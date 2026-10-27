import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_current_role_repository.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/role.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/view_models/role_view_model.dart';
import 'package:priority_lists/presentation/widgets/role_selector_bar.dart';
import 'package:provider/provider.dart';

Widget wrap(RoleViewModel vm) {
  return MaterialApp(
    home: ChangeNotifierProvider<RoleViewModel>.value(
      value: vm,
      child: const Scaffold(body: RoleSelectorBar()),
    ),
  );
}

/// The roles the row currently paints as active — read off the chips, so
/// exclusivity is asserted for the whole bar and not just the chips tapped.
List<Role> activeRoles(WidgetTester tester) {
  final active = <Role>[];
  for (final role in Role.values) {
    final chip = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text(role.label),
        matching: find.byType(ChoiceChip),
      ),
    );
    if (chip.selected) active.add(role);
  }
  return active;
}

/// Taps a role's chip, scrolling the row to it first: six chips do not fit the
/// width of a phone, so the trailing ones start off-screen.
Future<void> tapRole(WidgetTester tester, Role role) async {
  final label = find.text(role.label);
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  await tester.tap(label);
  await tester.pump();
}

void main() {
  testWidgets('shows one chip per role, none selected at first', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(RoleViewModel()));

    expect(find.byType(ChoiceChip), findsNWidgets(Role.values.length));
    for (final role in Role.values) {
      expect(find.text(role.label), findsOneWidget);
    }
    expect(activeRoles(tester), isEmpty);
  });

  testWidgets('tapping a role selects it and deselects the previous one', (
    tester,
  ) async {
    final vm = RoleViewModel(repository: InMemoryCurrentRoleRepository());
    await tester.pumpWidget(wrap(vm));

    await tapRole(tester, Role.partner);
    expect(activeRoles(tester), [Role.partner]);
    expect(vm.selected, Role.partner);

    await tapRole(tester, Role.creator);
    expect(activeRoles(tester), [Role.creator]);
    expect(vm.selected, Role.creator);
  });

  testWidgets('re-tapping the active role keeps it selected', (tester) async {
    final vm = RoleViewModel();
    await tester.pumpWidget(wrap(vm));

    await tapRole(tester, Role.myself);
    await tapRole(tester, Role.myself);

    expect(activeRoles(tester), [Role.myself]);
  });

  testWidgets('shows the stored role picked up by the view model', (
    tester,
  ) async {
    final repository = InMemoryCurrentRoleRepository();
    await repository.save(Role.father);
    final vm = RoleViewModel(repository: repository);
    await tester.pumpWidget(wrap(vm));

    await vm.load();
    await tester.pump();

    expect(activeRoles(tester), [Role.father]);
  });

  testWidgets('scrolls instead of overflowing on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final vm = RoleViewModel();
    await tester.pumpWidget(wrap(vm));
    // pumpWidget rethrows a layout overflow, so getting here means the chips
    // did not blow out the 320 px width.

    // The trailing roles sit off-screen; the row scrolls to reach them.
    final scroller = find.byType(SingleChildScrollView);
    await tester.drag(scroller, const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );

    await tapRole(tester, Role.myself);
    expect(activeRoles(tester), [Role.myself]);
  });

  testWidgets('sits under the node screen app bar on a phone', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final PriorityNodeRepository repository = InMemoryPriorityNodeRepository();
    final vm = RoleViewModel();
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            Provider<PriorityNodeRepository>.value(value: repository),
            ChangeNotifierProvider(
              create: (_) => NodeTreeViewModel(repository),
            ),
            ChangeNotifierProvider(create: (_) => FilterViewModel()),
            ChangeNotifierProvider<RoleViewModel>.value(value: vm),
          ],
          child: const NodeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The bar is mounted and the body below it still has room — pumping
    // rethrows a layout overflow, so reaching here is the assertion.
    expect(find.byType(RoleSelectorBar), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(Role.values.length));

    final barBottom = tester.getRect(find.byType(RoleSelectorBar)).bottom;
    expect(barBottom, lessThan(200));
    expect(
      tester.getRect(find.byType(AppBar)).bottom,
      lessThanOrEqualTo(barBottom),
    );

    await tapRole(tester, Role.professional);
    expect(activeRoles(tester), [Role.professional]);
  });

  testWidgets('renders nothing when no role view model is provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RoleSelectorBar())),
    );

    expect(find.byType(ChoiceChip), findsNothing);
  });
}
