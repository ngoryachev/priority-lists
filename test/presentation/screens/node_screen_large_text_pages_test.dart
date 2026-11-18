import 'package:flutter/material.dart';
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

/// A real level, on a real phone, with the text scaled up: the card's child
/// pages carry an extra line the owner's own face does not, and the tile
/// heights the list builds (160dp, or the 132dp floor) have the least room
/// to spare of anything the app renders.

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

/// One parent per priority, each with children of its own that have long
/// titles, a description and grandchildren (so the chips row is populated).
Future<PriorityNodeRepository> seeded() async {
  final nodes = <PriorityNode>[];
  var offset = 0;
  for (final priority in Priority.values) {
    final parent = 'Parent ${priority.label} with a title that wraps';
    nodes.add(
      node(parent, priority: priority, createdOffset: offset++, description: 'A describing line for the parent'),
    );
    for (var i = 0; i < 3; i++) {
      final child = 'Child $i of ${priority.label}, long enough to wrap twice';
      nodes.add(
        node(
          child,
          parent: parent,
          priority: Priority.values[i % Priority.values.length],
          createdOffset: offset++,
          description: 'A description on the child that is not short either',
        ),
      );
      nodes.add(node('$child / grandchild', parent: child, createdOffset: offset++));
    }
  }
  final repository = InMemoryPriorityNodeRepository();
  // The tree's top level is the roles and the main screen lists the children
  // of the active one, so every parent here hangs off one explicit role node.
  await repository.saveNodes([
    node('Role', priority: Priority.critical),
    for (final n in nodes) n.parentId == null ? n.withParent('Role') : n,
  ]);
  return repository;
}

Widget app(PriorityNodeRepository repository, {required double textScale}) {
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

/// The 1-4 buttons, told apart from the child-count badge (which also shows a
/// bare number) by the button's own type size.
Finder levelButton(String level) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && widget.data == level && widget.style?.fontSize == 14,
);

void main() {
  // 1.6 is what the existing mobile tests use, 1.7 is the last scale at which
  // a tight tile still renders the owner label, 1.8 the first one past it.
  for (final scale in [1.6, 1.7, 1.8]) {
    testWidgets('a 360x800 level swipes through its children at ${scale}x '
        'without overflowing', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app(await seeded(), textScale: scale));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'the level as it opens');

      // Every tile on screen, over all three of its child pages.
      for (var tile = 0; tile < 2; tile++) {
        for (var page = 1; page <= 3; page++) {
          final card = find.byType(PriorityCard).at(tile);
          await tester.drag(card, const Offset(-300, 0));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'tile $tile on page $page at ${scale}x',
          );

          for (final level in ['1', '2', '3', '4']) {
            expect(
              find
                  .descendant(of: card, matching: levelButton(level))
                  .hitTestable(),
              findsOneWidget,
              reason: 'the $level button on tile $tile page $page at '
                  '${scale}x',
            );
          }
          expect(
            find
                .descendant(
                  of: card,
                  matching: find.byIcon(Icons.drag_handle),
                )
                .hitTestable(),
            findsOneWidget,
            reason: 'the grip on tile $tile page $page at ${scale}x',
          );
          expect(
            find.descendant(of: card, matching: find.text('$page/3')),
            findsOneWidget,
            reason: 'the counter on tile $tile at ${scale}x',
          );
        }
      }
    });
  }
}
