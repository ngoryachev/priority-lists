import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/node_tree.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/presentation/widgets/move_node_dialog.dart';

/// The full-tree move picker. Since the tree's top level is the roles, it
/// offers no "top level" of its own any more: a node lifted there would
/// silently become a role.

PriorityNode node(String id, {String? parent}) {
  final created = DateTime(2026, 1, 1);
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    priority: Priority.high,
    createdAt: created,
    updatedAt: created,
  );
}

/// Two roles, each with a child.
final tree = NodeTree([
  node('work'),
  node('a work task', parent: 'work'),
  node('home'),
  node('a home task', parent: 'home'),
]);

Future<MoveDestination?> show(WidgetTester tester, PriorityNode moving) async {
  MoveDestination? picked;
  var opened = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          if (!opened) {
            opened = true;
            Future.microtask(() async {
              picked = await MoveNodeDialog.show(
                context,
                tree: tree,
                node: moving,
              );
            });
          }
          return const Scaffold(body: SizedBox());
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  testWidgets('offers no "Top level" destination', (tester) async {
    await show(tester, tree.nodeById('a work task')!);

    expect(find.text('Top level'), findsNothing);
    expect(find.text('No parent'), findsNothing);
  });

  testWidgets('the roles are still destinations, so a node can change role', (
    tester,
  ) async {
    await show(tester, tree.nodeById('a work task')!);

    expect(find.text('home'), findsOneWidget);
    await tester.tap(find.text('home'));
    await tester.pumpAndSettle();

    // The dialog is gone, having picked the other role as the new parent.
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the current parent is offered but not tappable', (tester) async {
    await show(tester, tree.nodeById('a work task')!);

    final tile = tester.widget<ListTile>(
      find.ancestor(of: find.text('work'), matching: find.byType(ListTile)),
    );
    expect(tile.enabled, isFalse);
    expect(find.text('Current parent'), findsOneWidget);
  });

  testWidgets('a role itself can be moved under another role', (tester) async {
    await show(tester, tree.nodeById('work')!);

    // Its own subtree is out, the other role is in — and there is no way back
    // to the top level.
    expect(find.text('a work task'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(find.text('Top level'), findsNothing);
  });
}
