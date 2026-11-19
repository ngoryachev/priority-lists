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
