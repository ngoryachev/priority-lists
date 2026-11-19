import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/node_mark.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';

/// The owner label on a child page is the one line a child face carries that
/// the owner's own face does not, and [PriorityCard.compactHeight] is measured
/// with it in. These probe that it survives at every text scale the app is
/// checked at, and that having pages never costs a tile more than the same
/// tile without them.

void main() {
  /// Builds inside the scaled [MediaQuery], so a builder can ask for the tile
  /// height the list would hand out at that scale.
  Widget wrap(WidgetBuilder build, {double textScale = 1.0}) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Builder(builder: build),
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
        currentPriority: Priority.high,
        onTap: () {},
        onSetPriority: (_) {},
      ),
  ];

  PriorityCard card(
    BuildContext context, {
    bool withPages = true,
    String? initialChildId,
  }) => PriorityCard(
    key: ValueKey('card-$withPages-$initialChildId'),
    title: ownerTitle,
    badgeLabel: Priority.critical.label,
    color: Colors.red,
    backgroundColor: Colors.red.withValues(alpha: 0.15),
    fixedHeight: PriorityCard.compactHeight(context),
    childCount: 5,
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

  group('a child page under scaled-up text', () {
    // 1.0 and 1.3 are the everyday scales, 2.0 the top of Android's range and
    // well into the iOS accessibility sizes.
    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('${scale}x does not overflow and keeps the owner label, the '
          'grip and the 1-4 row', (tester) async {
        useNarrowPhone(tester);
        await tester.pumpWidget(
          wrap(
            (context) => card(context, initialChildId: 'c0'),
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.drag_handle).hitTestable(), findsOneWidget);
        for (final level in ['1', '2', '3', '4']) {
          expect(
            find.text(level).hitTestable(),
            findsOneWidget,
            reason: '$level at ${scale}x',
          );
        }
        // Whose card this page hangs off, and the child's own title: both are
        // paid for by the tile's height at every scale.
        expect(
          find.textContaining('$ownerTitle ›'),
          findsOneWidget,
          reason: 'the owner label at ${scale}x',
        );
        expect(
          find.textContaining('Child number 0'),
          findsOneWidget,
          reason: 'the child title at ${scale}x',
        );
      });
    }
  });

  group('pages never cost a tile more than the tile had', () {
    // The dots' gutter narrows the owner face, so the face could run out of
    // width earlier on a card that swipes than on one that does not. Past
    // 2.4x the badge row overflows sideways either way (the card as it was
    // before this axis existed); what this asserts is that the second axis
    // is never what makes the difference.
    testWidgets('the owner page breaks at exactly the scale the page-less '
        'card does', (tester) async {
      useNarrowPhone(tester);
      final diverged = <String>[];

      for (var step = 10; step <= 30; step++) {
        final scale = step / 10;
        await tester.pumpWidget(
          wrap(
            (context) => card(context, withPages: false),
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final plainBroke = tester.takeException() != null;

        await tester.pumpWidget(
          wrap((context) => card(context), textScale: scale),
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

    testWidgets('at 2.0x a child page fits where the page-less card does', (
      tester,
    ) async {
      useNarrowPhone(tester);
      await tester.pumpWidget(
        wrap((context) => card(context, withPages: false), textScale: 2.0),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'the page-less card');

      await tester.pumpWidget(
        wrap(
          (context) => card(context, initialChildId: 'c0'),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'the child page');
    });
  });

  group('the grip keeps its place whatever the page shows', () {
    PriorityCard bare(
      BuildContext context, {
      required bool ownerHasLevels,
      required bool childHasLevels,
      String? initialChildId,
    }) => PriorityCard(
      key: ValueKey('bare-$ownerHasLevels-$childHasLevels-$initialChildId'),
      title: ownerTitle,
      badgeLabel: Priority.critical.label,
      color: Colors.red,
      fixedHeight: PriorityCard.compactHeight(context),
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

    testWidgets('a child row stays hittable under an owner that has none', (
      tester,
    ) async {
      // 320dp wide is the narrowest phone the app is checked on; a grip band
      // sized from the wrong face covers the buttons there first.
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        wrap(
          (context) => bare(
            context,
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

      // The inverse of the case above: the owner carries the 1-4 row and the
      // child pages do not, so the two faces reserve different widths.
      await tester.pumpWidget(
        wrap(
          (context) => bare(
            context,
            ownerHasLevels: true,
            childHasLevels: false,
          ),
        ),
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
      // The grip is anchored, not centred in what the face leaves over, so
      // turning the page does not move it: it used to slide with the width
      // the bottom-right row reserved, which is how it ended up covering
      // that row's buttons and the back-gesture gutter on a narrow card.
      expect(gripOnChild.dx, gripOnOwner.dx);
      expect(
        tester.getSize(find.byType(ReorderableDragStartListener)).width,
        44,
      );
    });
  });

  group('a pinned mark row', () {
    const pinnedTitle = 'A marked node with a title longer than one line holds';

    testWidgets('keeps its one line whole at every text scale', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final scale in [1.0, 1.3, 2.0, 3.0]) {
        await tester.pumpWidget(
          wrap(
            (context) => const Column(
              children: [
                PinnedMarkRow(mark: NodeMark.flame, title: pinnedTitle),
              ],
            ),
            textScale: scale,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'at scale $scale');
        final row = tester.getSize(find.byType(PinnedMarkRow));
        final title = tester.getSize(find.text(pinnedTitle));
        // The row grows with the line rather than clipping it, and never
        // shrinks below the compact floor.
        expect(
          row.height,
          greaterThanOrEqualTo(title.height),
          reason: 'the title is painted outside the row at scale $scale',
        );
        expect(row.height, greaterThanOrEqualTo(PinnedMarkRow.minHeight));
        // Still one line, whatever the scale.
        expect(tester.widget<Text>(find.text(pinnedTitle)).maxLines, 1);
      }
    });

    testWidgets('the emoji stays tappable at a large scale', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var cleared = 0;
      await tester.pumpWidget(
        wrap(
          (context) => Column(
            children: [
              PinnedMarkRow(
                mark: NodeMark.ice,
                title: pinnedTitle,
                onClearMark: () => cleared++,
              ),
            ],
          ),
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(NodeMark.ice.emoji));
      expect(cleared, 1);
    });
  });
}
