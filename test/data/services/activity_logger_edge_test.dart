import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_activity_log_repository.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/data/services/activity_logger.dart';
import 'package:priority_lists/domain/models/activity_event.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/activity_log_repository.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';

/// A log whose writes only finish when the test lets them.
class _GatedLog implements ActivityLogRepository {
  final Completer<void> gate;
  final List<ActivityEvent> written = [];
  int started = 0;

  _GatedLog(this.gate);

  @override
  Future<void> append(ActivityEvent event) async {
    started++;
    await gate.future;
    written.add(event);
  }

  @override
  Future<List<ActivityEvent>> recent({int limit = 500, DateTime? since}) async =>
      List.of(written);
}

/// A log where the first write is slow, to prove entries are not interleaved.
class _SlowFirstLog implements ActivityLogRepository {
  final List<String> written = [];
  bool first = true;

  @override
  Future<void> append(ActivityEvent event) async {
    if (first) {
      first = false;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    written.add(event.nodeTitle);
  }

  @override
  Future<List<ActivityEvent>> recent({int limit = 500, DateTime? since}) async =>
      const [];
}

void main() {
  late InMemoryPriorityNodeRepository repository;
  late InMemoryActivityLogRepository log;
  late ActivityLogger logger;
  late NodeTreeViewModel vm;

  setUp(() {
    repository = InMemoryPriorityNodeRepository();
    log = InMemoryActivityLogRepository();
    logger = ActivityLogger(log);
    vm = NodeTreeViewModel(repository, logger: logger);
  });

  /// The log, oldest first, once every queued write has landed.
  Future<List<ActivityEvent>> entries() async {
    await logger.idle;
    return (await log.recent()).reversed.toList();
  }

  Future<PriorityNode> seed(
    String title, {
    String? parentId,
    Priority priority = Priority.medium,
  }) async {
    final node = await vm.addChild(
      parentId: parentId,
      title: title,
      priority: priority,
    );
    return node!;
  }

  group('paths', () {
    test('an addition three levels down records the whole chain', () async {
      final work = await seed('Work');
      final backend = await seed('Backend', parentId: work.id);
      await seed('Fix login', parentId: backend.id);

      final event = (await entries()).last;
      expect(event.path, ['Work', 'Backend']);
      expect(event.pathLabel, 'Work › Backend');
    });

    test('a move into a nested parent names both chains in full', () async {
      final work = await seed('Work');
      final backend = await seed('Backend', parentId: work.id);
      final home = await seed('Home');
      final task = await seed('Fix login', parentId: home.id);

      await vm.moveNode(task.id, backend.id);

      final event = (await entries()).last;
      expect(event.action, ActivityAction.moved);
      expect(event.details, 'Home → Work › Backend');
      expect(event.path, ['Work', 'Backend']);
    });

    test('a move refused as a cycle is not logged', () async {
      final work = await seed('Work');
      final backend = await seed('Backend', parentId: work.id);
      final before = (await entries()).length;

      expect(await vm.moveNode(work.id, backend.id), isFalse);

      expect((await entries()).length, before);
    });
  });

  group('survival of the node', () {
    test('the entry keeps the title and place of a node that is gone',
        () async {
      final work = await seed('Work');
      final task = await seed('Fix login', parentId: work.id);

      await vm.deleteNode(task.id);

      expect(vm.tree.nodeById(task.id), isNull);
      final event = (await entries()).last;
      expect(event.action, ActivityAction.deleted);
      expect(event.nodeTitle, 'Fix login');
      expect(event.path, ['Work']);
      expect(event.nodeId, task.id);
    });

    test('a leaf delete says nothing about nesting', () async {
      await seed('Fix login');
      await vm.deleteNode(vm.tree.nodes.single.id);

      expect((await entries()).last.details, isEmpty);
    });
  });

  group('writing', () {
    test('the mutation does not wait for the log to be written', () async {
      final gate = Completer<void>();
      final gated = _GatedLog(gate);
      final slowLogger = ActivityLogger(gated);
      final slowVm = NodeTreeViewModel(repository, logger: slowLogger);

      final node = await slowVm.addChild(
        title: 'Fix login',
        priority: Priority.high,
      );

      expect(node, isNotNull, reason: 'the write returned without the log');
      expect(gated.written, isEmpty, reason: 'the log is still in flight');

      gate.complete();
      await slowLogger.idle;
      expect(gated.written, hasLength(1));
    });

    test('entries land in the order the mutations happened', () async {
      final slow = _SlowFirstLog();
      final orderedLogger = ActivityLogger(slow);
      final orderedVm = NodeTreeViewModel(repository, logger: orderedLogger);

      await orderedVm.addChild(title: 'First', priority: Priority.medium);
      await orderedVm.addChild(title: 'Second', priority: Priority.medium);
      await orderedLogger.idle;

      expect(slow.written, ['First', 'Second']);
    });

    test('one failed write does not stop the next one', () async {
      final flaky = _FlakyLog();
      final flakyLogger = ActivityLogger(flaky);
      final flakyVm = NodeTreeViewModel(repository, logger: flakyLogger);

      await flakyVm.addChild(title: 'First', priority: Priority.medium);
      await flakyVm.addChild(title: 'Second', priority: Priority.medium);
      await flakyLogger.idle;

      expect(flaky.written, ['Second']);
    });
  });

  group('drags', () {
    test('a drag into another priority group records the new priority',
        () async {
      await seed('A', priority: Priority.critical);
      await seed('B', priority: Priority.critical);
      await seed('C', priority: Priority.low);
      final d = await seed('D', priority: Priority.low);
      final before = (await entries()).length;

      final visible = vm.tree.childrenOf(null);
      expect(visible.map((n) => n.title), ['A', 'B', 'C', 'D']);
      await vm.reorderChildren(
        parentId: null,
        visible: visible,
        oldIndex: 3,
        newIndex: 0,
      );

      expect(vm.tree.nodeById(d.id)!.priority, Priority.critical);
      final events = await entries();
      expect(events.length, before + 1);
      expect(events.last.action, ActivityAction.reordered);
      expect(events.last.nodeTitle, 'D');
      expect(events.last.details, contains('Low → Critical'));
    });

    test('a drag to the front of the level is logged', () async {
      await seed('First');
      await seed('Second');
      final third = await seed('Third');
      final before = (await entries()).length;

      final visible = vm.tree.childrenOf(null);
      expect(visible.map((n) => n.title), ['First', 'Second', 'Third']);
      await vm.reorderChildren(
        parentId: null,
        visible: visible,
        oldIndex: 2,
        newIndex: 0,
      );

      // The drag really happened: the level now reads Third, First, Second.
      expect(vm.tree.childrenOf(null).map((n) => n.title),
          ['Third', 'First', 'Second']);

      final events = await entries();
      expect(events.length, before + 1,
          reason: 'moving Third to the top is a change worth recording');
      expect(events.last.action, ActivityAction.reordered);
      expect(events.last.nodeTitle, third.title);
    });

    test('a drag that lands where it started is not logged', () async {
      await seed('First');
      await seed('Second');
      final before = (await entries()).length;

      final visible = vm.tree.childrenOf(null);
      await vm.reorderChildren(
        parentId: null,
        visible: visible,
        oldIndex: 0,
        newIndex: 1,
      );

      expect((await entries()).length, before);
    });
  });

  group('actions', () {
    test('every stored action name reads back as itself', () {
      for (final action in ActivityAction.values) {
        expect(ActivityAction.fromName(action.name), action);
      }
    });

    test('an action written by a newer build reads as a plain edit', () {
      expect(ActivityAction.fromName('archived'), ActivityAction.updated);
    });
  });
}

/// Fails the first write and accepts the rest.
class _FlakyLog implements ActivityLogRepository {
  final List<String> written = [];
  bool first = true;

  @override
  Future<void> append(ActivityEvent event) async {
    if (first) {
      first = false;
      throw Exception('transient');
    }
    written.add(event.nodeTitle);
  }

  @override
  Future<List<ActivityEvent>> recent({int limit = 500, DateTime? since}) async =>
      const [];
}
