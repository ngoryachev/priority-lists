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
import 'package:provider/provider.dart';

/// Phone-shaped checks: small screens, large text, landscape, and tap targets.
/// The tree adds a level of chrome (breadcrumbs, a child-count badge) to an
/// already dense card, so these sizes are where it would break first.

PriorityNode node(
  String id, {
  String? parent,
  Priority priority = Priority.critical,
  String description = '',
}) {
  final created = DateTime(2026, 1, 1);
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

Future<PriorityNodeRepository> seededChain() async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes([
    node('A long enough root title to wrap on a narrow phone'),
    node('L1', parent: 'A long enough root title to wrap on a narrow phone'),
    node('L2', parent: 'L1'),
    node('L3', parent: 'L2', description: 'Some describing text that is not short'),
    node('Sibling', parent: 'L2', priority: Priority.low),
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
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: const NodeScreen(),
        ),
      ),
    ),
  );
}

void useScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Walks down [depth] levels, tapping the first card each time.
Future<void> drill(WidgetTester tester, List<String> titles) async {
  for (final title in titles) {
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'opening "$title" threw');
  }
}

void main() {
  group('NodeScreen on a phone', () {
    testWidgets('renders every level on a small phone', (tester) async {
      useScreen(tester, const Size(320, 568)); // iPhone SE, the tightest case
      final repository = await seededChain();

      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await drill(tester, [
        'A long enough root title to wrap on a narrow phone',
        'L1',
        'L2',
      ]);

      expect(find.byType(BreadcrumbBar), findsOneWidget);
      expect(find.text('L3'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives large text at depth', (tester) async {
      useScreen(tester, const Size(360, 640));
      final repository = await seededChain();

      await tester.pumpWidget(app(repository, textScale: 1.6));
      await tester.pumpAndSettle();
      await drill(tester, [
        'A long enough root title to wrap on a narrow phone',
        'L1',
        'L2',
      ]);

      expect(tester.takeException(), isNull);
    });

    testWidgets('survives landscape at depth', (tester) async {
      useScreen(tester, const Size(740, 360));
      final repository = await seededChain();

      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await drill(tester, [
        'A long enough root title to wrap on a narrow phone',
        'L1',
        'L2',
      ]);

      expect(tester.takeException(), isNull);
      expect(find.byType(BreadcrumbBar), findsOneWidget);
    });

    testWidgets('breadcrumbs give every crumb a finger-sized tap target',
        (tester) async {
      useScreen(tester, const Size(360, 640));
      final repository = await seededChain();

      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await drill(tester, [
        'A long enough root title to wrap on a narrow phone',
        'L1',
        'L2',
      ]);

      final crumbs = find.descendant(
        of: find.byType(BreadcrumbBar),
        matching: find.byType(InkWell),
      );
      expect(crumbs, findsWidgets);
      for (var i = 0; i < tester.widgetList(crumbs).length; i++) {
        final size = tester.getSize(crumbs.at(i));
        expect(size.height, greaterThanOrEqualTo(44),
            reason: 'crumb $i is only ${size.height}dp tall');
        expect(size.width, greaterThanOrEqualTo(44),
            reason: 'crumb $i is only ${size.width}dp wide');
      }
    });

    testWidgets('a deep breadcrumb trail scrolls instead of overflowing',
        (tester) async {
      useScreen(tester, const Size(320, 568));
      final repository = InMemoryPriorityNodeRepository();
      // Ten nested levels with titles far wider than the bar.
      final titles = [
        for (var i = 0; i < 10; i++) 'Level number $i with a wide title',
      ];
      await repository.saveNodes([
        for (var i = 0; i < titles.length; i++)
          node(titles[i], parent: i == 0 ? null : titles[i - 1]),
      ]);

      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();
      await drill(tester, titles.sublist(0, titles.length - 1));

      expect(tester.takeException(), isNull);
      expect(find.byType(BreadcrumbBar), findsOneWidget);
      // The last crumb is the one kept in view by the reversed scroll view.
      expect(
        find.descendant(
          of: find.byType(BreadcrumbBar),
          matching: find.text(titles[titles.length - 3]),
        ),
        findsOneWidget,
      );
    });
  });
}
