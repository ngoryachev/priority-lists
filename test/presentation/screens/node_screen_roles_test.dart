import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';
import 'package:provider/provider.dart';

/// The main screen is the active role's level: it lists that role's children,
/// adds into it, and is titled after it. Which role that is can change from the
/// chip bar at any depth, and nothing on a level may lift a node into the
/// roles.

PriorityNode node(
  String id, {
  String? parent,
  Priority priority = Priority.high,
  int position = 0,
  ColorPreset? color,
}) {
  final created = DateTime(2026, 1, 1).add(Duration(minutes: position));
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    priority: priority,
    position: position,
    colorPreset: color,
    createdAt: created,
    updatedAt: created,
  );
}

/// Two roles, each with a child of its own; "work" is the active one.
List<PriorityNode> twoRoles() => [
  node('work', priority: Priority.critical),
  node('a work task', parent: 'work'),
  node('home', priority: Priority.high, position: 1),
  node('a home task', parent: 'home'),
];

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

NodeTreeViewModel treeOf(WidgetTester tester) => Provider.of<NodeTreeViewModel>(
  tester.element(find.byType(NodeScreen).first),
  listen: false,
);

void main() {
  testWidgets('the main screen lists the active role\'s children only', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(await seeded(twoRoles())));
    await tester.pumpAndSettle();

    expect(cardTitles(tester), ['a work task']);
    // The role itself is a chip, never a card.
    expect(cardTitles(tester), isNot(contains('work')));
  });

  testWidgets('the app bar is titled after the active role', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(await seeded(twoRoles())));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'work'), findsOneWidget);
  });

  testWidgets('the app bar takes the role\'s own colour as its tint', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          node('work', priority: Priority.critical, color: ColorPreset.teal),
          node('a work task', parent: 'work'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(
      appBar.backgroundColor,
      Color(ColorPreset.teal.colorValue).withValues(alpha: 0.15),
    );
  });

  testWidgets('the FAB adds into the active role', (tester) async {
    usePhoneSize(tester);
    final repository = await seeded(twoRoles());
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(fab.tooltip, 'Add inside "work"');

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'another task');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    final stored = await repository.getAllNodes();
    expect(
      stored.firstWhere((n) => n.title == 'another task').parentId,
      'work',
    );
    expect(cardTitles(tester), contains('another task'));
  });

  testWidgets('switching a role swaps the level under the user', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(await seeded(twoRoles())));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'home'));
    await tester.pumpAndSettle();

    expect(cardTitles(tester), ['a home task']);
    expect(find.widgetWithText(AppBar, 'home'), findsOneWidget);
  });

  testWidgets('switching a role while drilled in pops back to the main screen',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          ...twoRoles(),
          node('deeper', parent: 'a work task'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('a work task'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'a work task'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'home'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'home'), findsOneWidget);
    expect(cardTitles(tester), ['a home task']);
    expect(find.byType(NodeScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('a role\'s child cannot be moved up a level, a deeper node can', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          ...twoRoles(),
          node('deeper', parent: 'a work task'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    // The level above a role's child is the role, and nothing may become one.
    expect(find.byIcon(Icons.arrow_upward), findsNothing);

    await tester.tap(find.text('a work task'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });

  testWidgets('an empty role invites adding to it rather than showing nothing',
      (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(await seeded([node('work', priority: Priority.critical)])),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing here yet'), findsOneWidget);
  });

  testWidgets('a tree with nothing in it gets a default Root role', (
    tester,
  ) async {
    final repository = await seeded([]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'Root'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Root'), findsOneWidget);
    final stored = await repository.getAllNodes();
    expect(stored.single.title, 'Root');
    expect(stored.single.priority, Priority.critical);
  });

  testWidgets('the chips stay pinned under the app bar while drilling down', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          ...twoRoles(),
          node('deeper', parent: 'a work task'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('a work task'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'work'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'home'), findsOneWidget);
  });

  testWidgets('the priority filter never hides a chip', (tester) async {
    usePhoneSize(tester);
    final filter = FilterViewModel();
    final repository = await seeded(twoRoles());
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => NodeTreeViewModel(repository),
            ),
            ChangeNotifierProvider.value(value: filter),
          ],
          child: const NodeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Critical only: "home" is an orange role, and roles are not list items.
    filter.setLevel(1);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, 'work'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'home'), findsOneWidget);
  });

  testWidgets('the History and Sign Out actions stay on the main screen', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(await seeded(twoRoles())));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.logout), findsOneWidget);
    // No Edit / Delete in the app bar for the role: the chip menu owns those.
    // (The cards on the level carry their own, as on any level.)
    Finder inAppBar(IconData icon) => find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(icon),
    );
    expect(inAppBar(Icons.edit_outlined), findsNothing);
    expect(inAppBar(Icons.delete_outline), findsNothing);
  });

  testWidgets('deleting the active role shows the successor\'s level', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(app(await seeded(twoRoles())));
    await tester.pumpAndSettle();

    await treeOf(tester).deleteRole('work');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'home'), findsOneWidget);
    expect(cardTitles(tester), ['a home task']);
  });
}
