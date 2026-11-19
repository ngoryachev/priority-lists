import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_activity_log_repository.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/activity_event.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/view_models/role_time_view_model.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';
import 'package:priority_lists/presentation/widgets/role_time_strip.dart';
import 'package:provider/provider.dart';

/// The duration label on the role time strip, in the corners of its spec the
/// first round of tests left open: the wording of short and round durations,
/// the label outliving the pointer leaving the band, the chip staying inside
/// the strip's extent when the stretch it names sits at the very top or the
/// very bottom of the day, and the timer dying with the widget.

PriorityNode node(
  String id, {
  String? parent,
  Priority priority = Priority.high,
  int position = 0,
}) {
  final created = DateTime(2026, 1, 1).add(Duration(minutes: position));
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    priority: priority,
    position: position,
    createdAt: created,
    updatedAt: created,
  );
}

List<PriorityNode> tree() => [
  node('work', priority: Priority.critical),
  node('a work task', parent: 'work'),
  node('home', priority: Priority.high, position: 1),
];

ActivityEvent activation(String roleId, DateTime at) => ActivityEvent(
  id: 'e-${at.microsecondsSinceEpoch}-$roleId',
  at: at,
  action: ActivityAction.prioritized,
  nodeId: roleId,
  nodeTitle: roleId,
  details: '${Priority.high.label} → ${Priority.critical.label}',
);

Future<Widget> app(
  List<ActivityEvent> events, {
  required DateTime now,
  List<PriorityNode>? extra,
}) async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes([...tree(), ...?extra]);
  final log = InMemoryActivityLogRepository();
  for (final event in events) {
    await log.append(event);
  }
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NodeTreeViewModel(repository)),
        ChangeNotifierProvider(create: (_) => FilterViewModel()),
        ChangeNotifierProvider(
          create: (context) => RoleTimeViewModel(
            log,
            context.read<NodeTreeViewModel>(),
            now: () => now,
            startTicker: false,
          )..refresh(),
        ),
      ],
      child: const NodeScreen(),
    ),
  );
}

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Rect stripRect(WidgetTester tester) =>
    tester.getRect(find.byType(RoleTimeStrip));

/// A point inside the hit band, at the height of [moment] of the day.
Offset bandAt(WidgetTester tester, DateTime moment, DateTime now) {
  final rect = stripRect(tester);
  final dayStart = DateTime(now.year, now.month, now.day, 6);
  final fraction =
      moment.difference(dayStart).inMilliseconds /
      now.difference(dayStart).inMilliseconds;
  return Offset(rect.right - 2, rect.top + rect.height * fraction);
}

Future<TestGesture> hover(WidgetTester tester, Offset to) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(to);
  await tester.pump();
  return mouse;
}

final paintedStrip = find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter.runtimeType.toString() == '_StripPainter',
);

void main() {
  group('how a duration is worded', () {
    // 06:00–08:00 uncounted, "work" 08:00–08:40 (40m), "home" 08:40–10:40
    // (exactly 2h), "work" again 10:40–12:00 (1h 20m).
    final now = DateTime(2026, 1, 1, 12);
    final events = [
      activation('work', DateTime(2026, 1, 1, 8)),
      activation('home', DateTime(2026, 1, 1, 8, 40)),
      activation('work', DateTime(2026, 1, 1, 10, 40)),
    ];

    testWidgets('minutes alone when the stretch is under an hour', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(await app(events, now: now));
      await tester.pumpAndSettle();

      await tester.tapAt(bandAt(tester, DateTime(2026, 1, 1, 8, 20), now));
      await tester.pump();

      expect(find.text('40m'), findsOneWidget);
    });

    testWidgets('hours alone when the stretch is a round number of them', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(await app(events, now: now));
      await tester.pumpAndSettle();

      await tester.tapAt(bandAt(tester, DateTime(2026, 1, 1, 9, 40), now));
      await tester.pump();

      expect(find.text('2h'), findsOneWidget);
    });

    testWidgets('hours and minutes together otherwise', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(await app(events, now: now));
      await tester.pumpAndSettle();

      await tester.tapAt(bandAt(tester, DateTime(2026, 1, 1, 11), now));
      await tester.pump();

      expect(find.text('1h 20m'), findsOneWidget);
    });
  });

  testWidgets('a stretch under a minute is named "<1m", and its chip stays '
      'inside the strip at the very top of the day', (tester) async {
    usePhoneSize(tester);
    // "work" holds 06:00–06:00:30 — half a minute at the top edge — and
    // "home" the rest of the day.
    final now = DateTime(2026, 1, 1, 12);
    await tester.pumpWidget(
      await app([
        activation('work', DateTime(2026, 1, 1, 6)),
        activation('home', DateTime(2026, 1, 1, 6, 0, 30)),
      ], now: now),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(bandAt(tester, DateTime(2026, 1, 1, 6, 0, 15), now));
    await tester.pump();

    expect(find.text('<1m'), findsOneWidget);
    final rect = stripRect(tester);
    final label = tester.getRect(find.text('<1m'));
    expect(label.top, greaterThanOrEqualTo(rect.top - 0.01));
    expect(label.bottom, lessThanOrEqualTo(rect.bottom + 0.01));
    expect(
      label.right,
      lessThanOrEqualTo(rect.right - RoleTimeStrip.width + 0.01),
    );
  });

  testWidgets('a stretch at the very bottom of the day keeps its chip inside '
      'the strip too', (tester) async {
    usePhoneSize(tester);
    // "home" holds only the last half minute before now.
    final now = DateTime(2026, 1, 1, 12);
    await tester.pumpWidget(
      await app([
        activation('work', DateTime(2026, 1, 1, 8)),
        activation('home', DateTime(2026, 1, 1, 11, 59, 30)),
      ], now: now),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(bandAt(tester, DateTime(2026, 1, 1, 11, 59, 45), now));
    await tester.pump();

    expect(find.text('<1m'), findsOneWidget);
    final rect = stripRect(tester);
    final label = tester.getRect(find.text('<1m'));
    expect(label.bottom, lessThanOrEqualTo(rect.bottom + 0.01));
    expect(label.top, greaterThanOrEqualTo(rect.top - 0.01));
  });

  testWidgets('the label stays its three seconds after the pointer has left '
      'the band', (tester) async {
    usePhoneSize(tester);
    final now = DateTime(2026, 1, 1, 12);
    await tester.pumpWidget(
      await app([
        activation('work', DateTime(2026, 1, 1, 8)),
        activation('home', DateTime(2026, 1, 1, 9, 25)),
      ], now: now),
    );
    await tester.pumpAndSettle();

    final mouse = await hover(
      tester,
      bandAt(tester, DateTime(2026, 1, 1, 8, 40), now),
    );
    expect(find.text('1h 25m'), findsOneWidget);

    // Off the band, into the middle of the list.
    await mouse.moveTo(stripRect(tester).center);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1h 25m'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('1h 25m'), findsNothing);
  });

  testWidgets('hovering uncounted time takes a label that was up back down', (
    tester,
  ) async {
    usePhoneSize(tester);
    final now = DateTime(2026, 1, 1, 12);
    await tester.pumpWidget(
      await app([
        activation('work', DateTime(2026, 1, 1, 8)),
        activation('home', DateTime(2026, 1, 1, 9, 25)),
      ], now: now),
    );
    await tester.pumpAndSettle();

    final mouse = await hover(
      tester,
      bandAt(tester, DateTime(2026, 1, 1, 8, 40), now),
    );
    expect(find.text('1h 25m'), findsOneWidget);

    // 07:00 is before the day's first logged action: nothing there.
    await mouse.moveTo(bandAt(tester, DateTime(2026, 1, 1, 7), now));
    await tester.pump();
    expect(find.text('1h 25m'), findsNothing);
  });

  testWidgets('the painted strip is still four pixels at the right edge', (
    tester,
  ) async {
    usePhoneSize(tester);
    final now = DateTime(2026, 1, 1, 12);
    await tester.pumpWidget(
      await app([activation('work', DateTime(2026, 1, 1, 8))], now: now),
    );
    await tester.pumpAndSettle();

    final strip = stripRect(tester);
    final painted = tester.getRect(paintedStrip);
    expect(painted.width, RoleTimeStrip.width);
    expect(painted.right, strip.right);
    expect(painted.top, strip.top);
    expect(painted.bottom, strip.bottom);
  });

  testWidgets('the auto-hide timer dies with the widget', (tester) async {
    usePhoneSize(tester);
    final now = DateTime(2026, 1, 1, 12);
    await tester.pumpWidget(
      await app([
        activation('work', DateTime(2026, 1, 1, 8)),
        activation('home', DateTime(2026, 1, 1, 9, 25)),
      ], now: now),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(bandAt(tester, DateTime(2026, 1, 1, 8, 40), now));
    await tester.pump();
    expect(find.text('1h 25m'), findsOneWidget);

    // Unmounted with a second to go: no pending timer, no setState after
    // dispose.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
  });

  testWidgets('the 1-4 priority buttons at a card\'s right edge still take '
      'their taps', (tester) async {
    usePhoneSize(tester);
    final now = DateTime(2026, 1, 1, 12);
    await tester.pumpWidget(
      await app([activation('work', DateTime(2026, 1, 1, 8))], now: now),
    );
    await tester.pumpAndSettle();

    expect(find.text(Priority.low.label), findsNothing);
    // The rightmost of the four buttons on the first card is "4".
    final button = find
        .descendant(
          of: find.byType(PriorityCard).first,
          matching: find.text('4'),
        )
        .first;
    final strip = stripRect(tester);
    // Every one of them is clear of the band on a phone-width screen.
    for (final element in find.text('4').evaluate()) {
      expect(
        tester.getRect(find.byWidget(element.widget)).right,
        lessThan(strip.right - RoleTimeStrip.hitWidth),
      );
    }

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text(Priority.low.label), findsWidgets);
  });

  testWidgets('on a wide window the chip still sits against the strip, out '
      'of the centred content\'s way', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final now = DateTime(2026, 1, 1, 12);
    await tester.pumpWidget(
      await app([
        activation('work', DateTime(2026, 1, 1, 8)),
        activation('home', DateTime(2026, 1, 1, 9, 25)),
      ], now: now),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(bandAt(tester, DateTime(2026, 1, 1, 8, 40), now));
    await tester.pump();

    expect(find.text('1h 25m'), findsOneWidget);
    final strip = stripRect(tester);
    final label = tester.getRect(find.text('1h 25m'));
    expect(
      label.right,
      lessThanOrEqualTo(strip.right - RoleTimeStrip.width + 0.01),
    );
    // Right against the strip, not adrift in the middle of the window.
    expect(label.right, greaterThan(strip.right - 40));
    // Clear of the centred list.
    expect(
      label.left,
      greaterThan(tester.getRect(find.byType(PriorityCard).first).right),
    );
  });
}
