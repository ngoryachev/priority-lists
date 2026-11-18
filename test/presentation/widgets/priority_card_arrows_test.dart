import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';

/// The browser's way through a card's pages: arrows on hover, wrapping around
/// at both ends, in place of the swipe dots.

void main() {
  List<PriorityCardPage> pages(int count) => [
    for (var i = 0; i < count; i++)
      PriorityCardPage(
        id: 'c$i',
        title: 'Child $i',
        badgeLabel: Priority.high.label,
        color: Colors.orange,
      ),
  ];

  Widget wrap({
    required List<String?> reported,
    bool pageArrows = true,
    String? initialChildId,
    Key? key,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          child: PriorityCard(
            key: key,
            title: 'Owner',
            badgeLabel: Priority.critical.label,
            color: Colors.red,
            fixedHeight: 200,
            childPages: pages(3),
            initialChildId: initialChildId,
            pageArrows: pageArrows,
            onChildPageChanged: reported.add,
          ),
        ),
      ),
    ),
  );

  Future<TestGesture> hover(WidgetTester tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(PriorityCard)));
    await tester.pumpAndSettle();
    return mouse;
  }

  final next = find.byIcon(Icons.chevron_right);
  final previous = find.byIcon(Icons.chevron_left);
  final dots = find.byIcon(Icons.more_vert);

  testWidgets('arrows replace the dots only while the mouse is over the card', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(reported: []));
    expect(next, findsNothing);
    expect(dots, findsOneWidget);

    final mouse = await hover(tester);
    expect(next, findsOneWidget);
    expect(previous, findsOneWidget);
    expect(dots, findsNothing);

    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(next, findsNothing);
    expect(dots, findsOneWidget);
  });

  testWidgets('next walks the children and wraps back to the node', (
    tester,
  ) async {
    final reported = <String?>[];
    await tester.pumpWidget(wrap(reported: reported));
    await hover(tester);

    for (var i = 0; i < 4; i++) {
      await tester.tap(next);
      await tester.pumpAndSettle();
    }

    expect(reported, ['c0', 'c1', 'c2', null]);
    expect(find.text('Owner'), findsOneWidget);
  });

  testWidgets('previous from the node wraps to the last child', (tester) async {
    final reported = <String?>[];
    await tester.pumpWidget(wrap(reported: reported));
    await hover(tester);

    await tester.tap(previous);
    await tester.pumpAndSettle();
    await tester.tap(previous);
    await tester.pumpAndSettle();

    expect(reported, ['c2', 'c1']);
    expect(find.text('Child 1'), findsOneWidget);
  });

  testWidgets('off by default outside the browser', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PriorityCard(
            title: 'Owner',
            badgeLabel: Priority.critical.label,
            color: Colors.red,
            fixedHeight: 200,
            childPages: pages(2),
          ),
        ),
      ),
    );
    await hover(tester);
    expect(next, findsNothing);
    expect(dots, findsOneWidget);
  });

  testWidgets('a new page from outside moves the card there', (tester) async {
    const key = ValueKey('card');
    await tester.pumpWidget(wrap(reported: [], key: key));
    expect(find.text('Owner'), findsOneWidget);

    await tester.pumpWidget(wrap(reported: [], key: key, initialChildId: 'c1'));
    await tester.pumpAndSettle();

    expect(find.text('Child 1'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
  });
}
