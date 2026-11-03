import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';
import 'package:provider/provider.dart';

/// The exclusive-`critical` rule lives in the view model, so the screen only
/// has to route the 1-4 button row through it. These tests check that wiring
/// from the widget the user actually taps.
void main() {
  late InMemoryPriorityNodeRepository repository;
  late NodeTreeViewModel vm;

  PriorityNode seed(
    String id,
    Priority priority, {
    int position = 0,
    int createdOffset = 0,
  }) {
    final created = DateTime(2026).add(Duration(minutes: createdOffset));
    return PriorityNode(
      id: id,
      title: id,
      priority: priority,
      position: position,
      createdAt: created,
      updatedAt: created,
    );
  }

  Widget wrap() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: vm),
        ChangeNotifierProvider(create: (_) => FilterViewModel()),
      ],
      child: const MaterialApp(home: NodeScreen()),
    );
  }

  /// The "1" (critical) button inside the card titled [title].
  Finder criticalButtonOf(String title) => find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(PriorityCard),
        ),
        matching: find.text('1'),
      );

  setUp(() {
    repository = InMemoryPriorityNodeRepository();
    vm = NodeTreeViewModel(repository);
  });

  testWidgets('the 1 button demotes the sibling that held the red slot',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await repository.saveNodes([
      seed('Incumbent', Priority.critical),
      seed('Orange', Priority.high, position: 1, createdOffset: 1),
      seed('Challenger', Priority.medium, position: 2, createdOffset: 2),
    ]);
    await vm.load();

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(criticalButtonOf('Challenger'));
    await tester.pumpAndSettle();

    expect(vm.tree.nodeById('Challenger')!.priority, Priority.critical);
    expect(vm.tree.nodeById('Incumbent')!.priority, Priority.high);
    expect(
      vm.tree.roots.map((n) => n.id),
      ['Challenger', 'Incumbent', 'Orange'],
      reason: 'the demoted red is parked above the orange already there',
    );
  });

  testWidgets('tapping 1 on the node that is already red changes nothing',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await repository.saveNodes([
      seed('Red', Priority.critical),
      seed('Orange', Priority.high, position: 1, createdOffset: 1),
    ]);
    await vm.load();

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(criticalButtonOf('Red'));
    await tester.pumpAndSettle();

    expect(vm.tree.nodeById('Orange')!.priority, Priority.high);
    expect(vm.tree.nodeById('Orange')!.updatedAt, DateTime(2026, 1, 1, 0, 1));
    expect(vm.tree.roots.map((n) => n.id), ['Red', 'Orange']);
  });
}
