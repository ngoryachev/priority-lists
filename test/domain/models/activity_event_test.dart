import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/activity_event.dart';

ActivityEvent event(
  String id,
  DateTime at, {
  ActivityAction action = ActivityAction.created,
  String title = 'Node',
  List<String> path = const [],
  String details = '',
}) {
  return ActivityEvent(
    id: id,
    at: at,
    action: action,
    nodeId: 'n-$id',
    nodeTitle: title,
    path: path,
    details: details,
  );
}

void main() {
  group('ActivityEvent', () {
    test('digest line of a re-prioritisation names both ends', () {
      final e = event(
        '1',
        DateTime(2026, 10, 6, 9),
        action: ActivityAction.prioritized,
        title: 'Fix login',
        details: 'Medium → High',
      );
      expect(e.digestLine, 'Re-prioritised: "Fix login" — Medium → High');
    });

    test('digest line names where the node lives', () {
      final e = event(
        '1',
        DateTime(2026, 10, 6, 9),
        title: 'Fix login',
        path: ['Work', 'Backend'],
        details: 'High',
      );
      expect(e.digestLine, 'Added: "Fix login" (in Work › Backend) — High');
    });

    test('day drops the time', () {
      expect(event('1', DateTime(2026, 10, 6, 23, 59)).day, DateTime(2026, 10, 6));
    });
  });

  group('ActivityDay.group', () {
    test('splits by calendar day, newest day and newest event first', () {
      final days = ActivityDay.group([
        event('a', DateTime(2026, 10, 5, 10)),
        event('b', DateTime(2026, 10, 6, 9)),
        event('c', DateTime(2026, 10, 6, 18)),
      ]);

      expect(days.map((d) => d.day),
          [DateTime(2026, 10, 6), DateTime(2026, 10, 5)]);
      expect(days.first.events.map((e) => e.id), ['c', 'b']);
      expect(days.last.events.map((e) => e.id), ['a']);
    });

    test('no days for no events', () {
      expect(ActivityDay.group(const []), isEmpty);
    });
  });

  group('digest', () {
    test('counts the day and retells it grouped by action, oldest first', () {
      final day = ActivityDay.group([
        event('1', DateTime(2026, 10, 6, 11),
            action: ActivityAction.deleted, title: 'Dead end'),
        event('2', DateTime(2026, 10, 6, 10), title: 'Second'),
        event('3', DateTime(2026, 10, 6, 9), title: 'First'),
      ]).single;

      expect(day.digest(), '''
2026-10-06 — 3 changes
- Added: "First"
- Added: "Second"
- Deleted: "Dead end"''');
    });

    test('singular for a single change', () {
      final day = ActivityDay.group([event('1', DateTime(2026, 10, 6))]).single;
      expect(day.digest(), startsWith('2026-10-06 — 1 change\n'));
    });
  });
}
