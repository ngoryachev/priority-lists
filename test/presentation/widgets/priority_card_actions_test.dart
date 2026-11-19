import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/node_mark.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  /// The item card carries the most actions (four), so it is the worst case
  /// for the action row — on a 360dp phone it used to overflow.
  Widget itemCard() => PriorityCard(
        title: 'Some item',
        badgeLabel: Priority.critical.label,
        color: Colors.red,
        fixedHeight: 400,
        currentPriority: Priority.critical,
        onEdit: () {},
        onDelete: () {},
        onMoveUp: () {},
        onMoveInto: () {},
        onSetPriority: (_) {},
      );

  testWidgets('every action fits a narrow phone without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(itemCard()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final icon in [
      Icons.arrow_upward,
      Icons.move_to_inbox,
      Icons.edit_outlined,
      Icons.delete_outline,
    ]) {
      expect(find.byIcon(icon).hitTestable(), findsOneWidget,
          reason: '$icon must stay tappable at 360dp');
    }
  });

  testWidgets('priority is set through the level row, not up/down arrows',
      (tester) async {
    Priority? picked;
    await tester.pumpWidget(wrap(PriorityCard(
      title: 'Some item',
      badgeLabel: Priority.low.label,
      color: Colors.green,
      fixedHeight: 400,
      currentPriority: Priority.low,
      onSetPriority: (p) => picked = p,
    )));

    expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);

    await tester.tap(find.text('1'));
    expect(picked, Priority.critical);
  });

  testWidgets('move-into action fires its callback', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var moved = false;
    await tester.pumpWidget(wrap(PriorityCard(
      title: 'Some item',
      badgeLabel: Priority.high.label,
      color: Colors.orange,
      fixedHeight: 400,
      currentPriority: Priority.high,
      onEdit: () {},
      onDelete: () {},
      onMoveUp: () {},
      onMoveInto: () => moved = true,
      onSetPriority: (_) {},
    )));

    await tester.tap(find.byIcon(Icons.move_to_inbox));
    expect(moved, isTrue);
  });

  group('the mark buttons', () {
    Widget markableCard({
      NodeMark? current,
      required ValueChanged<NodeMark?> onSetMark,
    }) => PriorityCard(
      title: 'Some item',
      badgeLabel: Priority.high.label,
      color: Colors.orange,
      fixedHeight: 400,
      currentPriority: Priority.high,
      currentMark: current,
      onSetMark: onSetMark,
      onSetPriority: (_) {},
    );

    testWidgets('each one fires with its own mark', (tester) async {
      final picked = <NodeMark?>[];
      await tester.pumpWidget(
        wrap(markableCard(onSetMark: picked.add)),
      );

      await tester.tap(find.text(NodeMark.flame.emoji));
      await tester.tap(find.text(NodeMark.ice.emoji));
      expect(picked, [NodeMark.flame, NodeMark.ice]);
    });

    testWidgets('tapping the active one asks for no mark at all',
        (tester) async {
      final picked = <NodeMark?>[];
      await tester.pumpWidget(
        wrap(markableCard(current: NodeMark.ice, onSetMark: picked.add)),
      );

      await tester.tap(find.text(NodeMark.ice.emoji));
      expect(picked, [null]);

      // The other one still sets itself; only the active button unmarks.
      await tester.tap(find.text(NodeMark.flame.emoji));
      expect(picked, [null, NodeMark.flame]);
    });

    testWidgets('a card built without onSetMark shows neither', (tester) async {
      await tester.pumpWidget(wrap(PriorityCard(
        title: 'Some item',
        badgeLabel: Priority.high.label,
        color: Colors.orange,
        fixedHeight: 400,
        currentPriority: Priority.high,
        currentMark: NodeMark.flame,
        onSetPriority: (_) {},
      )));

      for (final mark in NodeMark.values) {
        expect(find.text(mark.emoji), findsNothing);
      }
      // The 1-4 row is still there on its own.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('both marks and all four levels stay tappable at 360dp',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(markableCard(onSetMark: (_) {})));
      await tester.pump();

      expect(tester.takeException(), isNull);
      for (final mark in NodeMark.values) {
        expect(find.text(mark.emoji).hitTestable(), findsOneWidget,
            reason: '${mark.emoji} must stay tappable at 360dp');
      }
      for (final p in Priority.values) {
        expect(find.text('${p.value}').hitTestable(), findsOneWidget,
            reason: 'the 1-4 row must keep its room');
      }
    });

    testWidgets('the grip keeps its 44dp and its place, and never covers the '
        'gutter, at every width', (tester) async {
      // The card's bottom edge is claimed by three things and, on a 320dp
      // phone, has room for barely two: the 24dp back-gesture gutter, the
      // grip's 44dp, and the six-button row. The gutter and the grip are
      // fixed and must always be exactly where they are; the row is the one
      // that gives way, by scrolling. This is the one place that says so.
      //
      // The grip used to be centred in whatever the row left over, which made
      // its position a function of the row's width — it covered the row's
      // buttons on one card width, the gutter on another, and below ~288dp was
      // clipped out of existence. The assertions below are the invariants that
      // replaced that: same size, same place, at every width.
      Rect? firstGrip;
      for (final width in [400.0, 360.0, 320.0, 300.0, 288.0, 277.0]) {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final picked = <NodeMark?>[];
        await tester.pumpWidget(
          wrap(
            ReorderableListView(
              onReorder: (_, _) {},
              buildDefaultDragHandles: false,
              children: [
                PriorityCard(
                  key: const ValueKey('card'),
                  title: 'Some item',
                  badgeLabel: Priority.high.label,
                  color: Colors.orange,
                  // Any height a tile could have: the bottom-right row and the
                  // grip are both pinned to the card's bottom edge, so it is
                  // the card's *width* this is about.
                  fixedHeight: 120,
                  currentPriority: Priority.high,
                  dragIndex: 0,
                  // A child page makes the card swipeable, which is what puts
                  // the back-gesture gutter on its left edge.
                  childPages: [
                    PriorityCardPage(
                      id: 'kid',
                      title: 'Kid',
                      badgeLabel: Priority.low.label,
                      color: Colors.green,
                      currentPriority: Priority.low,
                    ),
                  ],
                  onSetMark: picked.add,
                  onSetPriority: (_) {},
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final at = 'at ${width}dp';

        // Its whole 44dp target, and its glyph unclipped — not a sliver of
        // either, however narrow the card.
        final grip = tester.getRect(find.byType(ReorderableDragStartListener));
        // 44 and 24 spelt out rather than read back from the card: these are
        // the touch-target guideline and the platform's back-swipe strip, so a
        // change that shrinks either should fail here, not pass quietly.
        expect(grip.width, 44, reason: at);
        expect(grip.height, 44, reason: at);
        expect(
          tester.getSize(find.byIcon(Icons.drag_handle)).width,
          20,
          reason: 'the drag handle is clipped $at',
        );
        expect(
          find.byIcon(Icons.drag_handle).hitTestable(),
          findsOneWidget,
          reason: 'the card cannot be picked up $at',
        );

        // Clear of the strip the card keeps free of its own gestures, and in
        // the same place on every card — the position is no longer a function
        // of what the bottom-right row costs.
        final content = tester.getRect(find.byType(Stack).first);
        expect(
          grip.left - content.left,
          24,
          reason: 'the grip is not flush against the gutter $at',
        );
        final relative = grip.shift(-content.topLeft);
        firstGrip ??= relative;
        expect(relative, firstGrip, reason: 'the grip moved $at');

        // The 1-4 row is the part of the bottom row that is always there, so
        // it is never what scrolls away.
        for (final p in Priority.values) {
          expect(
            find.text('${p.value}').hitTestable(),
            findsOneWidget,
            reason: 'the 1-4 row lost button ${p.value} $at',
          );
        }

        // The marks are fully tappable across the supported range; below it
        // they scroll into reach rather than hiding under anything.
        if (width >= 320) {
          for (final mark in NodeMark.values) {
            expect(
              find.text(mark.emoji).hitTestable(),
              findsOneWidget,
              reason: '${mark.emoji} is not tappable $at',
            );
          }
          await tester.tap(find.text(NodeMark.flame.emoji));
          await tester.tap(find.text(NodeMark.ice.emoji));
          expect(picked, [NodeMark.flame, NodeMark.ice], reason: at);
        }
      }
    });

    testWidgets('a child page carries no mark buttons', (tester) async {
      await tester.pumpWidget(wrap(SizedBox(
        width: 360,
        child: PriorityCard(
          title: 'Owner',
          badgeLabel: Priority.high.label,
          color: Colors.orange,
          fixedHeight: 400,
          currentPriority: Priority.high,
          currentMark: NodeMark.flame,
          onSetMark: (_) {},
          onSetPriority: (_) {},
          childPages: [
            PriorityCardPage(
              id: 'kid',
              title: 'Kid',
              badgeLabel: Priority.low.label,
              color: Colors.green,
              currentPriority: Priority.low,
              onSetPriority: (_) {},
            ),
          ],
        ),
      )));
      await tester.pumpAndSettle();

      // The owner face has them; swiping to the child leaves them behind.
      expect(find.text(NodeMark.flame.emoji), findsOneWidget);
      await tester.drag(find.text('Owner'), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('Kid'), findsOneWidget);
      expect(find.text(NodeMark.flame.emoji), findsNothing);
      expect(find.text('1'), findsOneWidget, reason: 'the 1-4 row rides along');
    });
  });
}
