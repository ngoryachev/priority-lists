import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/breadcrumb_bar.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';
import 'package:provider/provider.dart';

PriorityNode node(
  String id, {
  String? parent,
  Priority priority = Priority.medium,
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

Future<PriorityNodeRepository> seeded(List<PriorityNode> nodes) async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes(nodes);
  return repository;
}

Widget wrap(PriorityNodeRepository repository, {FilterViewModel? filter}) {
  return MultiProvider(
    providers: [
      Provider<PriorityNodeRepository>.value(value: repository),
      ChangeNotifierProvider(create: (_) => NodeTreeViewModel(repository)),
      if (filter == null)
        ChangeNotifierProvider(create: (_) => FilterViewModel())
      else
        ChangeNotifierProvider.value(value: filter),
    ],
    child: const MaterialApp(home: NodeScreen()),
  );
}

/// The production tree: [AuthGate] builds the tree providers *below*
/// `MaterialApp`, so the [Navigator] sits above them and a pushed route is
/// built outside their scope. Drilling down has to keep working there too.
Widget wrapLikeProduction(
  PriorityNodeRepository repository, {
  FilterViewModel? filter,
}) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        Provider<PriorityNodeRepository>.value(value: repository),
        ChangeNotifierProvider(create: (_) => NodeTreeViewModel(repository)),
        if (filter == null)
          ChangeNotifierProvider(create: (_) => FilterViewModel())
        else
          ChangeNotifierProvider.value(value: filter),
      ],
      child: const NodeScreen(),
    ),
  );
}

/// The default 800x600 test view is too short for medium tiles to clear the
/// compact threshold, which is what gates chips.
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('NodeScreen', () {
    testWidgets('top level lists root nodes with child chips', (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        node('Work', priority: Priority.critical),
        node('Fix bug', parent: 'Work', priority: Priority.high),
        node('Home', priority: Priority.high),
        node('Buy milk', parent: 'Home', priority: Priority.medium),
      ]);

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Work'), findsOneWidget);
      expect(find.textContaining('Fix bug'), findsWidgets);
      // Nesting is flagged by a child-count badge on the tile itself.
      expect(find.byIcon(Icons.subdirectory_arrow_right), findsNWidgets(2));
    });

    testWidgets('drills down when the providers sit below the Navigator',
        (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        node('Work', priority: Priority.critical),
        node('Fix bug', parent: 'Work', priority: Priority.high),
        node('Deeper', parent: 'Fix bug', priority: Priority.high),
      ]);

      await tester.pumpWidget(wrapLikeProduction(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(AppBar, 'Work'), findsOneWidget);

      // And again, so a route pushed from an already-pushed route is covered.
      await tester.tap(find.text('Fix bug').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(AppBar, 'Fix bug'), findsOneWidget);
      expect(find.text('Deeper'), findsWidgets);
    });

    testWidgets('drills into a node and shows its children', (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        node('Work', priority: Priority.critical),
        node('Fix bug', parent: 'Work', priority: Priority.high),
      ]);

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();

      // The pushed level is titled after the node and lists its children.
      expect(find.widgetWithText(AppBar, 'Work'), findsOneWidget);
      expect(find.text('Fix bug'), findsWidgets);
    });

    testWidgets('nests as deep as asked, with breadcrumbs past level two',
        (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        node('L0', priority: Priority.critical),
        node('L1', parent: 'L0', priority: Priority.critical),
        node('L2', parent: 'L1', priority: Priority.critical),
        node('L3', parent: 'L2', priority: Priority.critical),
      ]);

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();

      // No trail at the top level, nor one level in.
      expect(find.byType(BreadcrumbBar), findsNothing);
      await tester.tap(find.text('L0'));
      await tester.pumpAndSettle();
      expect(find.byType(BreadcrumbBar), findsNothing);

      await tester.tap(find.text('L1').last);
      await tester.pumpAndSettle();
      expect(find.byType(BreadcrumbBar), findsOneWidget);

      await tester.tap(find.text('L2').last);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'L2'), findsOneWidget);
      expect(find.text('L3'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a breadcrumb jumps back to that ancestor', (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        node('L0', priority: Priority.critical),
        node('L1', parent: 'L0', priority: Priority.critical),
        node('L2', parent: 'L1', priority: Priority.critical),
      ]);

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('L0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('L1').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'L1'), findsOneWidget);

      // Tap the "L0" crumb inside the trail.
      await tester.tap(
        find.descendant(
          of: find.byType(BreadcrumbBar),
          matching: find.text('L0'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'L0'), findsOneWidget);
    });

    testWidgets('chips honor the priority filter', (tester) async {
      usePhoneSize(tester);
      final filter = FilterViewModel();
      final repository = await seeded([
        node('Work', priority: Priority.critical),
        node('Fix bug', parent: 'Work', priority: Priority.high),
      ]);

      await tester.pumpWidget(wrap(repository, filter: filter));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fix bug'), findsWidgets);

      filter.setLevel(1); // only critical stays visible
      await tester.pumpAndSettle();

      expect(find.textContaining('Fix bug'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bubble view renders a level without exceptions',
        (tester) async {
      final repository = await seeded([
        node('Work', priority: Priority.critical),
        for (var i = 0; i < 7; i++)
          node('Task $i',
              parent: 'Work',
              priority: Priority.critical,
              createdOffset: i),
        node('Backlog', priority: Priority.low),
        node('Later', parent: 'Backlog', priority: Priority.low),
      ]);

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bubble_chart));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      // A critical bubble is wide enough for four chips, so the remaining
      // three of the seven children collapse into "+3".
      expect(find.text('+3'), findsOneWidget);
      // Low nodes stay plain — too small to carry chips.
      expect(find.text('Later'), findsNothing);
    });

    testWidgets('an empty level invites adding to it', (tester) async {
      final repository = await seeded([node('Work', priority: Priority.high)]);

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing here yet'), findsOneWidget);
    });

    testWidgets('a level hidden by the filter says so', (tester) async {
      final filter = FilterViewModel();
      final repository = await seeded([
        node('Work', priority: Priority.critical),
        node('Someday', parent: 'Work', priority: Priority.low),
      ]);

      await tester.pumpWidget(wrap(repository, filter: filter));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();

      filter.setLevel(1);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('hidden by the priority filter'),
        findsOneWidget,
      );
    });

    testWidgets('dragging a card by its handle reorders the level',
        (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        node('First', priority: Priority.critical),
        node('Second', priority: Priority.critical),
      ]);

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();

      List<String> orderOnScreen() => tester
          .widgetList<PriorityCard>(find.byType(PriorityCard))
          .map((card) => card.title)
          .toList();

      expect(orderOnScreen(), ['First', 'Second']);

      // Grab the second card's handle and drag it above the first.
      final handle = find.byIcon(Icons.drag_indicator).at(1);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      // A short nudge past the drag slop first, then the real travel: the
      // recognizer only picks up the drag once it has moved.
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(orderOnScreen(), ['Second', 'First']);

      // The order is persisted, not just a visual swap.
      final stored = await repository.getAllNodes()
        ..sort((a, b) => a.position.compareTo(b.position));
      expect(stored.map((n) => n.title), ['Second', 'First']);
    });

    testWidgets('node actions replace sign-out once inside the tree',
        (tester) async {
      final repository = await seeded([node('Work', priority: Priority.high)]);

      await tester.pumpWidget(wrap(repository));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.logout), findsOneWidget);

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.logout), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsWidgets);
      expect(find.byIcon(Icons.delete_outline), findsWidgets);
    });
  });
}
