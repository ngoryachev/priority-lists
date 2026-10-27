import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/models/role.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/view_models/role_view_model.dart';
import 'package:priority_lists/presentation/widgets/role_selector_bar.dart';
import 'package:provider/provider.dart';

/// The role bar is pinned to every level of the tree and shares one view model
/// across pushed routes, so these checks walk down the tree instead of pumping
/// the bar on its own: drilling down is where the provider scope and the extra
/// chrome height would break first.

PriorityNode node(String id, {String? parent, String description = ''}) {
  final created = DateTime(2026, 1, 1);
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    description: description,
    priority: Priority.critical,
    createdAt: created,
    updatedAt: created,
  );
}

Future<PriorityNodeRepository> seededChain() async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes([
    node('Root'),
    node('L1', parent: 'Root'),
    node('L2', parent: 'L1', description: 'Some describing text, not short'),
  ]);
  return repository;
}

/// Mirrors production: the tree providers sit *below* `MaterialApp`, so a
/// pushed route is built outside their scope.
Widget app(
  PriorityNodeRepository repository,
  RoleViewModel roles, {
  double textScale = 1.0,
}) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        Provider<PriorityNodeRepository>.value(value: repository),
        ChangeNotifierProvider(create: (_) => NodeTreeViewModel(repository)),
        ChangeNotifierProvider(create: (_) => FilterViewModel()),
        ChangeNotifierProvider<RoleViewModel>.value(value: roles),
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

void useScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> drill(WidgetTester tester, List<String> titles) async {
  for (final title in titles) {
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'opening "$title" threw');
  }
}

/// The roles the visible bar paints as active.
List<Role> activeRoles(WidgetTester tester) {
  final active = <Role>[];
  for (final role in Role.values) {
    final chip = tester.widget<ChoiceChip>(
      find
          .ancestor(
            of: find.text(role.label),
            matching: find.byType(ChoiceChip),
          )
          .first,
    );
    if (chip.selected) active.add(role);
  }
  return active;
}

Future<void> tapRole(WidgetTester tester, Role role) async {
  final label = find.text(role.label).first;
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  await tester.tap(label);
  await tester.pump();
}

void main() {
  group('RoleSelectorBar in the tree', () {
    testWidgets('stays pinned and keeps the pick while drilling down', (
      tester,
    ) async {
      useScreen(tester, const Size(400, 900));
      final repository = await seededChain();
      final roles = RoleViewModel();

      await tester.pumpWidget(app(repository, roles));
      await tester.pumpAndSettle();
      await tapRole(tester, Role.partner);

      await drill(tester, ['Root', 'L1']);

      expect(find.byType(RoleSelectorBar), findsOneWidget);
      expect(activeRoles(tester), [Role.partner]);
    });

    testWidgets('a pick made two levels down is the one the root shows', (
      tester,
    ) async {
      useScreen(tester, const Size(400, 900));
      final repository = await seededChain();
      final roles = RoleViewModel();

      await tester.pumpWidget(app(repository, roles));
      await tester.pumpAndSettle();
      await tapRole(tester, Role.father);

      await drill(tester, ['Root', 'L1']);
      await tapRole(tester, Role.creator);
      expect(activeRoles(tester), [Role.creator]);

      // Back to the root: the same single slot, so the deep pick shows here.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(roles.selected, Role.creator);
      expect(activeRoles(tester), [Role.creator]);
    });

    testWidgets('does not overflow at depth on the tightest phone', (
      tester,
    ) async {
      useScreen(tester, const Size(320, 568)); // iPhone SE
      final repository = await seededChain();

      await tester.pumpWidget(app(repository, RoleViewModel()));
      await tester.pumpAndSettle();
      await drill(tester, ['Root', 'L1']);

      expect(tester.takeException(), isNull);
      expect(find.byType(RoleSelectorBar), findsOneWidget);
    });

    testWidgets('does not overflow with large text at depth', (tester) async {
      useScreen(tester, const Size(360, 640));
      final repository = await seededChain();

      await tester.pumpWidget(
        app(repository, RoleViewModel(), textScale: 1.6),
      );
      await tester.pumpAndSettle();
      await drill(tester, ['Root', 'L1']);

      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overflow in landscape at depth', (tester) async {
      useScreen(tester, const Size(740, 360));
      final repository = await seededChain();

      await tester.pumpWidget(app(repository, RoleViewModel()));
      await tester.pumpAndSettle();
      await drill(tester, ['Root', 'L1']);

      expect(tester.takeException(), isNull);
      expect(find.byType(RoleSelectorBar), findsOneWidget);
    });

    testWidgets('survives the bubble view on a phone', (tester) async {
      useScreen(tester, const Size(360, 640));
      final repository = await seededChain();

      await tester.pumpWidget(app(repository, RoleViewModel()));
      await tester.pumpAndSettle();
      // The bubble view runs a ticker that never settles, so pump by hand.
      await tester.tap(find.byTooltip('Bubble View'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(RoleSelectorBar), findsOneWidget);
    });

    testWidgets('gives every chip a finger-sized tap target', (tester) async {
      useScreen(tester, const Size(360, 640));
      final repository = await seededChain();

      await tester.pumpWidget(app(repository, RoleViewModel()));
      await tester.pumpAndSettle();

      final chips = find.byType(ChoiceChip);
      expect(chips, findsNWidgets(Role.values.length));
      for (var i = 0; i < Role.values.length; i++) {
        final size = tester.getSize(chips.at(i));
        expect(
          size.height,
          greaterThanOrEqualTo(44),
          reason: 'chip $i is only ${size.height}dp tall',
        );
      }
    });
  });
}
