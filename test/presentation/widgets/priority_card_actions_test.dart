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

    testWidgets('the marks never cost the grip or the 1-4 row their targets', (
      tester,
    ) async {
      // The marks live in the badge row, not next to the 1-4 buttons, so the
      // bottom of the card is exactly what it was before them: the drag grip
      // and the four priority buttons, each with its whole touch target, and
      // the strip the card keeps clear for the platform back swipe. This is
      // the guard for that — the earlier placement squeezed all three.
      for (final width in [400.0, 360.0, 320.0]) {
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
                  // Any height a tile could have: the grip and the 1-4 row are
                  // both pinned to the card's bottom edge, so it is the card's
                  // *width* this is about.
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

        // The grip's whole target and an unclipped glyph. 44 and 20 are spelt
        // out rather than read back from the card: they are the touch-target
        // guideline and the glyph, so a change that shrinks either should fail
        // here, not pass quietly.
        final grip = tester.getRect(find.byType(ReorderableDragStartListener));
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

        // Clear of the strip the card keeps free of its own gestures.
        final content = tester.getRect(find.byType(Stack).first);
        final gutter = Rect.fromLTRB(
          content.left,
          grip.top,
          content.left + 24,
          grip.bottom,
        );
        expect(
          grip.overlaps(gutter),
          isFalse,
          reason: 'the grip reaches into the back-gesture gutter $at '
              '(grip $grip, gutter $gutter)',
        );

        // All four priority buttons, and both marks in the row above.
        for (final p in Priority.values) {
          expect(
            find.text('${p.value}').hitTestable(),
            findsOneWidget,
            reason: 'the 1-4 row lost button ${p.value} $at',
          );
        }
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
