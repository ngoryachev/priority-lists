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

  _FailingRepository(this.inner);

  @override
  Future<List<PriorityNode>> getAllNodes() => inner.getAllNodes();

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
