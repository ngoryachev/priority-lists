import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_activity_log_repository.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/data/services/activity_logger.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';

/// Storage that can be made to fail, for the all-or-nothing checks.
class _FailingRepository implements PriorityNodeRepository {
  final PriorityNodeRepository inner;
  bool failWrites;
  bool failReads;

  _FailingRepository(this.inner, {this.failWrites = false,
      this.failReads = false});

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

/// The roles are the tree's top-level nodes: exactly one of them is red, that
/// one is the active role, and switching between them is a plain priority
/// write. This suite covers what that costs the level they live on.
void main() {
  late InMemoryPriorityNodeRepository repository;
  late NodeTreeViewModel vm;

  setUp(() {
    repository = InMemoryPriorityNodeRepository();
    vm = NodeTreeViewModel(repository);
  });

  PriorityNode role(
    String id,
    Priority priority, {
    int position = 0,
    String? parentId,
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

  /// Three roles in chip order, the first of them active.
  Future<void> seedRoles() async {
    await repository.saveNodes([
      role('work', Priority.critical),
      role('home', Priority.high, position: 1),
      role('rest', Priority.medium, position: 2),
    ]);
    await vm.load();
  }

  List<String> chipOrder() => vm.rolesInChipOrder.map((n) => n.id).toList();

  Future<void> switchTo(String id) =>
      vm.updateNode(vm.tree.nodeById(id)!.copyWith(priority: Priority.critical));

  group('switching the active role', () {
    test('the new role turns red and the old one drops to high', () async {
      await seedRoles();
      expect(vm.activeRole!.id, 'work');

      await switchTo('rest');

      expect(vm.activeRole!.id, 'rest');
      expect(vm.tree.nodeById('work')!.priority, Priority.high);
      expect(vm.tree.nodeById('rest')!.priority, Priority.critical);
      // In storage, not just in memory.
      final stored = {
        for (final node in await repository.getAllNodes()) node.id: node,
      };
      expect(stored['work']!.priority, Priority.high);
      expect(stored['rest']!.priority, Priority.critical);
    });

    test('the chips keep their order across repeated switches', () async {
      await seedRoles();
      expect(chipOrder(), ['work', 'home', 'rest']);

      await switchTo('rest');
      expect(chipOrder(), ['work', 'home', 'rest']);
      await switchTo('home');
      expect(chipOrder(), ['work', 'home', 'rest']);
      await switchTo('work');
      expect(chipOrder(), ['work', 'home', 'rest']);

      // Which is to say: the roles level is never renumbered.
      final stored = {
        for (final node in await repository.getAllNodes()) node.id: node,
      };
      expect(stored['work']!.position, 0);
      expect(stored['home']!.position, 1);
      expect(stored['rest']!.position, 2);
    });

    test('only the two roles whose priority changed are written', () async {
      await seedRoles();
      final untouched = vm.tree.nodeById('home')!.updatedAt;

      await switchTo('rest');

      expect(vm.tree.nodeById('home')!.updatedAt, untouched);
    });

    test('the switch and the role it displaced are both logged', () async {
      final log = InMemoryActivityLogRepository();
      final logger = ActivityLogger(log);
      vm = NodeTreeViewModel(repository, logger: logger);
      await seedRoles();

      await switchTo('rest');
      await logger.idle;
      final events = (await log.recent()).reversed.toList();

      expect(events.map((e) => e.nodeTitle), ['rest', 'work']);
      expect(events.last.details, contains('displaced by "rest"'));
    });

    test('a level below the roles still renumbers on an eviction', () async {
      await repository.saveNodes([
        role('work', Priority.critical),
        role('red', Priority.critical, parentId: 'work'),
        role('orange', Priority.high, parentId: 'work', position: 1),
        role('target', Priority.low, parentId: 'work', position: 2),
      ]);
      await vm.load();

      await switchTo('target');

      expect(
        vm.tree.childrenOf('work').map((n) => n.id),
        ['target', 'red', 'orange'],
      );
      expect(vm.tree.nodeById('red')!.position, 1);
    });
  });

  group('moveRole', () {
    test('swaps a role with its neighbour and renumbers the level', () async {
      await seedRoles();

      expect(await vm.moveRole(id: 'rest', delta: -1), isTrue);

      expect(chipOrder(), ['work', 'rest', 'home']);
      final stored = {
        for (final node in await repository.getAllNodes()) node.id: node,
      };
      expect(stored['rest']!.position, 1);
      expect(stored['home']!.position, 2);
    });

    test('never touches a priority, so it cannot switch roles', () async {
      await seedRoles();

      await vm.moveRole(id: 'work', delta: 1);

      expect(chipOrder(), ['home', 'work', 'rest']);
      expect(vm.activeRole!.id, 'work');
      expect(vm.tree.nodeById('home')!.priority, Priority.high);
    });

    test('is a no-op at either end of the row', () async {
      await seedRoles();
      final before = vm.tree.nodes.map((n) => n.updatedAt).toList();

      expect(await vm.moveRole(id: 'work', delta: -1), isFalse);
      expect(await vm.moveRole(id: 'rest', delta: 1), isFalse);

      expect(chipOrder(), ['work', 'home', 'rest']);
      expect(vm.tree.nodes.map((n) => n.updatedAt), before);
    });

    test('an unknown role is refused', () async {
      await seedRoles();
      expect(await vm.moveRole(id: 'nope', delta: 1), isFalse);
    });

    test('a rejected write leaves the order alone', () async {
      await seedRoles();
      final guarded = NodeTreeViewModel(
        _FailingRepository(repository, failWrites: true),
      );
      await guarded.load();

      expect(await guarded.moveRole(id: 'rest', delta: -1), isFalse);

      expect(
        guarded.rolesInChipOrder.map((n) => n.id),
        ['work', 'home', 'rest'],
      );
    });
  });

  group('deleteRole', () {
    test('deleting the active role promotes the next one', () async {
      await seedRoles();

      await vm.deleteRole('work');

      expect(vm.tree.nodeById('work'), isNull);
      expect(vm.activeRole!.id, 'home');
      expect(vm.tree.nodeById('home')!.priority, Priority.critical);
      // Chip order is what it was, minus the role that went.
      expect(chipOrder(), ['home', 'rest']);
    });

    test('deleting an inactive role leaves the red where it is', () async {
      await seedRoles();
      final untouched = vm.tree.nodeById('work')!.updatedAt;

      await vm.deleteRole('rest');

      expect(vm.activeRole!.id, 'work');
      expect(vm.tree.nodeById('work')!.updatedAt, untouched);
      expect(chipOrder(), ['work', 'home']);
    });

    test('the subtree goes with the role', () async {
      await repository.saveNodes([
        role('work', Priority.critical),
        role('task', Priority.high, parentId: 'work'),
        role('home', Priority.high, position: 1),
      ]);
      await vm.load();

      await vm.deleteRole('work');

      expect(vm.tree.nodeById('task'), isNull);
      expect(vm.activeRole!.id, 'home');
    });

    test('a rejected delete promotes nobody', () async {
      await seedRoles();
      final guarded = NodeTreeViewModel(
        _FailingRepository(repository, failWrites: true),
      );
      await guarded.load();

      await guarded.deleteRole('work');

      expect(guarded.tree.nodeById('work')!.priority, Priority.critical);
      expect(guarded.activeRole!.id, 'work');
    });
  });

  group('the default role', () {
    test('an empty tree gets one red Root on load', () async {
      await vm.load();

      expect(vm.tree.roots.map((n) => n.title), ['Root']);
      expect(vm.activeRole!.priority, Priority.critical);
      // Written through the repository, not just held in memory.
      expect((await repository.getAllNodes()).single.title, 'Root');
    });

    test('a tree that already has roles is left alone', () async {
      await seedRoles();
      expect(vm.tree.nodes, hasLength(3));

      await vm.load();

      expect(vm.tree.nodes, hasLength(3));
      expect(vm.activeRole!.id, 'work');
    });

    test('a read that failed creates nothing', () async {
      final guarded = NodeTreeViewModel(
        _FailingRepository(repository, failReads: true),
      );

      await guarded.load();

      expect(guarded.error, isNotNull);
      expect(guarded.tree.isEmpty, isTrue);
      expect(await repository.getAllNodes(), isEmpty);
    });

    /// The create goes through the same write path as everything else, and
    /// that path re-reads the tree when a write is rejected — which must not
    /// turn into an endless retry.
    test('a rejected create does not loop', () async {
      final guarded = NodeTreeViewModel(
        _FailingRepository(repository, failWrites: true),
      );

      await guarded.load();

      expect(guarded.tree.isEmpty, isTrue);
      expect(guarded.error, isNotNull);
      expect(await repository.getAllNodes(), isEmpty);
    });
  });
}
