import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/activity_event.dart';
import 'package:priority_lists/domain/repositories/activity_log_repository.dart';
import 'package:priority_lists/presentation/view_models/activity_log_view_model.dart';

/// Records what the screen asked for, and hands back whatever it was given.
class _RecordingLog implements ActivityLogRepository {
  final List<ActivityEvent> events;
  final List<DateTime?> sinceAsked = [];
  Object? failure;

  _RecordingLog([this.events = const []]);

  @override
  Future<void> append(ActivityEvent event) async {}

  @override
  Future<List<ActivityEvent>> recent({int limit = 500, DateTime? since}) async {
    sinceAsked.add(since);
    if (failure != null) throw failure!;
    return events
        .where((e) => since == null || !e.at.isBefore(since))
        .toList();
  }
}

ActivityEvent event(String id, DateTime at) => ActivityEvent(
      id: id,
      at: at,
      action: ActivityAction.created,
      nodeId: 'n-$id',
      nodeTitle: 'Node $id',
    );

DateTime midnight() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

void main() {
  test('the default window is a fortnight counted in calendar days', () async {
    final log = _RecordingLog();
    final vm = ActivityLogViewModel(log);

    await vm.load();

    expect(vm.windowDays, ActivityLogViewModel.defaultDays);
    expect(log.sinceAsked.single,
        midnight().subtract(const Duration(days: 13)));
  });

  test('"Today" asks from this midnight, not from 24 hours ago', () async {
    final log = _RecordingLog();
    final vm = ActivityLogViewModel(log);

    await vm.load(windowDays: 1);

    expect(vm.windowDays, 1);
    expect(log.sinceAsked.single, midnight());
  });

  test('a chosen window sticks for the next reload', () async {
    final log = _RecordingLog();
    final vm = ActivityLogViewModel(log);

    await vm.load(windowDays: 7);
    await vm.load();

    expect(vm.windowDays, 7);
    expect(log.sinceAsked,
        List.filled(2, midnight().subtract(const Duration(days: 6))));
  });

  test('groups what came back by day, newest first', () async {
    final log = _RecordingLog([
      event('a', midnight().add(const Duration(hours: 9))),
      event('b', midnight().subtract(const Duration(hours: 2))),
      event('c', midnight().add(const Duration(hours: 11))),
    ]);
    final vm = ActivityLogViewModel(log);

    await vm.load();

    expect(vm.days.map((d) => d.day),
        [midnight(), midnight().subtract(const Duration(days: 1))]);
    expect(vm.days.first.events.map((e) => e.id), ['c', 'a']);
  });

  test('a failure is reported and leaves no stale days behind', () async {
    final log = _RecordingLog([event('a', midnight())]);
    final vm = ActivityLogViewModel(log);
    await vm.load();
    expect(vm.days, hasLength(1));

    log.failure = Exception('no table');
    await vm.load();

    expect(vm.error, contains('no table'));
    expect(vm.days, isEmpty);
    expect(vm.isLoading, isFalse);
  });

  test('a successful reload clears an earlier failure', () async {
    final log = _RecordingLog([event('a', midnight())])
      ..failure = Exception('no table');
    final vm = ActivityLogViewModel(log);
    await vm.load();
    expect(vm.error, isNotNull);

    log.failure = null;
    await vm.load();

    expect(vm.error, isNull);
    expect(vm.days, hasLength(1));
  });

  test('listeners hear the load start and finish', () async {
    final vm = ActivityLogViewModel(_RecordingLog());
    var notifications = 0;
    vm.addListener(() => notifications++);

    await vm.load();

    expect(notifications, 2);
    expect(vm.isLoading, isFalse);
  });
}
