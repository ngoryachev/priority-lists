import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/node_mark.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/presentation/utils/priority_colors.dart';
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
    // Four cells, as it has always been: Delete sits behind the overflow
    // button now, with the marks, so the row's width is unchanged.
    for (final icon in [
      Icons.arrow_upward,
      Icons.move_to_inbox,
      Icons.edit_outlined,
      Icons.more_horiz,
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

  group('the mark actions', () {
    Widget markableCard({
      NodeMark? current,
      required ValueChanged<NodeMark?> onSetMark,
      VoidCallback? onDelete,
    }) => PriorityCard(
      title: 'Some item',
      badgeLabel: Priority.high.label,
      color: Colors.orange,
      fixedHeight: 400,
      currentPriority: Priority.high,
      currentMark: current,
      onSetMark: onSetMark,
      onDelete: onDelete,
      onSetPriority: (_) {},
    );

    /// Opens the badge row's overflow menu, where the marks live.
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
    }

    testWidgets('each entry fires with its own mark', (tester) async {
      final picked = <NodeMark?>[];
      await tester.pumpWidget(wrap(markableCard(onSetMark: picked.add)));

      for (final mark in NodeMark.values) {
        await openMenu(tester);
        await tester.tap(find.text('${mark.emoji} ${mark.label}'));
        await tester.pumpAndSettle();
      }

      expect(picked, [NodeMark.flame, NodeMark.ice]);
    });

    testWidgets('a marked node is offered "Remove mark", and its own entry '
        'is shown but disabled', (tester) async {
      final picked = <NodeMark?>[];
      await tester.pumpWidget(
        wrap(markableCard(current: NodeMark.ice, onSetMark: picked.add)),
      );
      await openMenu(tester);

      // Both marks are always listed, so the menu never changes shape; the
      // one already set simply cannot be chosen again.
      for (final mark in NodeMark.values) {
        expect(find.text('${mark.emoji} ${mark.label}'), findsOneWidget);
      }
      // Choosing the one already set does nothing and leaves the menu open,
      // which is what "disabled" means to the user.
      await tester.tap(
        find.text('${NodeMark.ice.emoji} ${NodeMark.ice.label}'),
      );
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
      expect(find.text('Remove mark'), findsOneWidget);

      await tester.tap(find.text('Remove mark'));
      await tester.pumpAndSettle();
      expect(picked, [null]);
    });

    testWidgets('an unmarked node is offered no "Remove mark"', (tester) async {
      await tester.pumpWidget(wrap(markableCard(onSetMark: (_) {})));
      await openMenu(tester);

      expect(find.text('Remove mark'), findsNothing);
    });

    testWidgets('Delete shares the menu and still fires', (tester) async {
      var deleted = false;
      await tester.pumpWidget(
        wrap(markableCard(onSetMark: (_) {}, onDelete: () => deleted = true)),
      );
      await openMenu(tester);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });

    testWidgets('a card built without onSetMark offers only Delete', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PriorityCard(
            title: 'Some item',
            badgeLabel: Priority.high.label,
            color: Colors.orange,
            fixedHeight: 400,
            currentPriority: Priority.high,
            currentMark: NodeMark.flame,
            onDelete: () {},
            onSetPriority: (_) {},
          ),
        ),
      );
      await openMenu(tester);

      for (final mark in NodeMark.values) {
        expect(find.text('${mark.emoji} ${mark.label}'), findsNothing);
      }
      expect(find.text('Remove mark'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('a card with neither has no overflow button at all', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PriorityCard(
            title: 'Some item',
            badgeLabel: Priority.high.label,
            color: Colors.orange,
            fixedHeight: 400,
            currentPriority: Priority.high,
            onSetPriority: (_) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.more_horiz), findsNothing);
      // The 1-4 row is still there on its own.
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('the marks cost the card no width: the grip, the 1-4 row and '
        'every action keep their targets', (tester) async {
      // The marks are menu entries, so the badge row has the four cells it has
      // always had and the bottom of the card is untouched. This is the guard
      // for that: earlier attempts put the marks in one row or the other and
      // squeezed the grip, the 1-4 buttons or the actions that were there.
      for (final width in [400.0, 360.0, 320.0]) {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(const SizedBox());

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
                  childPages: [
                    PriorityCardPage(
                      id: 'kid',
                      title: 'Kid',
                      badgeLabel: Priority.low.label,
                      color: Colors.green,
                      currentPriority: Priority.low,
                    ),
                  ],
                  onEdit: () {},
                  onDelete: () {},
                  onMoveInto: () {},
                  onSetMark: (_) {},
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

        // All four priority buttons, and every badge-row cell.
        for (final p in Priority.values) {
          expect(
            find.text('${p.value}').hitTestable(),
            findsOneWidget,
            reason: 'the 1-4 row lost button ${p.value} $at',
          );
        }
        for (final icon in [
          Icons.move_to_inbox,
          Icons.edit_outlined,
          Icons.more_horiz,
        ]) {
          expect(
            find.byIcon(icon).hitTestable(),
            findsOneWidget,
            reason: '$icon is not tappable $at',
          );
        }
      }
    });

    testWidgets('a child page carries no overflow button', (tester) async {
      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 360,
            child: PriorityCard(
              title: 'Owner',
              badgeLabel: Priority.high.label,
              color: Colors.orange,
              fixedHeight: 400,
              currentPriority: Priority.high,
              currentMark: NodeMark.flame,
              onSetMark: (_) {},
              onDelete: () {},
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
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The owner face has it; swiping to the child leaves it behind.
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      await tester.drag(find.text('Owner'), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(find.text('Kid'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(find.text('1'), findsOneWidget, reason: 'the 1-4 row rides along');
    });
  });

  group('a pinned row in move mode', () {
    /// The background the row paints, or null when it paints none.
    Color? rowTint(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(PinnedMarkRow),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    Color? titleColor(WidgetTester tester) =>
        tester.widget<Text>(find.text('Burning')).style?.color;

    testWidgets('an idle row paints no tint and keeps the mark\'s colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 360,
            child: PinnedMarkRow(mark: NodeMark.flame, title: 'Burning'),
          ),
        ),
      );

      expect(rowTint(tester), isNull);
      expect(titleColor(tester), markColor(NodeMark.flame));
    });

    testWidgets('a drop target paints the same green the cards do', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 360,
            child: PinnedMarkRow(
              mark: NodeMark.flame,
              title: 'Burning',
              isDropTarget: true,
            ),
          ),
        ),
      );

      // The flag has to reach the pixels: a row that only knows it is a
      // target but looks untouched is the bug it is there to prevent.
      expect(rowTint(tester), Colors.green.withValues(alpha: 0.35));
      expect(titleColor(tester), Colors.green.shade700);
      expect(titleColor(tester), isNot(markColor(NodeMark.flame)));
    });
  });
}
