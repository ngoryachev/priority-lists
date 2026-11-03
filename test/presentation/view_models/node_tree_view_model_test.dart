import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';

/// Repository that fails every write, to check the view model does not keep a
/// change the storage rejected.
class _FailingRepository implements PriorityNodeRepository {
  final PriorityNodeRepository inner;
  bool failWrites = true;
  bool failReads = false;

  _FailingRepository(this.inner);

  @override
  Future<List<PriorityNode>> getAllNodes() {
    if (failReads) throw Exception('offline');
    return inner.getAllNodes();
  }

  @override
  Future<void> saveNode(PriorityNode node) async {
    if (failWrites) throw Exception('nope');
    await inner.saveNode(node);
  }

  @override
  Future<void> saveNodes(List<PriorityNode> nodes) async {
    if (failWrites) throw Exception('nope');
    await inner.saveNodes(nodes);
  }

  @override
  Future<void> deleteNode(String id) async {
    if (failWrites) throw Exception('nope');
    await inner.deleteNode(id);
  }
}

void main() {
  late InMemoryPriorityNodeRepository repository;
  late NodeTreeViewModel vm;

  setUp(() {
    repository = InMemoryPriorityNodeRepository();
    vm = NodeTreeViewModel(repository);
  });

  group('refresh', () {
    test('quietly picks up rows written elsewhere', () async {
      vm = NodeTreeViewModel(repository, minRefreshAge: Duration.zero);
      await vm.load();
      final seen = <bool>[];
      vm.addListener(() => seen.add(vm.isLoading));

      await repository.saveNode(PriorityNode(
        id: 'x',
        title: 'From another device',
        priority: Priority.low,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));
      await vm.refresh();

      expect(vm.tree.nodeById('x'), isNotNull);
      expect(seen, [false], reason: 'no loading flip, just one settle');
    });

    test('skips the round-trip while the tree is fresh', () async {
      vm = NodeTreeViewModel(
        repository,
        minRefreshAge: const Duration(hours: 1),
      );
      await vm.load();
      await repository.saveNode(PriorityNode(
        id: 'x',
        title: 'Late',
        priority: Priority.low,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ));

      await vm.refresh();

      expect(vm.tree.nodeById('x'), isNull);
    });

    test('keeps the current tree when the read fails', () async {
      final failing = _FailingRepository(repository)..failWrites = false;
      vm = NodeTreeViewModel(failing, minRefreshAge: Duration.zero);
      await vm.addChild(title: 'Keep me', priority: Priority.low);
      await vm.load();

      failing.failReads = true;
      await vm.refresh();

      expect(vm.tree.roots.map((n) => n.title), ['Keep me']);
      expect(vm.error, isNull);
    });
  });

  /// Builds root → a → a1 and returns their ids.
  Future<(String, String, String)> seedChain() async {
    final root = await vm.addChild(title: 'root', priority: Priority.high);
    final a = await vm.addChild(
      parentId: root!.id,
      title: 'a',
      priority: Priority.medium,
    );
    final a1 = await vm.addChild(
      parentId: a!.id,
      title: 'a1',
      priority: Priority.low,
    );
    return (root.id, a.id, a1!.id);
  }

  group('NodeTreeViewModel', () {
    test('load pulls the flat tree from storage', () async {
      await repository.saveNodes([
        PriorityNode(
          id: 'r',
          title: 'root',
          priority: Priority.high,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ]);

      await vm.load();

      expect(vm.tree.roots.map((n) => n.title), ['root']);
      expect(vm.isLoading, isFalse);
      expect(vm.error, isNull);
    });

    test('nests children arbitrarily deep', () async {
      var parentId = (await vm.addChild(title: 'l0', priority: Priority.high))!.id;
      for (var depth = 1; depth <= 8; depth++) {
        parentId = (await vm.addChild(
          parentId: parentId,
          title: 'l$depth',
          priority: Priority.medium,
        ))!
            .id;
      }

      expect(vm.tree.nodes, hasLength(9));
      expect(vm.tree.depthOf(parentId), 8);
      expect(vm.tree.pathTo(parentId).map((n) => n.title).first, 'l0');
    });

    test('updating a node keeps its place in the tree', () async {
      final (_, aId, _) = await seedChain();

      await vm.updateNode(
        vm.tree.nodeById(aId)!.copyWith(title: 'renamed'),
      );

      expect(vm.tree.nodeById(aId)!.title, 'renamed');
      expect(vm.tree.childrenOf(aId).map((n) => n.title), ['a1']);
    });

    test('deleting a node removes its whole subtree', () async {
      final (rootId, aId, a1Id) = await seedChain();

      await vm.deleteNode(aId);

      expect(vm.tree.nodeById(aId), isNull);
      expect(vm.tree.nodeById(a1Id), isNull);
      expect(vm.tree.nodeById(rootId), isNotNull);
      expect(await repository.getAllNodes(), hasLength(1));
    });

    test('moving a node carries its subtree along', () async {
      final (rootId, aId, a1Id) = await seedChain();
      final other = await vm.addChild(title: 'other', priority: Priority.high);

      expect(await vm.moveNode(aId, other!.id), isTrue);

      expect(vm.tree.childrenOf(rootId), isEmpty);
      expect(vm.tree.childrenOf(other.id).map((n) => n.id), [aId]);
      // The subtree is untouched: a1 still hangs off a, now one level deeper.
      expect(vm.tree.childrenOf(aId).map((n) => n.id), [a1Id]);
      expect(vm.tree.depthOf(a1Id), 2);
    });

    test('moving to the top level detaches the node from its parent', () async {
      final (rootId, aId, _) = await seedChain();

      expect(await vm.moveNode(aId, null), isTrue);

      expect(vm.tree.nodeById(aId)!.isRoot, isTrue);
      expect(vm.tree.roots.map((n) => n.id), containsAll([rootId, aId]));
    });

    test('refuses a move into itself or its own subtree', () async {
      final (_, aId, a1Id) = await seedChain();

      expect(await vm.moveNode(aId, aId), isFalse);
      expect(await vm.moveNode(aId, a1Id), isFalse);
      // The tree is unchanged by the refusal.
      expect(vm.tree.childrenOf(aId).map((n) => n.id), [a1Id]);
    });

    test('move targets never include the node or its descendants', () async {
      final (rootId, aId, a1Id) = await seedChain();

      final targets = vm.moveTargetsFor(aId).map((n) => n.id);
      expect(targets, [rootId]);
      expect(targets, isNot(contains(aId)));
      expect(targets, isNot(contains(a1Id)));
    });

    group('reordering', () {
      /// Four siblings: two high, two low — the shape a filtered drag has to
      /// cope with. Deliberately not critical: that priority is exclusive
      /// among siblings (see the `exclusive critical` group), which would mix
      /// an eviction into every drag here.
      Future<List<String>> seedLevel() async {
        final ids = <String>[];
        for (final entry in [
          ('h1', Priority.high),
          ('h2', Priority.high),
          ('l1', Priority.low),
          ('l2', Priority.low),
        ]) {
          final node = await vm.addChild(title: entry.$1, priority: entry.$2);
          ids.add(node!.id);
        }
        return ids;
      }

      List<String> titlesOf(String? parentId) =>
          vm.tree.childrenOf(parentId).map((n) => n.title).toList();

      test('moves a node within its priority group', () async {
        await seedLevel();
        final visible = vm.tree.roots;

        expect(
          await vm.reorderChildren(
            parentId: null,
            visible: visible,
            oldIndex: 1,
            newIndex: 0,
          ),
          isTrue,
        );

        expect(titlesOf(null), ['h2', 'h1', 'l1', 'l2']);
        // The new order is what storage holds, not just what the screen shows.
        final stored = await repository.getAllNodes()
          ..sort((a, b) => a.position.compareTo(b.position));
        expect(stored.map((n) => n.title), ['h2', 'h1', 'l1', 'l2']);
      });

      test('adopts the priority of the group it is dropped into', () async {
        await seedLevel();

        // Drag the first low node up between the two high ones.
        await vm.reorderChildren(
          parentId: null,
          visible: vm.tree.roots,
          oldIndex: 2,
          newIndex: 1,
        );

        expect(titlesOf(null), ['h1', 'l1', 'h2', 'l2']);
        expect(vm.tree.roots[1].priority, Priority.high,
            reason: 'dropped among high nodes, so it became high');
      });

      test('keeps its priority when dropped on its own boundary', () async {
        await seedLevel();

        // Move the second high node to the head of its own group.
        await vm.reorderChildren(
          parentId: null,
          visible: vm.tree.roots,
          oldIndex: 1,
          newIndex: 0,
        );

        expect(vm.tree.roots.first.title, 'h2');
        expect(vm.tree.roots.first.priority, Priority.high);
      });

      test('leaves filtered-out siblings where they were', () async {
        await seedLevel();
        // The user is filtering to high only, so the low nodes are hidden.
        final visible = vm.tree.roots
            .where((n) => n.priority == Priority.high)
            .toList();

        await vm.reorderChildren(
          parentId: null,
          visible: visible,
          oldIndex: 1,
          newIndex: 0,
        );

        // Visible nodes swapped; the hidden ones neither moved nor changed
        // priority just because they were off-screen.
        expect(titlesOf(null), ['h2', 'h1', 'l1', 'l2']);
        expect(
          vm.tree.roots.where((n) => n.priority == Priority.low).length,
          2,
        );
      });

      test('a hidden node stays with the sibling it followed', () async {
        await seedLevel();
        // Hide only 'h2' by pretending the filter shows everything else.
        final all = vm.tree.roots;
        final visible = [all[0], all[2], all[3]];

        // Move 'l2' (last visible) to the front.
        await vm.reorderChildren(
          parentId: null,
          visible: visible,
          oldIndex: 2,
          newIndex: 0,
        );

        // 'h2' followed 'h1' before the drag, and still does.
        final order = titlesOf(null);
        expect(order.indexOf('h2'), order.indexOf('h1') + 1);
      });

      test('a no-op drag writes nothing', () async {
        await seedLevel();
        final before = vm.tree.roots.map((n) => n.updatedAt).toList();

        expect(
          await vm.reorderChildren(
            parentId: null,
            visible: vm.tree.roots,
            oldIndex: 1,
            newIndex: 2,
          ),
          isTrue,
        );

        expect(vm.tree.roots.map((n) => n.updatedAt), before);
      });

      test('reordering deep in the tree touches only that level', () async {
        final root = await vm.addChild(title: 'root', priority: Priority.high);
        for (final title in ['a', 'b', 'c']) {
          await vm.addChild(
            parentId: root!.id,
            title: title,
            priority: Priority.high,
          );
        }
        final otherRoot =
            await vm.addChild(title: 'other', priority: Priority.high);

        await vm.reorderChildren(
          parentId: root!.id,
          visible: vm.tree.childrenOf(root.id),
          oldIndex: 2,
          newIndex: 0,
        );

        expect(titlesOf(root.id), ['c', 'a', 'b']);
        expect(vm.tree.nodeById(otherRoot!.id)!.position, 0);
      });
    });

    /// `critical` is exclusive among direct siblings: a parent never shows two
    /// red children, so whoever turns red pushes the incumbent down to `high`
    /// and parks it directly above the oranges that were already there.
    group('exclusive critical', () {
      /// A node written straight into storage. Seeding through the repository
      /// instead of the view model is the only way to set up a level that
      /// already holds two reds — which is exactly what the rule has to resolve
      /// in data written before it existed.
      PriorityNode raw(
        String id,
        Priority priority, {
        String? parentId,
        int position = 0,
      }) =>
          PriorityNode(
            id: id,
            parentId: parentId,
            title: id,
            priority: priority,
            position: position,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          );

      List<String> idsOf(String? parentId) =>
          vm.tree.childrenOf(parentId).map((n) => n.id).toList();

      test('the demoted red lands above the oranges already there', () async {
        await repository.saveNodes([
          raw('p', Priority.high),
          raw('red', Priority.critical, parentId: 'p'),
          raw('o1', Priority.high, parentId: 'p', position: 1),
          raw('o2', Priority.high, parentId: 'p', position: 2),
          raw('target', Priority.medium, parentId: 'p', position: 3),
        ]);
        await vm.load();

        await vm.updateNode(
          vm.tree.nodeById('target')!.copyWith(priority: Priority.critical),
        );

        expect(idsOf('p'), ['target', 'red', 'o1', 'o2']);
        expect(vm.tree.nodeById('target')!.priority, Priority.critical);
        expect(vm.tree.nodeById('red')!.priority, Priority.high);
        // The whole eviction is in storage, not just in memory.
        final stored = {
          for (final node in await repository.getAllNodes()) node.id: node,
        };
        expect(stored['red']!.priority, Priority.high);
        expect(stored['red']!.position, lessThan(stored['o1']!.position));
      });

      test('two reds pushed down keep their relative order', () async {
        await repository.saveNodes([
          raw('r1', Priority.critical),
          raw('r2', Priority.critical, position: 1),
          raw('o', Priority.high, position: 2),
          raw('m', Priority.medium, position: 3),
        ]);
        await vm.load();

        // Top level, so the rule has to hold for parentId == null too.
        await vm.updateNode(
          vm.tree.nodeById('m')!.copyWith(priority: Priority.critical),
        );

        expect(idsOf(null), ['m', 'r1', 'r2', 'o']);
        expect(vm.tree.nodeById('r1')!.priority, Priority.high);
        expect(vm.tree.nodeById('r2')!.priority, Priority.high);
      });

      test('another parent keeps its own red child', () async {
        await repository.saveNodes([
          raw('p1', Priority.high),
          raw('p2', Priority.high, position: 1),
          raw('a', Priority.critical, parentId: 'p1'),
          raw('b', Priority.low, parentId: 'p1', position: 1),
          raw('c', Priority.critical, parentId: 'p2'),
        ]);
        await vm.load();

        await vm.updateNode(
          vm.tree.nodeById('b')!.copyWith(priority: Priority.critical),
        );

        expect(idsOf('p1'), ['b', 'a']);
        expect(vm.tree.nodeById('a')!.priority, Priority.high);
        expect(vm.tree.nodeById('c')!.priority, Priority.critical);
        // The level the two parents live on is not renumbered either.
        expect(vm.tree.nodeById('p1')!.position, 0);
        expect(vm.tree.nodeById('p2')!.position, 1);
      });

      test('re-saving a node that is already red leaves the level alone',
          () async {
        await repository.saveNodes([
          raw('red', Priority.critical),
          raw('o', Priority.high, position: 1),
        ]);
        await vm.load();
        final untouched = vm.tree.nodeById('o')!.updatedAt;

        await vm.updateNode(
          vm.tree.nodeById('red')!.copyWith(title: 'renamed'),
        );

        expect(vm.tree.nodeById('o')!.updatedAt, untouched);
        expect(vm.tree.nodeById('o')!.priority, Priority.high);
      });

      test('a node created as critical takes the slot', () async {
        final parent = await vm.addChild(title: 'p', priority: Priority.high);
        final first = await vm.addChild(
          parentId: parent!.id,
          title: 'first',
          priority: Priority.critical,
        );
        final second = await vm.addChild(
          parentId: parent.id,
          title: 'second',
          priority: Priority.critical,
        );

        expect(vm.tree.nodeById(second!.id)!.priority, Priority.critical);
        expect(vm.tree.nodeById(first!.id)!.priority, Priority.high);
        expect(
          vm.tree.childrenOf(parent.id).map((n) => n.title),
          ['second', 'first'],
        );
      });

      test('a red node moved in demotes the red child it finds', () async {
        await repository.saveNodes([
          raw('p', Priority.high),
          raw('resident', Priority.critical, parentId: 'p'),
          raw('orange', Priority.high, parentId: 'p', position: 1),
          raw('incoming', Priority.critical, position: 1),
        ]);
        await vm.load();

        expect(await vm.moveNode('incoming', 'p'), isTrue);

        expect(idsOf('p'), ['incoming', 'resident', 'orange']);
        expect(vm.tree.nodeById('resident')!.priority, Priority.high);
      });

      test('a drag into the red group evicts the node that was red', () async {
        await repository.saveNodes([
          raw('r', Priority.critical),
          raw('o', Priority.high, position: 1),
          raw('low', Priority.low, position: 2),
        ]);
        await vm.load();

        // Drop the low node on top of the level, i.e. into the red group.
        await vm.reorderChildren(
          parentId: null,
          visible: vm.tree.roots,
          oldIndex: 2,
          newIndex: 0,
        );

        expect(vm.tree.nodeById('low')!.priority, Priority.critical);
        expect(vm.tree.nodeById('r')!.priority, Priority.high);
        expect(idsOf(null), ['low', 'r', 'o']);
      });

      test('a rejected eviction leaves the level exactly as it was', () async {
        await repository.saveNodes([
          raw('r', Priority.critical),
          raw('o', Priority.high, position: 1),
          raw('m', Priority.medium, position: 2),
        ]);
        final guarded = NodeTreeViewModel(_FailingRepository(repository));
        await guarded.load();

        await guarded.updateNode(
          guarded.tree.nodeById('m')!.copyWith(priority: Priority.critical),
        );

        expect(guarded.error, isNotNull);
        expect(guarded.tree.roots.map((n) => n.id), ['r', 'o', 'm']);
        expect(guarded.tree.nodeById('r')!.priority, Priority.critical,
            reason: 'no half-applied eviction');
        expect(guarded.tree.nodeById('m')!.priority, Priority.medium);
      });
    });

    test('a rejected write is not kept in memory', () async {
      final failing = _FailingRepository(repository);
      final guarded = NodeTreeViewModel(failing);

      final created = await guarded.addChild(
        title: 'ghost',
        priority: Priority.high,
      );

      expect(created, isNull);
      expect(guarded.error, isNotNull);
      expect(guarded.tree.nodes, isEmpty);
    });
  });
}
