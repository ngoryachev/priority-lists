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

    testWidgets('the grip covers neither a mark button nor the back-gesture '
        'gutter, down to 320dp', (tester) async {
      // With a grip, which the 360dp case above has none of. The grip's 44dp
      // target is centred in a band measured from the card's own width, so it
      // drifts as the card narrows — onto the button row on one side, onto the
      // back-gesture gutter on the other. The band has to be bounded by both,
      // and this is the one place that says so. 320dp is the narrowest the app
      // is tested at; 300 is below anything shipping, and is here as margin.
      for (final width in [320.0, 360.0, 400.0, 300.0]) {
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

        final grip = tester.getRect(find.byType(ReorderableDragStartListener));
        for (final mark in NodeMark.values) {
          // The button's whole square, not just the glyph inside it: the
          // square is what takes the tap.
          final button = tester.getRect(
            find
                .ancestor(
                  of: find.text(mark.emoji),
                  matching: find.byType(SizedBox),
                )
                .first,
          );
          expect(
            grip.overlaps(button),
            isFalse,
            reason: '${mark.emoji} is under the grip at ${width}dp '
                '(grip $grip, button $button)',
          );
        }
        // The other end of the band: the leftmost strip of the card, which
        // the card keeps clear of its own gestures.
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
          reason: 'the grip reaches into the back-gesture gutter at ${width}dp '
              '(grip $grip, gutter $gutter)',
        );
        // And the handle is still a handle: its glyph is inside its target.
        final glyph = tester.getRect(find.byIcon(Icons.drag_handle));
        expect(
          grip.contains(glyph.topLeft) && grip.contains(glyph.bottomRight),
          isTrue,
          reason: 'the grip glyph is not covered by its own target at '
              '${width}dp (grip $grip, glyph $glyph)',
        );

        // And the taps actually land, not just the rectangles clear.
        await tester.tap(find.text(NodeMark.flame.emoji));
        await tester.tap(find.text(NodeMark.ice.emoji));
        expect(picked, [NodeMark.flame, NodeMark.ice], reason: 'at ${width}dp');
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
