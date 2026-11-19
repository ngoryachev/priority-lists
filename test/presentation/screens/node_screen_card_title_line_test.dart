import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';
import 'package:provider/provider.dart';

/// The tile height the list hands out must pay for a whole line of title in
/// the screen that builds it, not only in an isolated card. A height a few dp
/// short does not throw: the title sits in a [Flexible], so it is quietly
/// handed less than its line and paints the rest under the 1-4 row. So this
/// measures the line box rather than waiting for an overflow exception, which
/// is what the other `NodeScreen` checks do.

PriorityNode node(
  String id, {
  String? parent,
  Priority priority = Priority.high,
  int createdOffset = 0,
}) {
  final created = DateTime(2026, 1, 1).add(Duration(minutes: createdOffset));
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    description: 'A description the tile does not show',
    priority: priority,
    createdAt: created,
    updatedAt: created,
  );
}

Future<PriorityNodeRepository> seeded(List<PriorityNode> nodes) async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes([
    node('Role', priority: Priority.critical),
    for (final n in nodes) n.parentId == null ? n.withParent('Role') : n,
  ]);
  return repository;
}

Widget app(PriorityNodeRepository repository, {double textScale = 1.0}) =>
    MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<PriorityNodeRepository>.value(value: repository),
          ChangeNotifierProvider(create: (_) => NodeTreeViewModel(repository)),
          ChangeNotifierProvider(create: (_) => FilterViewModel()),
        ],
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: const NodeScreen(),
          ),
        ),
      ),
    );

const ownerTitle =
    'An owner title far longer than one line of a phone tile can hold';
const childTitle =
    'A child title far longer than one line of a phone tile can hold';

Finder levelRow() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_PriorityLevelRow',
);

/// The title on screen gets the whole of its one line, and that line stays
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
  expect(
    tester.getRect(finder).top + line,
    lessThanOrEqualTo(tester.getRect(levelRow().first).top + 0.5),
    reason: 'the title line reaches into the 1-4 row on $where',
  );
}

void main() {
  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('at ${scale}x a list tile pays for one whole line of title, '
        'on the owner face and on a child page', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        app(
          await seeded([
            node(ownerTitle, priority: Priority.critical),
            node(childTitle, parent: ownerTitle, createdOffset: 1),
          ]),
          textScale: scale,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expectWholeTitleLine(tester, ownerTitle, 'the owner face at ${scale}x');

      // The same tile, swiped to its child page: that face carries the owner
      // label on top of the same three bands, so it is the taller of the two.
      await tester.drag(find.byType(PriorityCard).first, const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('$ownerTitle ›'), findsOneWidget);
      expectWholeTitleLine(tester, childTitle, 'a child page at ${scale}x');
    });
  }
}
