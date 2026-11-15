import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';

/// The card's second axis on a narrow phone: the bottom drag grip, the
/// right-edge dots and the 1-4 row all share the one tile, so this is where
/// they would collide.

void main() {
  Widget wrap(Widget child, {double textScale = 1.0}) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child,
        ),
      ),
    ),
  );

  List<PriorityCardPage> pages(int count) => [
    for (var i = 0; i < count; i++)
      PriorityCardPage(
        id: 'c$i',
        title: 'Child number $i',
        badgeLabel: Priority.high.label,
        color: Colors.orange,
        backgroundColor: Colors.orange.withValues(alpha: 0.15),
        childCount: i,
        subtitle: 'Something describing child $i',
        chipLabels: const ['one', 'two'],
        currentPriority: Priority.high,
        onTap: () {},
        onSetPriority: (_) {},
      ),
  ];

  PriorityCard card({
    required double height,
    // Five, so the owner's child-count badge cannot be mistaken for one of
    // the 1-4 buttons.
    int children = 5,
    String? initialChildId,
  }) => PriorityCard(
    // Keyed by the page it opens on: the initial page is read when the state
    // is created, so a test that pumps one card over another needs the second
    // one to be a new card rather than the first one rebuilt.
    key: ValueKey('card-$initialChildId'),
    title: 'An owner title long enough to need the full width of the tile',
    badgeLabel: Priority.critical.label,
    color: Colors.red,
    backgroundColor: Colors.red.withValues(alpha: 0.15),
    fixedHeight: height,
    childCount: children,
    subtitle: 'The owner description',
    chipLabels: const ['first child', 'second child'],
    currentPriority: Priority.critical,
    dragIndex: 0,
    childPages: pages(children),
    initialChildId: initialChildId,
    onTap: () {},
    onEdit: () {},
    onDelete: () {},
    onMoveUp: () {},
    onMoveInto: () {},
    onSetPriority: (_) {},
  );

  void useNarrowPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Every tile height a priority asks for on an 800dp-tall phone, plus the
  /// 132dp floor the list clamps the shortest ones to.
  final heights = <double>{
    for (final p in Priority.values)
      (800 * p.cardHeightFraction).clamp(132.0, double.infinity),
  };

  for (final height in heights) {
    testWidgets('a ${height.toInt()}dp tile fits the grip, the dots and the '
        '1-4 row at 360dp', (tester) async {
      useNarrowPhone(tester);
      await tester.pumpWidget(wrap(card(height: height)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final grip = find.byIcon(Icons.drag_handle);
      expect(grip.hitTestable(), findsOneWidget);
      // The grip is the only way to start a reorder, so it keeps a
      // finger-sized target.
      final gripSize = tester.getSize(
        find.byType(ReorderableDragStartListener),
      );
      expect(gripSize.width, greaterThanOrEqualTo(44));
      expect(gripSize.height, greaterThanOrEqualTo(44));

      for (final level in ['1', '2', '3', '4']) {
        expect(
          find.text(level).hitTestable(),
          findsOneWidget,
          reason: '"$level" must stay tappable next to the grip and the dots',
        );
      }

      // The owner's own actions keep their room next to the dots' gutter.
      for (final icon in [
        Icons.arrow_upward,
        Icons.move_to_inbox,
        Icons.edit_outlined,
        Icons.delete_outline,
      ]) {
        expect(find.byIcon(icon).hitTestable(), findsOneWidget, reason: '$icon');
      }

      // The swipe hint, and no leftover vertical handle in the action row.
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
    });
  }

  for (final height in heights) {
    // 2.0 is the top of Android's font-size range and well into the iOS
    // accessibility sizes. Beyond it the badge row overflows sideways at
    // every tile height, pages or no pages — that is the card as it was
    // before this axis existed and is not tested here.
    for (final scale in [1.5, 2.0]) {
      testWidgets('text at ${scale}x does not overflow a ${height.toInt()}dp '
          'tile, on the owner page or a child page', (tester) async {
        useNarrowPhone(tester);
        await tester.pumpWidget(wrap(card(height: height), textScale: scale));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.drag_handle).hitTestable(), findsOneWidget);

        // A child page is the tighter of the two: the owner label costs it a
        // line the owner's own face does not pay for, which the shortest
        // tile cannot spare once the text is scaled up.
        await tester.pumpWidget(
          wrap(card(height: height, initialChildId: 'c0'), textScale: scale),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.drag_handle).hitTestable(), findsOneWidget);
        for (final level in ['1', '2', '3', '4']) {
          expect(find.text(level).hitTestable(), findsOneWidget, reason: level);
        }
      });
    }
  }

  testWidgets('the counter names the child page, not the page index',
      (tester) async {
    useNarrowPhone(tester);
    await tester.pumpWidget(wrap(card(height: 160, initialChildId: 'c2')));
    await tester.pumpAndSettle();

    expect(find.text('3/5'), findsOneWidget);
    expect(find.text('Child number 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card without children has neither dots nor a counter',
      (tester) async {
    useNarrowPhone(tester);
    await tester.pumpWidget(wrap(card(height: 160, children: 0)));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.byType(PageView), findsNothing);
    expect(find.byIcon(Icons.drag_handle).hitTestable(), findsOneWidget);
  });

  testWidgets('the grip clears the 1-4 row of the page on screen, not the '
      "owner's", (tester) async {
    // The smallest phone the app is tested on, with the list's own insets:
    // the tile is 280dp wide there, which is where a grip band sized from
    // the wrong face starts covering the buttons.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // An owner with no 1-4 row of its own, pages that have one: the grip is
    // hit-test-first, so a band sized from the owner would sit on top of the
    // child's buttons.
    await tester.pumpWidget(
      wrap(
        Padding(
          padding: const EdgeInsets.all(8),
          child: PriorityCard(
            title: 'No level row of its own',
            badgeLabel: Priority.critical.label,
            color: Colors.red,
            fixedHeight: 160,
            dragIndex: 0,
            childPages: pages(2),
            initialChildId: 'c0',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.drag_handle).hitTestable(), findsOneWidget);
    for (final level in ['1', '2', '3', '4']) {
      expect(find.text(level).hitTestable(), findsOneWidget, reason: level);
    }
  });

  testWidgets('a card with no tile height lays out exactly as it did before '
      'pages existed', (tester) async {
    useNarrowPhone(tester);
    // The pages need a bounded tile height, which only the list hands out.
    // Without one the card must keep laying out like it always has — a Stack
    // of nothing but positioned children would quietly claim every pixel it
    // is offered.
    Widget sized({required bool withPages}) => Align(
      alignment: Alignment.topCenter,
      child: PriorityCard(
        title: 'Content sized',
        badgeLabel: Priority.high.label,
        color: Colors.orange,
        currentPriority: Priority.high,
        childPages: withPages ? pages(3) : const [],
        onSetPriority: (_) {},
      ),
    );

    await tester.pumpWidget(wrap(sized(withPages: false)));
    await tester.pumpAndSettle();
    final plain = tester.getSize(find.byType(PriorityCard));

    await tester.pumpWidget(wrap(sized(withPages: true)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Content sized'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
    expect(tester.getSize(find.byType(PriorityCard)), plain);
  });

  testWidgets('a child page offers the 1-4 row and nothing else',
      (tester) async {
    useNarrowPhone(tester);
    await tester.pumpWidget(wrap(card(height: 400, initialChildId: 'c0')));
    await tester.pumpAndSettle();

    expect(find.text('Child number 0'), findsOneWidget);
    for (final icon in [
      Icons.edit_outlined,
      Icons.delete_outline,
      Icons.arrow_upward,
      Icons.move_to_inbox,
    ]) {
      expect(find.byIcon(icon), findsNothing, reason: '$icon is owner-only');
    }
    // The reorder grip belongs to the tile, not to the page, so it stays.
    expect(find.byIcon(Icons.drag_handle).hitTestable(), findsOneWidget);
    for (final level in ['1', '2', '3', '4']) {
      expect(find.text(level).hitTestable(), findsOneWidget);
    }
  });
}
