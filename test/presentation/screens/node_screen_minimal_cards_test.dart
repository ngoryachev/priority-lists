import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/item_chips.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';
import 'package:provider/provider.dart';

/// What a list tile is now: a badge row, one line of title and the 1-4 row.
/// No chips, no description, and one height for every priority.

PriorityNode node(
  String id, {
  String? parent,
  Priority priority = Priority.high,
  String description = '',
  int createdOffset = 0,
}) {
  final created = DateTime(2026, 1, 1).add(Duration(minutes: createdOffset));
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    description: description,
    priority: priority,
    createdAt: created,
    updatedAt: created,
  );
}

const roleId = 'Role';

Future<PriorityNodeRepository> seeded(List<PriorityNode> nodes) async {
  final repository = InMemoryPriorityNodeRepository();
  // The tree's top level is the roles and the screen lists the children of
  // the active one, so everything top-level hangs off one role node.
  await repository.saveNodes([
    node(roleId, priority: Priority.critical),
    for (final n in nodes) n.parentId == null ? n.withParent(roleId) : n,
  ]);
  return repository;
}

Widget app(PriorityNodeRepository repository, {double textScale = 1.0}) {
  return MaterialApp(
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
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The child-count badge, told apart from the 1-4 buttons (which also show a
/// bare number) by the badge's own smaller type.
Finder countBadge(String count) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && widget.data == count && widget.style?.fontSize == 12,
);

const longTitle =
    'A node title far longer than one line of a phone tile could ever hold';
const description = 'A description that used to take the rest of the tile';

void main() {
  testWidgets('a long title is one ellipsised line and the description is '
      'not on the tile at all', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      app(await seeded([node(longTitle, description: description)])),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text(longTitle));
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    // The description stays on the node (and in the edit dialog); the tile
    // simply does not say it.
    expect(find.text(description), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a node with children shows the count, no chips, and still '
      'swipes to a child page', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          node('Parent', priority: Priority.critical),
          node('First child', parent: 'Parent', createdOffset: 1),
          node('Second child', parent: 'Parent', createdOffset: 2),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byType(PriorityCard).first;
    // The child count, in the badge row — the one thing a tile says about
    // what is inside it.
    expect(
      find.descendant(of: card, matching: countBadge('2')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.subdirectory_arrow_right), findsOneWidget);
    // No titles of children on the owner's own face, as chips or otherwise.
    expect(find.byType(ItemChips), findsNothing);
    expect(find.text('First child'), findsNothing);

    await tester.drag(card, const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('First child'), findsOneWidget);
    // Whose tile this page belongs to, and which of the children it is.
    expect(find.text('Parent ›'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    final childTitle = tester.widget<Text>(find.text('First child'));
    expect(childTitle.maxLines, 1);
    expect(childTitle.overflow, TextOverflow.ellipsis);
  });

  testWidgets('every priority gets the same tile, well under the old 132dp '
      'floor', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          for (var i = 0; i < Priority.values.length; i++)
            node(
              '${Priority.values[i].label} node',
              priority: Priority.values[i],
              createdOffset: i,
            ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    final cards = find.byType(PriorityCard);
    expect(cards, findsNWidgets(Priority.values.length));
    final heights = {
      for (var i = 0; i < Priority.values.length; i++)
        tester.getSize(cards.at(i)).height,
    };
    expect(heights, hasLength(1), reason: 'one height for every priority');
    expect(
      heights.single,
      lessThan(132),
      reason: 'shorter than the floor the priority-scaled tiles had',
    );
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('a level of minimal tiles does not overflow at ${scale}x', (
      tester,
    ) async {
      usePhone(tester);
      await tester.pumpWidget(
        app(
          await seeded([
            for (var i = 0; i < Priority.values.length; i++)
              node(
                '$longTitle $i',
                priority: Priority.values[i],
                description: description,
                createdOffset: i,
              ),
            node('A child', parent: '$longTitle 0', createdOffset: 9),
          ]),
          textScale: scale,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'the level as it opens');

      // And on a child page, which carries the owner label on top of the
      // same three bands.
      await tester.drag(find.byType(PriorityCard).first, const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'a child page');
      expect(find.text('A child'), findsOneWidget);
    });
  }
}
