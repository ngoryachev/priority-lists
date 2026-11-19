import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/activity_event.dart';
import 'package:priority_lists/domain/models/role_timeline.dart';

DateTime t(int hour, [int minute = 0, int day = 18]) =>
    DateTime(2026, 11, day, hour, minute);

var _ids = 0;

/// Any logged action somewhere in the tree.
ActivityEvent edit(DateTime at) => ActivityEvent(
  id: 'e${_ids++}',
  at: at,
  action: ActivityAction.updated,
  nodeId: 'some-node',
  nodeTitle: 'x',
  path: const ['Work'],
  details: 'description',
);

/// [role] took the red slot.
ActivityEvent activate(String role, DateTime at) => ActivityEvent(
  id: 'a${_ids++}',
  at: at,
  action: ActivityAction.prioritized,
  nodeId: role,
  nodeTitle: role,
  details: 'High → Critical',
);

/// [role] lost the red slot to another role.
ActivityEvent displace(String role, DateTime at) => ActivityEvent(
  id: 'd${_ids++}',
  at: at,
  action: ActivityAction.prioritized,
  nodeId: role,
  nodeTitle: role,
  details: 'Critical → High, displaced by "other"',
);

/// A top-level node was marked 🔥 / 🧊, or had its mark taken off. Written
/// with an empty path, exactly as the logger writes it for a role — which is
/// the shape `_roleChange` inspects.
ActivityEvent marked(String role, DateTime at, String details) => ActivityEvent(
  id: 'm${_ids++}',
  at: at,
  action: ActivityAction.marked,
  nodeId: role,
  nodeTitle: role,
  details: details,
);

void main() {
  group('day start', () {
    test('a day runs from 06:00 to 06:00', () {
      expect(RoleTimeline.dayStartFor(t(5, 59)), t(6, 0, 17));
      expect(RoleTimeline.dayStartFor(t(6)), t(6));
      expect(RoleTimeline.dayStartFor(t(23)), t(6));
    });
  });

  group('marks', () {
    const detailsWritten = ['🔥 In progress', '🧊 Blocked', 'Mark removed'];

    test('a mark on a role is not read as a role switch', () {
      for (final details in detailsWritten) {
        final spans = RoleTimeline.build(
          events: [activate('work', t(9)), marked('home', t(10), details)],
          now: t(11),
          currentRoleId: 'work',
        );
        expect(
          spans.map((s) => s.roleId).toSet(),
          {'work'},
          reason: '"$details" must not switch the day to "home"',
        );
      }
    });

    test('a day of nothing but marks counts towards the current role', () {
      final spans = RoleTimeline.build(
        events: [
          for (final details in detailsWritten) marked('home', t(9), details),
        ],
        now: t(10),
        currentRoleId: 'work',
      );

      // The marks are ordinary actions: they keep the clock running for the
      // role that is active, and name no switch of their own.
      expect(spans.map((s) => s.roleId), ['work']);
    });
  });

  group('build', () {
    test('nothing logged today counts nothing', () {
      final spans = RoleTimeline.build(
        events: [edit(t(5)), edit(t(23, 0, 17))],
        now: t(12),
        currentRoleId: 'work',
      );
      expect(spans, isEmpty);
    });

    test('the day starts at the first action and runs to now', () {
      final spans = RoleTimeline.build(
        events: [edit(t(9))],
        now: t(15),
        currentRoleId: 'work',
      );
      expect(spans, [RoleSpan('work', t(9), t(15))]);
    });

    test('a daytime gap without actions still counts', () {
      final spans = RoleTimeline.build(
        events: [edit(t(8)), edit(t(16))],
        now: t(17),
        currentRoleId: 'work',
      );
      expect(spans, [RoleSpan('work', t(8), t(17))]);
    });

    test(
      'switches cut the day into roles, the first role from its displacement',
      () {
        final spans = RoleTimeline.build(
          events: [
            edit(t(8)),
            activate('myself', t(12)),
            displace('work', t(12)),
            activate('work', t(14)),
            displace('myself', t(14)),
          ],
          now: t(18),
          currentRoleId: 'work',
        );
        expect(spans, [
          RoleSpan('work', t(8), t(12)),
          RoleSpan('myself', t(12), t(14)),
          RoleSpan('work', t(14), t(18)),
        ]);
      },
    );

    test('two quiet hours after 20:00 stop the count at the last action', () {
      final spans = RoleTimeline.build(
        events: [edit(t(8)), edit(t(21))],
        now: t(23, 30),
        currentRoleId: 'work',
      );
      expect(spans, [RoleSpan('work', t(8), t(21))]);
    });

    test('quiet since before 20:00 stops the count at 20:00', () {
      final spans = RoleTimeline.build(
        events: [edit(t(8)), edit(t(19))],
        now: t(23),
        currentRoleId: 'work',
      );
      expect(spans, [RoleSpan('work', t(8), t(20))]);
    });

    test('under two quiet hours in the evening keeps counting', () {
      final spans = RoleTimeline.build(
        events: [edit(t(8)), edit(t(21))],
        now: t(22, 30),
        currentRoleId: 'work',
      );
      expect(spans, [RoleSpan('work', t(8), t(22, 30))]);
    });

    test('an action after a quiet evening resumes the count', () {
      final spans = RoleTimeline.build(
        events: [edit(t(8)), edit(t(20, 30)), edit(t(23, 30))],
        now: t(23, 45),
        currentRoleId: 'work',
      );
      expect(spans, [
        RoleSpan('work', t(8), t(20, 30)),
        RoleSpan('work', t(23, 30), t(23, 45)),
      ]);
    });

    test('after midnight the previous day is still running', () {
      final spans = RoleTimeline.build(
        events: [edit(t(22, 0, 17)), edit(t(23, 30, 17)), edit(t(0, 30))],
        now: t(1),
        currentRoleId: 'myself',
      );
      expect(spans, [RoleSpan('myself', t(22, 0, 17), t(1))]);
    });

    test(
      'a first switch with no displacement leaves the time before it blank',
      () {
        final spans = RoleTimeline.build(
          events: [edit(t(8)), activate('myself', t(10))],
          now: t(11),
          currentRoleId: 'myself',
        );
        expect(spans, [RoleSpan('myself', t(10), t(11))]);
      },
    );

    test('a role switch deeper in the tree is not a role switch', () {
      final nested = ActivityEvent(
        id: 'n',
        at: t(10),
        action: ActivityAction.prioritized,
        nodeId: 'task',
        nodeTitle: 'task',
        path: const ['Work'],
        details: 'High → Critical',
      );
      final spans = RoleTimeline.build(
        events: [edit(t(8)), nested],
        now: t(11),
        currentRoleId: 'work',
      );
      expect(spans, [RoleSpan('work', t(8), t(11))]);
    });
  });
}
