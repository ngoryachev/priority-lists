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

/// The strip along the right edge names a stretch's duration on demand: hover
/// it with a mouse or tap it with a finger, and a small chip to its left says
/// how long that stretch was, for three seconds.

/// Noon of a day that started — by the timeline's rules — at 06:00, so the
/// strip covers six hours.
final now = DateTime(2026, 1, 1, 12);
final dayStart = DateTime(2026, 1, 1, 6);

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

/// "work" is the active role, with a child that has a child of its own, so a
/// card tap has somewhere to go.
List<PriorityNode> tree() => [
  node('work', priority: Priority.critical),
  node('a work task', parent: 'work'),
  node('deeper', parent: 'a work task'),
  node('home', priority: Priority.high, position: 1),
];

/// A role becoming active, as the log writes it.
ActivityEvent activation(String roleId, DateTime at) => ActivityEvent(
  id: 'e-${at.microsecondsSinceEpoch}-$roleId',
  at: at,
  action: ActivityAction.prioritized,
  nodeId: roleId,
  nodeTitle: roleId,
  details: '${Priority.high.label} → ${Priority.critical.label}',
);

/// Two switches: 06:00–08:00 is uncounted, "work" runs 08:00–09:25 (1h 25m)
/// and [second] 09:25–12:00 (2h 35m).
List<ActivityEvent> twoSpans({String second = 'home'}) => [
  activation('work', DateTime(2026, 1, 1, 8)),
  activation(second, DateTime(2026, 1, 1, 9, 25)),
];

/// Where a moment of the day sits along the strip, as a fraction of it.
double at(DateTime moment) =>
    moment.difference(dayStart).inMilliseconds /
    now.difference(dayStart).inMilliseconds;

Future<Widget> app(
  List<PriorityNode> nodes,
  List<ActivityEvent> events, {
  List<PriorityNode>? extra,
}) async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes([...nodes, ...?extra]);
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

/// A point inside the hit band, at [fraction] of the strip's height.
Offset inBand(WidgetTester tester, double fraction) {
  final rect = stripRect(tester);
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

void main() {
  testWidgets('hovering a stretch names its duration beside the strip', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(await app(tree(), twoSpans()));
    await tester.pumpAndSettle();

    final rect = stripRect(tester);
    await hover(tester, inBand(tester, at(DateTime(2026, 1, 1, 8, 40))));

    expect(find.text('1h 25m'), findsOneWidget);
    final label = tester.getRect(find.text('1h 25m'));
    // Left of the painted strip, which keeps its four pixels.
    expect(
      label.right,
      lessThanOrEqualTo(rect.right - RoleTimeStrip.width + 0.01),
    );
    // Centred on the middle of the stretch it names.
    final middle =
        rect.top +
        rect.height *
            (at(DateTime(2026, 1, 1, 8)) + at(DateTime(2026, 1, 1, 9, 25))) /
            2;
    expect((label.center.dy - middle).abs(), lessThan(2));
    // And inside the strip's own vertical extent.
    expect(label.top, greaterThanOrEqualTo(rect.top));
    expect(label.bottom, lessThanOrEqualTo(rect.bottom));
  });

  testWidgets('the label goes away three seconds after it came up', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(await app(tree(), twoSpans()));
    await tester.pumpAndSettle();

    await hover(tester, inBand(tester, at(DateTime(2026, 1, 1, 8, 40))));
    expect(find.text('1h 25m'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text('1h 25m'), findsNothing);
  });

  testWidgets('hovering the next stretch switches the label to it', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(await app(tree(), twoSpans()));
    await tester.pumpAndSettle();

    final mouse = await hover(
      tester,
      inBand(tester, at(DateTime(2026, 1, 1, 8, 40))),
    );
    await mouse.moveTo(inBand(tester, at(DateTime(2026, 1, 1, 11))));
    await tester.pump();

    expect(find.text('1h 25m'), findsNothing);
    expect(find.text('2h 35m'), findsOneWidget);

    // The three seconds started over with the new stretch.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('2h 35m'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('2h 35m'), findsNothing);
  });

  testWidgets('a tap names the stretch at that height and then lets go', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(await app(tree(), twoSpans()));
    await tester.pumpAndSettle();

    await tester.tapAt(inBand(tester, at(DateTime(2026, 1, 1, 10))));
    await tester.pump();

    expect(find.text('2h 35m'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.text('2h 35m'), findsNothing);
  });

  testWidgets('a tap on another stretch switches the label and the three '
      'seconds', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(await app(tree(), twoSpans()));
    await tester.pumpAndSettle();

    await tester.tapAt(inBand(tester, at(DateTime(2026, 1, 1, 8, 40))));
    await tester.pump();
    expect(find.text('1h 25m'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.tapAt(inBand(tester, at(DateTime(2026, 1, 1, 11))));
    await tester.pump();
    expect(find.text('1h 25m'), findsNothing);
    expect(find.text('2h 35m'), findsOneWidget);

    // Still up where the first stretch's three seconds would have ended.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('2h 35m'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('2h 35m'), findsNothing);
  });

  testWidgets('a tap on uncounted time names nothing', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(await app(tree(), twoSpans()));
    await tester.pumpAndSettle();

    // 07:00: before the day's first logged action, so nothing is painted.
    await tester.tapAt(inBand(tester, at(DateTime(2026, 1, 1, 7))));
    await tester.pump();

    expect(find.text('1h 25m'), findsNothing);
    expect(find.text('2h 35m'), findsNothing);
  });

  testWidgets('a deleted role\'s stretch names nothing either', (tester) async {
    usePhoneSize(tester);
    // "ghost" is in the log but no longer in the tree: unpainted, unnamed.
    await tester.pumpWidget(await app(tree(), twoSpans(second: 'ghost')));
    await tester.pumpAndSettle();

    await tester.tapAt(inBand(tester, at(DateTime(2026, 1, 1, 11))));
    await tester.pump();

    expect(find.text('2h 35m'), findsNothing);

    // The stretch above it is still named.
    await tester.tapAt(inBand(tester, at(DateTime(2026, 1, 1, 8, 40))));
    await tester.pump();
    expect(find.text('1h 25m'), findsOneWidget);
  });

  testWidgets('a tap on a card still opens it', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(await app(tree(), twoSpans()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('a work task'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'a work task'), findsOneWidget);
  });

  testWidgets('a tap in the band never opens the card beneath it', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(await app(tree(), twoSpans()));
    await tester.pumpAndSettle();

    // The band runs over the right edge of the only card on this level.
    final card = tester.getRect(find.byType(PriorityCard));
    final rect = stripRect(tester);
    expect(card.right, greaterThan(rect.right - RoleTimeStrip.hitWidth));

    await tester.tapAt(Offset(rect.right - 2, card.center.dy));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'work'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'a work task'), findsNothing);
  });

  testWidgets('a drag that starts in the band still scrolls the list', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      await app(
        tree(),
        twoSpans(),
        extra: [
          for (var i = 0; i < 20; i++)
            node('task $i', parent: 'work', position: i + 1),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final before = tester.getRect(find.text('task 0')).top;
    await tester.dragFrom(inBand(tester, 0.5), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.text('task 0')).top, lessThan(before - 100));
  });
}
