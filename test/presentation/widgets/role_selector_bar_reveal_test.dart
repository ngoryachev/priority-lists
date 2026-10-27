import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_current_role_repository.dart';
import 'package:priority_lists/domain/models/role.dart';
import 'package:priority_lists/presentation/view_models/role_view_model.dart';
import 'package:priority_lists/presentation/widgets/role_selector_bar.dart';
import 'package:provider/provider.dart';

/// The bar now scrolls the active chip into view by itself. These checks cover
/// the cases the reveal must stay out of the way in: a width where nothing
/// scrolls at all, and a row the user has scrolled by hand.

Widget wrap(RoleViewModel vm) {
  return MaterialApp(
    home: ChangeNotifierProvider<RoleViewModel>.value(
      value: vm,
      child: const Scaffold(body: RoleSelectorBar()),
    ),
  );
}

ScrollableState rowState(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable));

ChoiceChip chipFor(WidgetTester tester, Role role) => tester.widget<ChoiceChip>(
  find.ancestor(of: find.text(role.label), matching: find.byType(ChoiceChip)),
);

void main() {
  testWidgets('on a width that fits every chip the row never moves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = InMemoryCurrentRoleRepository();
    await repository.save(Role.myself);
    final vm = RoleViewModel(repository: repository);
    await tester.pumpWidget(wrap(vm));

    await vm.load();
    await tester.pumpAndSettle();

    final position = rowState(tester).position;
    expect(chipFor(tester, Role.myself).selected, isTrue);
    expect(
      position.maxScrollExtent,
      0,
      reason: 'all six chips fit, so there is nothing to scroll',
    );
    expect(position.pixels, 0);
  });

  testWidgets('a hand-scrolled row stays put when a visible chip is picked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final vm = RoleViewModel();
    await tester.pumpWidget(wrap(vm));

    // The user drags the row to its trailing end themselves.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-1200, 0),
    );
    await tester.pumpAndSettle();
    final position = rowState(tester).position;
    final offsetBefore = position.pixels;
    expect(offsetBefore, position.maxScrollExtent);
    expect(offsetBefore, greaterThan(0));

    // ...and taps a chip that is now in plain sight there.
    await tester.tap(find.text(Role.myself.label));
    await tester.pumpAndSettle();

    expect(chipFor(tester, Role.myself).selected, isTrue);
    expect(
      rowState(tester).position.pixels,
      offsetBefore,
      reason: 'revealing a chip already on screen must not move the row',
    );
  });
}
