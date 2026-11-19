import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';

/// [PriorityCard.compactHeight] promises a tile that fits exactly what a
/// minimal face holds: a badge row, *one whole line* of title and the 1-4 row,
/// in three bands. A tile a few dp short of that does not throw — the title
/// sits in a [Flexible], so it is silently handed less room than its line
/// needs and paints the rest of itself on top of the 1-4 row underneath.
/// These measure the line instead of waiting for an exception.

const ownerTitle =
    'An owner title far longer than one line of a phone tile can hold';
const childTitle =
    'A child title far longer than one line of a phone tile can hold';

void main() {
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

  /// A tile exactly as `_buildList` builds it: the shared compact height, the
  /// owner's actions, the drag grip, the 1-4 row and one child page.
  PriorityCard card(BuildContext context, {String? initialChildId}) =>
      PriorityCard(
        title: ownerTitle,
        badgeLabel: Priority.critical.label,
        color: Colors.red,
        backgroundColor: Colors.red.withValues(alpha: 0.15),
        fixedHeight: PriorityCard.compactHeight(context),
        childCount: 5,
        currentPriority: Priority.critical,
        dragIndex: 0,
        childPages: [
          PriorityCardPage(
            id: 'c0',
            title: childTitle,
            badgeLabel: Priority.high.label,
            color: Colors.orange,
            backgroundColor: Colors.orange.withValues(alpha: 0.15),
            childCount: 2,
            currentPriority: Priority.high,
            onTap: () {},
            onSetPriority: (_) {},
          ),
        ],
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

  Finder levelRow() => find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_PriorityLevelRow',
  );

  /// Checks the title on screen gets the whole of its one line and keeps it
  /// out of the band the 1-4 row owns.
  void expectWholeTitleLine(WidgetTester tester, String title, String where) {
    final finder = find.text(title);
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final line = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
    expect(
      paragraph.size.height,
      closeTo(line, 0.5),
      reason: 'the title line is squeezed on $where',
    );
    final rect = tester.getRect(finder);
    expect(
      rect.top + line,
      lessThanOrEqualTo(tester.getRect(levelRow()).top + 0.5),
      reason: 'the title line reaches into the 1-4 row on $where',
    );
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('at ${scale}x the tile pays for one whole line of title on '
        'the owner face', (tester) async {
      useNarrowPhone(tester);
      await tester.pumpWidget(wrap((context) => card(context),
          textScale: scale));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectWholeTitleLine(tester, ownerTitle, 'the owner face at ${scale}x');
    });

    testWidgets('at ${scale}x the tile pays for one whole line of title on a '
        'child page', (tester) async {
      useNarrowPhone(tester);
      await tester.pumpWidget(
        wrap((context) => card(context, initialChildId: 'c0'),
            textScale: scale),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectWholeTitleLine(tester, childTitle, 'a child page at ${scale}x');
    });
  }
}
