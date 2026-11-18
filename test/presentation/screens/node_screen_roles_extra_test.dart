import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/breadcrumb_bar.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';
import 'package:provider/provider.dart';

/// What happens around the main screen once the roles are the top level: a
/// node handed from one role to another, a drag on the role's own level, and
/// the breadcrumbs of a level two deep inside a role.

PriorityNode node(
  String id, {
  String? parent,
  Priority priority = Priority.high,
  int position = 0,
}) {
  final created = DateTime(2026, 1, 1).add(Duration(minutes: position));
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    priority: priority,
    position: position,
    createdAt: created,
    updatedAt: created,
  );
}

Future<InMemoryPriorityNodeRepository> seeded(List<PriorityNode> nodes) async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes(nodes);
  return repository;
}

Widget app(InMemoryPriorityNodeRepository repository) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NodeTreeViewModel(repository)),
        ChangeNotifierProvider(create: (_) => FilterViewModel()),
      ],
      child: const NodeScreen(),
    ),
  );
}

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

List<String> cardTitles(WidgetTester tester) => tester
    .widgetList<PriorityCard>(find.byType(PriorityCard))
    .map((card) => card.title)
    .toList();

List<String> chipOrder(WidgetTester tester) => tester
    .widgetList<ChoiceChip>(find.byType(ChoiceChip))
    .map((chip) => ((chip.label as Text).data)!)
    .toList();

NodeTreeViewModel treeOf(WidgetTester tester) => Provider.of<NodeTreeViewModel>(
  tester.element(find.byType(NodeScreen).first),
  listen: false,
);

void main() {
  testWidgets('a node can be handed to another role and shows up there', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(await _twoRoles());
    await tester.pumpAndSettle();
    expect(cardTitles(tester), ['a work task']);

    // "Move into another node" on the card, then the full-tree picker.
    await tester.tap(find.byTooltip('Move into another node').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick from tree…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'home'));
    await tester.pumpAndSettle();

    expect(treeOf(tester).tree.nodeById('a work task')!.parentId, 'home');
    expect(cardTitles(tester), isEmpty);

    // And it is there under the other role, which is a chip tap away.
    await tester.tap(find.widgetWithText(ChoiceChip, 'home'));
    await tester.pumpAndSettle();
    expect(cardTitles(tester), containsAll(['a home task', 'a work task']));
  });

  testWidgets('a drag on the role\'s level leaves the chips where they are', (
    tester,
  ) async {
    usePhoneSize(tester);
    final repository = await seeded([
      node('work', priority: Priority.critical),
      node('home', priority: Priority.low, position: 1),
      node('rest', priority: Priority.low, position: 2),
      node('first', parent: 'work', priority: Priority.high, position: 0),
      node('second', parent: 'work', priority: Priority.high, position: 1),
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(cardTitles(tester), ['first', 'second']);

    final vm = treeOf(tester);
    await vm.reorderChildren(
      parentId: 'work',
      visible: vm.tree.childrenOf('work'),
      oldIndex: 1,
      newIndex: 0,
    );
    await tester.pumpAndSettle();

    expect(cardTitles(tester), ['second', 'first']);
    // The roles are a different level and keep their own numbering.
    expect(chipOrder(tester), ['work', 'home', 'rest']);
    expect(
      vm.rolesInChipOrder.map((r) => r.position).toList(),
      [0, 1, 2],
    );
  });

  testWidgets('breadcrumbs two levels into a role never show the role', (
    tester,
  ) async {
    usePhoneSize(tester);
    final repository = await seeded([
      node('work', priority: Priority.critical),
      node('A', parent: 'work'),
      node('B', parent: 'A'),
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PriorityCard, 'A'));
    await tester.pumpAndSettle();
    // One level in there is no trail yet: the title says where we are.
    expect(find.byType(BreadcrumbBar), findsNothing);

    await tester.tap(find.widgetWithText(PriorityCard, 'B'));
    await tester.pumpAndSettle();

    expect(find.byType(BreadcrumbBar), findsOneWidget);
    final crumbs = tester.widget<BreadcrumbBar>(find.byType(BreadcrumbBar));
    expect(crumbs.ancestors.map((n) => n.title).toList(), ['A']);
  });

  testWidgets('a role\'s grandchild lifted one level lands on the main screen',
      (tester) async {
    usePhoneSize(tester);
    final repository = await seeded([
      node('work', priority: Priority.critical),
      node('A', parent: 'work'),
      node('B', parent: 'A'),
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PriorityCard, 'A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move up one level').first);
    await tester.pumpAndSettle();

    expect(treeOf(tester).tree.nodeById('B')!.parentId, 'work');
    // Back out to the main screen: B is now a sibling of A.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(cardTitles(tester), containsAll(['A', 'B']));
    // And it never became a role of its own.
    expect(chipOrder(tester), ['work']);
  });
}

Future<Widget> _twoRoles() async {
  final repository = await seeded([
    node('work', priority: Priority.critical),
    node('a work task', parent: 'work'),
    node('home', priority: Priority.high, position: 1),
    node('a home task', parent: 'home'),
  ]);
  return app(repository);
}
