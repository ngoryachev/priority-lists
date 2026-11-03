import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_activity_log_repository.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/data/services/activity_logger.dart';
import 'package:priority_lists/domain/models/activity_event.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';

/// Storage that rejects every write, to check an eviction is all-or-nothing.
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

/// Edge cases of the exclusive-`critical` rule that the main view-model suite
/// does not reach: repeated evictions, the other mutation paths, the filtered
/// drag, and the invariant holding across a whole session of edits.
void main() {
  late InMemoryPriorityNodeRepository repository;
  late NodeTreeViewModel vm;

  setUp(() {
    repository = InMemoryPriorityNodeRepository();
    vm = NodeTreeViewModel(repository);
  });

  PriorityNode raw(
    String id,
    Priority priority, {
    String? parentId,
    int position = 0,
    String? title,
  }) =>
      PriorityNode(
        id: id,
        parentId: parentId,
        title: title ?? id,
        priority: priority,
        position: position,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

  List<String> idsOf(String? parentId) =>
      vm.tree.childrenOf(parentId).map((n) => n.id).toList();

  Future<void> setCritical(String id) => vm.updateNode(
        vm.tree.nodeById(id)!.copyWith(priority: Priority.critical),
      );

  /// Every parent (and the top level) holds at most one red child.
  void expectAtMostOneRed() {
    final parents = <String?>{null, ...vm.tree.nodes.map((n) => n.id)};
    for (final parentId in parents) {
      final reds = vm.tree
          .childrenOf(parentId)
          .where((n) => n.priority == Priority.critical)
          .length;
      expect(reds, lessThanOrEqualTo(1),
          reason: 'parent $parentId shows $reds red children');
    }
  }

  group('repeated evictions', () {
    test('the newest demotion sits above the one before it', () async {
      await repository.saveNodes([
        raw('a', Priority.critical),
        raw('o', Priority.high, position: 1),
        raw('b', Priority.medium, position: 2),
        raw('c', Priority.medium, position: 3),
      ]);
      await vm.load();

      await setCritical('b'); // a -> high, parked above o
      await setCritical('c'); // b -> high, parked above a and o

      expect(idsOf(null), ['c', 'b', 'a', 'o']);
      expect(vm.tree.nodeById('a')!.priority, Priority.high);
      expect(vm.tree.nodeById('b')!.priority, Priority.high);
      expectAtMostOneRed();
    });

    test('a demoted node can take the slot back', () async {
      await repository.saveNodes([
        raw('a', Priority.critical),
        raw('o', Priority.high, position: 1),
        raw('b', Priority.medium, position: 2),
      ]);
      await vm.load();

      await setCritical('b');
      // 'a' was pushed to high; promoting it again must push 'b' down in turn.
      await setCritical('a');

      expect(idsOf(null), ['a', 'b', 'o']);
      expect(vm.tree.nodeById('b')!.priority, Priority.high);
      expectAtMostOneRed();
    });

    test('each parent is evicted on its own', () async {
      await repository.saveNodes([
        raw('p1', Priority.high),
        raw('p2', Priority.high, position: 1),
        raw('a1', Priority.critical, parentId: 'p1'),
        raw('b1', Priority.low, parentId: 'p1', position: 1),
        raw('a2', Priority.critical, parentId: 'p2'),
        raw('b2', Priority.low, parentId: 'p2', position: 1),
      ]);
      await vm.load();

      await setCritical('b1');
      await setCritical('b2');

      expect(idsOf('p1'), ['b1', 'a1']);
      expect(idsOf('p2'), ['b2', 'a2']);
      expect(vm.tree.nodeById('a1')!.priority, Priority.high);
      expect(vm.tree.nodeById('a2')!.priority, Priority.high);
      expectAtMostOneRed();
    });
  });

  group('what an eviction must not disturb', () {
    test('the edit dialog keeps its other fields while evicting', () async {
      await repository.saveNodes([
        raw('red', Priority.critical),
        raw('target', Priority.medium, position: 1, title: 'before'),
      ]);
      await vm.load();

      // One update carrying everything the form can change at once.
      await vm.updateNode(vm.tree.nodeById('target')!.copyWith(
            title: 'after',
            description: 'why it matters',
            priority: Priority.critical,
            colorPreset: ColorPreset.values.first,
          ));

      final stored = {
        for (final node in await repository.getAllNodes()) node.id: node,
      };
      expect(stored['target']!.title, 'after');
      expect(stored['target']!.description, 'why it matters');
      expect(stored['target']!.colorPreset, ColorPreset.values.first);
      expect(stored['target']!.priority, Priority.critical);
      expect(stored['red']!.priority, Priority.high);
    });

    test('the demoted node keeps its own fields and its subtree', () async {
      await repository.saveNodes([
        raw('red', Priority.critical, title: 'incumbent'),
        raw('kid', Priority.critical, parentId: 'red'),
        raw('target', Priority.low, position: 1),
      ]);
      await vm.load();

      await setCritical('target');

      final demoted = vm.tree.nodeById('red')!;
      expect(demoted.title, 'incumbent');
      expect(demoted.priority, Priority.high);
      // Only direct siblings are in scope: the child keeps its own red slot.
      expect(vm.tree.nodeById('kid')!.priority, Priority.critical);
      expect(idsOf('red'), ['kid']);
    });

    test('a red node one level down is not a sibling', () async {
      await repository.saveNodes([
        raw('root', Priority.high),
        raw('deep', Priority.critical, parentId: 'root'),
        raw('target', Priority.medium, position: 1),
      ]);
      await vm.load();

      await setCritical('target');

      expect(vm.tree.nodeById('deep')!.priority, Priority.critical);
      expect(vm.tree.nodeById('root')!.updatedAt, DateTime(2026),
          reason: 'an unrelated level is not rewritten');
    });
  });

  group('other ways into the red slot', () {
    test('a red node lifted to the top level evicts the red root', () async {
      await repository.saveNodes([
        raw('root', Priority.critical),
        raw('o', Priority.high, position: 1),
        raw('parent', Priority.medium, position: 2),
        raw('incoming', Priority.critical, parentId: 'parent'),
      ]);
      await vm.load();

      expect(await vm.moveNode('incoming', null), isTrue);

      expect(idsOf(null), ['incoming', 'root', 'o', 'parent']);
      expect(vm.tree.nodeById('root')!.priority, Priority.high);
      expectAtMostOneRed();
    });

    test('a move that brings no red leaves the slot alone', () async {
      await repository.saveNodes([
        raw('p', Priority.high),
        raw('red', Priority.critical, parentId: 'p'),
        raw('mover', Priority.high, position: 1),
      ]);
      await vm.load();

      expect(await vm.moveNode('mover', 'p'), isTrue);

      expect(vm.tree.nodeById('red')!.priority, Priority.critical);
      expectAtMostOneRed();
    });

    test('a filtered drag into the red group keeps the hidden sibling below',
        () async {
      await repository.saveNodes([
        raw('red', Priority.critical),
        raw('hidden', Priority.high, position: 1),
        raw('low', Priority.low, position: 2),
      ]);
      await vm.load();
      // The filter hides the high group, so the drag only sees red and low.
      final visible = vm.tree.roots
          .where((n) => n.priority != Priority.high)
          .toList();

      await vm.reorderChildren(
        parentId: null,
        visible: visible,
        oldIndex: 1,
        newIndex: 0,
      );

      expect(vm.tree.nodeById('low')!.priority, Priority.critical);
      expect(vm.tree.nodeById('red')!.priority, Priority.high);
      // The demoted red goes above the orange that was already there, even
      // though the filter kept that orange off screen.
      expect(idsOf(null), ['low', 'red', 'hidden']);
      expectAtMostOneRed();
    });

    test('a rejected drag into the red group changes nothing', () async {
      await repository.saveNodes([
        raw('red', Priority.critical),
        raw('o', Priority.high, position: 1),
        raw('low', Priority.low, position: 2),
      ]);
      final guarded = NodeTreeViewModel(_FailingRepository(repository));
      await guarded.load();

      expect(
        await guarded.reorderChildren(
          parentId: null,
          visible: guarded.tree.roots,
          oldIndex: 2,
          newIndex: 0,
        ),
        isFalse,
      );

      expect(guarded.tree.roots.map((n) => n.id), ['red', 'o', 'low']);
      expect(guarded.tree.nodeById('red')!.priority, Priority.critical);
      expect(guarded.tree.nodeById('low')!.priority, Priority.low);
    });

    test('a rejected create does not demote the incumbent', () async {
      await repository.saveNodes([raw('red', Priority.critical)]);
      final guarded = NodeTreeViewModel(_FailingRepository(repository));
      await guarded.load();

      expect(
        await guarded.addChild(title: 'new red', priority: Priority.critical),
        isNull,
      );

      expect(guarded.tree.roots.map((n) => n.id), ['red']);
      expect(guarded.tree.nodeById('red')!.priority, Priority.critical);
    });

    test('a rejected move does not demote the resident', () async {
      await repository.saveNodes([
        raw('p', Priority.high),
        raw('resident', Priority.critical, parentId: 'p'),
        raw('incoming', Priority.critical, position: 1),
      ]);
      final guarded = NodeTreeViewModel(_FailingRepository(repository));
      await guarded.load();

      expect(await guarded.moveNode('incoming', 'p'), isFalse);

      expect(guarded.tree.nodeById('resident')!.priority, Priority.critical);
      expect(guarded.tree.nodeById('incoming')!.parentId, isNull);
    });
  });

  test('the invariant survives a long session of mixed edits', () async {
    final parent = await vm.addChild(title: 'p', priority: Priority.high);
    final ids = <String>[];
    for (final priority in [
      Priority.critical,
      Priority.high,
      Priority.critical,
      Priority.low,
      Priority.critical,
      Priority.medium,
    ]) {
      final child = await vm.addChild(
        parentId: parent!.id,
        title: 'n${ids.length}',
        priority: priority,
      );
      ids.add(child!.id);
      expectAtMostOneRed();
    }

    for (final id in ids) {
      await setCritical(id);
      expectAtMostOneRed();
      expect(vm.tree.childrenOf(parent!.id).first.id, id,
          reason: 'the newest red leads its level');
    }

    // And a drag on the same level does not reintroduce a second red.
    await vm.reorderChildren(
      parentId: parent!.id,
      visible: vm.tree.childrenOf(parent.id),
      oldIndex: 4,
      newIndex: 0,
    );
    expectAtMostOneRed();
  });

  group('logging', () {
    test('siblings that were only renumbered are not logged', () async {
      final log = InMemoryActivityLogRepository();
      final logger = ActivityLogger(log);
      vm = NodeTreeViewModel(repository, logger: logger);
      await repository.saveNodes([
        raw('red', Priority.critical, title: 'red'),
        raw('o1', Priority.high, position: 1, title: 'o1'),
        raw('o2', Priority.high, position: 2, title: 'o2'),
        raw('target', Priority.medium, position: 3, title: 'target'),
      ]);
      await vm.load();

      await setCritical('target');
      await logger.idle;
      final events = (await log.recent()).reversed.toList();

      // Exactly two entries: the promotion and the one demotion it caused.
      expect(events.length, 2);
      expect(events.first.nodeTitle, 'target');
      expect(events.last.nodeTitle, 'red');
      expect(events.last.action, ActivityAction.prioritized);
      expect(
        events.map((e) => e.nodeTitle),
        isNot(anyElement(anyOf('o1', 'o2'))),
      );
    });

    test('a drag-triggered eviction logs the displaced node too', () async {
      final log = InMemoryActivityLogRepository();
      final logger = ActivityLogger(log);
      vm = NodeTreeViewModel(repository, logger: logger);
      await repository.saveNodes([
        raw('red', Priority.critical, title: 'red'),
        raw('low', Priority.low, position: 1, title: 'low'),
      ]);
      await vm.load();

      await vm.reorderChildren(
        parentId: null,
        visible: vm.tree.roots,
        oldIndex: 1,
        newIndex: 0,
      );
      await logger.idle;
      final events = (await log.recent()).reversed.toList();

      expect(events.last.nodeTitle, 'red');
      expect(events.last.details, contains('displaced by "low"'));
    });
  });
}
