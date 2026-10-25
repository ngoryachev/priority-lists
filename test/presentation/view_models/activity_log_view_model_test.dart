import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/activity_event.dart';
import 'package:priority_lists/domain/repositories/activity_log_repository.dart';
import 'package:priority_lists/presentation/view_models/activity_log_view_model.dart';

/// Records what the screen asked for, and hands back whatever it was given.
class _RecordingLog implements ActivityLogRepository {
  final List<ActivityEvent> events;
  final List<DateTime?> sinceAsked = [];
  Object? failure;

  /// Held open to keep a load in flight while the test ticks rows.
  Completer<void>? gate;

  _RecordingLog([this.events = const []]);

  @override
  Future<void> append(ActivityEvent event) async {}

  @override
  Future<List<ActivityEvent>> recent({int limit = 500, DateTime? since}) async {
    sinceAsked.add(since);
    if (gate != null) await gate!.future;
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

  group('selection', () {
    test('nothing is ticked to begin with', () async {
      final vm = ActivityLogViewModel(_RecordingLog([event('a', midnight())]));
      await vm.load();

      expect(vm.hasSelection, isFalse);
      expect(vm.selectedCount, 0);
      expect(vm.selectedIn(vm.days.single), isEmpty);
    });

    test('a day tick covers that day and nothing else', () async {
      final log = _RecordingLog([
        event('a', midnight().add(const Duration(hours: 9))),
        event('b', midnight().add(const Duration(hours: 10))),
        event('c', midnight().subtract(const Duration(hours: 2))),
      ]);
      final vm = ActivityLogViewModel(log);
      await vm.load();

      vm.setDaySelected(vm.days.first, true);

      expect(vm.selectedCount, 2);
      expect(vm.selectedIn(vm.days.first).map((e) => e.id), ['b', 'a']);
      expect(vm.selectedIn(vm.days.last), isEmpty);

      vm.setDaySelected(vm.days.first, false);
      expect(vm.hasSelection, isFalse);
    });

    test('ticking an id twice does not notify twice', () async {
      final vm = ActivityLogViewModel(_RecordingLog([event('a', midnight())]));
      await vm.load();
      var notifications = 0;
      vm.addListener(() => notifications++);

      vm.setEventSelected('a', true);
      vm.setEventSelected('a', true);
      vm.setEventSelected('b', false);

      expect(notifications, 1);
      expect(vm.selectedCount, 1);
    });

    test('a row ticked during a reload is dropped if the log lost it',
        () async {
      final log = _RecordingLog([
        event('a', midnight().add(const Duration(hours: 9))),
        event('b', midnight().add(const Duration(hours: 10))),
      ]);
      final vm = ActivityLogViewModel(log);
      await vm.load();

      // A reload starts, and the user ticks while it is still in flight.
      log.gate = Completer<void>();
      log.events.removeWhere((e) => e.id == 'b');
      final reload = vm.load();
      vm.setEventSelected('a', true);
      vm.setEventSelected('b', true);
      log.gate!.complete();
      await reload;

      // "a" is still there and stays ticked; "b" is gone and is forgotten.
      expect(vm.selectedCount, 1);
      expect(vm.isSelected('a'), isTrue);
      expect(vm.isSelected('b'), isFalse);
    });

    test('a failed reload leaves nothing ticked', () async {
      final log = _RecordingLog([event('a', midnight())]);
      final vm = ActivityLogViewModel(log);
      await vm.load();

      log.gate = Completer<void>();
      log.failure = Exception('no table');
      final reload = vm.load();
      vm.setEventSelected('a', true);
      log.gate!.complete();
      await reload;

      expect(vm.hasSelection, isFalse);
    });
  });
}
