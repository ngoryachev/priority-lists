import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';

/// The owner label on a child page is dropped once the text is scaled past
/// what a tight tile has room for. These probe the edges of that rule: the
/// scale just below the cut (where the label is still paid for and the tile
/// has the least slack left), the scale just above it, and whether a card
/// with pages ever overflows where the same card without pages does not.

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

  const ownerTitle = 'An owner title long enough to need the full width';

  List<PriorityCardPage> pages(int count) => [
    for (var i = 0; i < count; i++)
      PriorityCardPage(
        id: 'c$i',
        title: 'Child number $i with a title of its own worth reading',
        badgeLabel: Priority.high.label,
        color: Colors.orange,
        backgroundColor: Colors.orange.withValues(alpha: 0.15),
        childCount: i,
        subtitle: 'Something describing child $i at some length',
        chipLabels: const ['one', 'two', 'three'],
        currentPriority: Priority.high,
        onTap: () {},
        onSetPriority: (_) {},
      ),
  ];

  PriorityCard card({
    required double height,
    bool withPages = true,
    String? initialChildId,
  }) => PriorityCard(
    key: ValueKey('card-$withPages-$initialChildId'),
    title: ownerTitle,
    badgeLabel: Priority.critical.label,
    color: Colors.red,
    backgroundColor: Colors.red.withValues(alpha: 0.15),
    fixedHeight: height,
    childCount: 5,
    subtitle: 'The owner description, long enough to wrap on a phone',
    chipLabels: const ['first child', 'second child'],
    currentPriority: Priority.critical,
    dragIndex: 0,
    childPages: withPages ? pages(5) : const [],
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

  /// Both tile heights a priority asks for on an 800dp phone (0.20 -> 160dp,
  /// 0.10 -> the 132dp floor), plus two taller ones a big tablet would give.
  const heights = <double>[132, 160, 200, 260];

  group('a child page under scaled-up text', () {
    // 1.7 is the last scale at which a tight tile still renders the owner
    // label, so it has the least vertical slack of any scale; 1.75 and 1.8
    // are the first ones past the cut.
    for (final scale in [1.6, 1.7, 1.75, 1.8]) {
      for (final height in heights) {
        testWidgets('${height.toInt()}dp at ${scale}x does not overflow and '
            'keeps the grip and the 1-4 row', (tester) async {
          useNarrowPhone(tester);
          await tester.pumpWidget(
            wrap(card(height: height, initialChildId: 'c0'),
                textScale: scale),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.byIcon(Icons.drag_handle).hitTestable(), findsOneWidget);
          for (final level in ['1', '2', '3', '4']) {
            expect(
              find.text(level).hitTestable(),
              findsOneWidget,
              reason: '$level at ${scale}x on ${height.toInt()}dp',
            );
          }
          // Whether the label is there or not, the child's own title is the
          // line that must survive.
          expect(
            find.textContaining('Child number 0'),
            findsOneWidget,
            reason: 'the child title at ${scale}x on ${height.toInt()}dp',
          );
        });
      }
    }

    testWidgets('the label survives on a tile with room and goes on one '
        'without', (tester) async {
      useNarrowPhone(tester);
      Finder label() => find.textContaining('$ownerTitle ›');

      // The 132dp floor tile, the tightest the list ever builds.
      await tester.pumpWidget(
        wrap(card(height: 132, initialChildId: 'c0'), textScale: 1.7),
      );
      await tester.pumpAndSettle();
      expect(label(), findsOneWidget, reason: '1.7x still fits');

      await tester.pumpWidget(
        wrap(card(height: 132, initialChildId: 'c0'), textScale: 1.8),
      );
      await tester.pumpAndSettle();
      expect(label(), findsNothing, reason: '1.8x no longer fits');
      // The counter still says whose slot this is, so the page is not
      // mistakable for the owner's own face.
      expect(find.text('1/5'), findsOneWidget);

      // A tall tile has the room at any scale and keeps the label.
      await tester.pumpWidget(
        wrap(card(height: 260, initialChildId: 'c0'), textScale: 2.0),
      );
      await tester.pumpAndSettle();
      expect(label(), findsOneWidget, reason: 'a tall tile keeps it');
    });
  });

  group('pages never cost a tile more than the tile had', () {
    // The dots' gutter narrows the owner face, so the face could run out of
    // width earlier on a card that swipes than on one that does not. Past
    // 2.4x the badge row overflows sideways either way (the card as it was
    // before this axis existed); what this asserts is that the second axis
    // is never what makes the difference.
    for (final height in heights) {
      testWidgets('a ${height.toInt()}dp owner page breaks at exactly the '
          'scale the page-less card does', (tester) async {
        useNarrowPhone(tester);
        final diverged = <String>[];

        for (var step = 10; step <= 30; step++) {
          final scale = step / 10;
          await tester.pumpWidget(
            wrap(card(height: height, withPages: false), textScale: scale),
          );
          await tester.pumpAndSettle();
          final plainBroke = tester.takeException() != null;

          await tester.pumpWidget(
            wrap(card(height: height), textScale: scale),
          );
          await tester.pumpAndSettle();
          final pagedBroke = tester.takeException() != null;

          if (plainBroke != pagedBroke) {
            diverged.add(
              '${scale}x: with pages ${pagedBroke ? "overflows" : "fits"}, '
              'without them ${plainBroke ? "overflows" : "fits"}',
            );
          }
        }

        expect(diverged, isEmpty);
      });
    }

    for (final height in heights) {
      testWidgets('${height.toInt()}dp at 2.0x: a child page fits where the '
          'page-less card does', (tester) async {
        useNarrowPhone(tester);
        await tester.pumpWidget(
          wrap(card(height: height, withPages: false), textScale: 2.0),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the page-less card');

        await tester.pumpWidget(
          wrap(card(height: height, initialChildId: 'c0'), textScale: 2.0),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'the child page');
      });
    }
  });

  group('the grip band follows the page on screen', () {
    PriorityCard bare({
      required bool ownerHasLevels,
      required bool childHasLevels,
      String? initialChildId,
    }) => PriorityCard(
      key: ValueKey('bare-$ownerHasLevels-$childHasLevels-$initialChildId'),
      title: ownerTitle,
      badgeLabel: Priority.critical.label,
      color: Colors.red,
      fixedHeight: 160,
      dragIndex: 0,
      childPages: [
        for (var i = 0; i < 2; i++)
          PriorityCardPage(
            id: 'c$i',
            title: 'Child $i',
            badgeLabel: Priority.high.label,
            color: Colors.orange,
            currentPriority: Priority.high,
            onTap: () {},
            onSetPriority: childHasLevels ? (_) {} : null,
          ),
      ],
      initialChildId: initialChildId,
      onTap: () {},
      onSetPriority: ownerHasLevels ? (_) {} : null,
    );

    testWidgets('a child row stays hittable under an owner that has none',
        (tester) async {
      // 320dp wide is the narrowest phone the app is checked on; a grip band
      // sized from the wrong face covers the buttons there first.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
          bare(
            ownerHasLevels: false,
            childHasLevels: true,
            initialChildId: 'c0',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.drag_handle).hitTestable(), findsOneWidget);
      for (final level in ['1', '2', '3', '4']) {
        expect(find.text(level).hitTestable(), findsOneWidget, reason: level);
      }
    });

    testWidgets('swiping from a page with a row to one without keeps the grip '
        'draggable', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // The inverse of the case above: the owner carries the 1-4 row, the
      // child pages do not, so the band widens as the card turns.
      await tester.pumpWidget(
        wrap(bare(ownerHasLevels: true, childHasLevels: false)),
      );
      await tester.pumpAndSettle();

      for (final level in ['1', '2', '3', '4']) {
        expect(find.text(level).hitTestable(), findsOneWidget, reason: level);
      }
      final gripOnOwner = tester.getCenter(find.byIcon(Icons.drag_handle));

      await tester.drag(find.byType(PriorityCard), const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(find.text('1/2'), findsOneWidget);
      expect(find.byIcon(Icons.drag_handle).hitTestable(), findsOneWidget);
      final gripOnChild = tester.getCenter(find.byIcon(Icons.drag_handle));
      // The band is the full card width on a page with no 1-4 row, so the
      // grip genuinely moves; it must still be on the card and reachable.
      expect(gripOnChild.dx, greaterThan(gripOnOwner.dx));
      expect(
        tester.getSize(find.byType(ReorderableDragStartListener)).width,
        greaterThanOrEqualTo(44),
      );
    });
  });
}
