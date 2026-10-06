import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_activity_log_repository.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/data/services/activity_logger.dart';
import 'package:priority_lists/domain/models/activity_event.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/activity_log_repository.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';

/// Log that refuses every write — the tree must not notice.
class _BrokenLog implements ActivityLogRepository {
  @override
  Future<void> append(ActivityEvent event) async => throw Exception('no table');

  @override
  Future<List<ActivityEvent>> recent({int limit = 500, DateTime? since}) async =>
      throw Exception('no table');
}

/// Node storage that refuses every write, to check nothing is logged for a
/// mutation that never happened.
class _ReadOnlyRepository implements PriorityNodeRepository {
  final PriorityNodeRepository inner;

  _ReadOnlyRepository(this.inner);

  @override
  Future<List<PriorityNode>> getAllNodes() => inner.getAllNodes();

  @override
  Future<void> saveNode(PriorityNode node) async => throw Exception('nope');

  @override
  Future<void> saveNodes(List<PriorityNode> nodes) async =>
      throw Exception('nope');

  @override
  Future<void> deleteNode(String id) async => throw Exception('nope');
}

void main() {
  late InMemoryPriorityNodeRepository repository;
  late InMemoryActivityLogRepository log;
  late NodeTreeViewModel vm;
  late ActivityLogger logger;

  setUp(() {
    repository = InMemoryPriorityNodeRepository();
    log = InMemoryActivityLogRepository();
    logger = ActivityLogger(log);
    vm = NodeTreeViewModel(repository, logger: logger);
  });

  /// The log, oldest first, once every queued write has landed.
  Future<List<ActivityEvent>> entries() async {
    await logger.idle;
    final events = await log.recent();
    return events.reversed.toList();
  }

  Future<PriorityNode> seed(String title, {String? parentId}) async {
    final node = await vm.addChild(
      parentId: parentId,
      title: title,
      priority: Priority.medium,
    );
    return node!;
  }

  test('records an added node with its priority and its parent path', () async {
    final root = await seed('Work');
    await seed('Fix login', parentId: root.id);

    final events = await entries();
    expect(events.map((e) => e.action),
        [ActivityAction.created, ActivityAction.created]);
    expect(events.last.nodeTitle, 'Fix login');
    expect(events.last.path, ['Work']);
    expect(events.last.details, 'Medium');
  });

  test('a priority-only change is logged as a re-prioritisation', () async {
    final node = await seed('Fix login');
    await vm.updateNode(node.copyWith(priority: Priority.critical));

    final event = (await entries()).last;
    expect(event.action, ActivityAction.prioritized);
    expect(event.details, 'Medium → Critical');
  });

  test('an edit names the fields that changed', () async {
    final node = await seed('Fix login');
    await vm.updateNode(node.copyWith(
      title: 'Fix logout',
      description: 'with the new session code',
      colorPreset: ColorPreset.values.first,
    ));

    final event = (await entries()).last;
    expect(event.action, ActivityAction.updated);
    expect(event.details, contains('title "Fix login" → "Fix logout"'));
    expect(event.details, contains('description'));
    expect(event.details, contains('colour'));
  });

  test('an update that changes nothing is not logged', () async {
    final node = await seed('Fix login');
    await vm.updateNode(node);

    expect((await entries()).length, 1); // the creation only
  });

  test('a move records both ends of the trip', () async {
    final work = await seed('Work');
    final home = await seed('Home');
    final task = await seed('Fix login', parentId: work.id);

    await vm.moveNode(task.id, home.id);

    final event = (await entries()).last;
    expect(event.action, ActivityAction.moved);
    expect(event.details, 'Work → Home');
    expect(event.path, ['Home']);
  });

  test('a move back to the top level says so', () async {
    final work = await seed('Work');
    final task = await seed('Fix login', parentId: work.id);

    await vm.moveNode(task.id, null);

    final event = (await entries()).last;
    expect(event.details, 'Work → top level');
    expect(event.path, isEmpty);
  });

  test('a delete counts what went with it', () async {
    final work = await seed('Work');
    await seed('Fix login', parentId: work.id);
    await seed('Fix logout', parentId: work.id);

    await vm.deleteNode(work.id);

    final event = (await entries()).last;
    expect(event.action, ActivityAction.deleted);
    expect(event.nodeTitle, 'Work');
    expect(event.details, 'with 2 nested');
  });

  test('a drag logs the dragged node only', () async {
    final first = await seed('First');
    await seed('Second');
    await seed('Third');
    final before = (await entries()).length;

    final visible = vm.tree.childrenOf(null);
    await vm.reorderChildren(
      parentId: null,
      visible: visible,
      oldIndex: 0,
      newIndex: 3,
    );

    final events = await entries();
    expect(events.length, before + 1);
    expect(events.last.action, ActivityAction.reordered);
    expect(events.last.nodeTitle, first.title);
    expect(events.last.details, contains('rank 1 → 3'));
  });

  test('a log that cannot be written does not break the mutation', () async {
    final failing = NodeTreeViewModel(
      repository,
      logger: ActivityLogger(_BrokenLog()),
    );
    final node = await failing.addChild(
      title: 'Still saved',
      priority: Priority.high,
    );

    expect(node, isNotNull);
    expect(failing.error, isNull);
    expect(failing.tree.nodes.map((n) => n.title), contains('Still saved'));
  });

  test('a rejected mutation is not logged', () async {
    final seeded = await seed('Work');
    final before = (await entries()).length;

    final blocked = NodeTreeViewModel(
      _ReadOnlyRepository(repository),
      logger: logger,
    );
    await blocked.load();
    await blocked.addChild(title: 'Never saved', priority: Priority.low);
    await blocked.updateNode(seeded.copyWith(priority: Priority.critical));
    await blocked.deleteNode(seeded.id);

    expect((await entries()).length, before);
  });
}
