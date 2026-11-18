import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/role_selector_bar.dart';
import 'package:provider/provider.dart';

/// The corners of the chip bar the main suite does not reach: a roles level
/// with holes in its `position` numbering (what deleting a middle role leaves
/// behind), a level that never had positions at all (a local install from
/// before roles existed), and a level holding two reds (a tree written by
/// another device between two switches).

PriorityNode node(
  String id, {
  Priority priority = Priority.medium,
  int position = 0,
  String? parent,
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime(2026, 1, 1).add(Duration(days: position));
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

Future<(InMemoryPriorityNodeRepository, NodeTreeViewModel)> seeded(
  List<PriorityNode> nodes,
) async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes(nodes);
  final vm = NodeTreeViewModel(repository);
  await vm.load();
  return (repository, vm);
}

Widget wrap(NodeTreeViewModel vm) {
  return MaterialApp(
    home: ChangeNotifierProvider<NodeTreeViewModel>.value(
      value: vm,
      child: const Scaffold(body: Column(children: [RoleSelectorBar()])),
    ),
  );
}

Finder chipOf(String title) => find.widgetWithText(ChoiceChip, title);

List<String> chipOrder(WidgetTester tester) => tester
    .widgetList<ChoiceChip>(find.byType(ChoiceChip))
    .map((chip) => ((chip.label as Text).data)!)
    .toList();

String activeChip(WidgetTester tester) {
  final active = tester
      .widgetList<ChoiceChip>(find.byType(ChoiceChip))
      .where((chip) => chip.selected);
  expect(active, hasLength(1), reason: 'exactly one chip is ever active');
  return ((active.first.label as Text).data)!;
}

Future<void> openMenu(WidgetTester tester, String title) async {
  await tester.longPress(chipOf(title));
  await tester.pumpAndSettle();
}

Future<void> tapMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> addRole(WidgetTester tester, String title) async {
  await tester.tap(find.widgetWithText(ActionChip, '+'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, title);
  await tester.tap(find.widgetWithText(FilledButton, 'Create'));
  await tester.pumpAndSettle();
}

Future<void> deleteRole(WidgetTester tester, String title) async {
  await openMenu(tester, title);
  await tapMenuItem(tester, 'Delete');
  await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a role added after a middle one was deleted goes last', (
    tester,
  ) async {
    final (_, vm) = await seeded([
      node('work', priority: Priority.critical),
      node('home', priority: Priority.high, position: 1),
      node('rest', priority: Priority.low, position: 2),
      node('play', priority: Priority.low, position: 3),
    ]);
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    // Two roles out of the middle of the row: deleting leaves the positions of
    // the survivors alone, so the level is now numbered 0 and 3.
    await deleteRole(tester, 'home');
    await deleteRole(tester, 'rest');
    expect(chipOrder(tester), ['work', 'play']);

    await addRole(tester, 'study');

    expect(chipOrder(tester), ['work', 'play', 'study']);
  });

  testWidgets('a role added to a level that never had positions goes last', (
    tester,
  ) async {
    // What a local install from before roles existed looks like: every
    // top-level node written with the default position 0.
    final (_, vm) = await seeded([
      node('work', priority: Priority.critical, createdAt: DateTime(2026, 1, 1)),
      node('home', priority: Priority.high, createdAt: DateTime(2026, 1, 2)),
      node('rest', priority: Priority.low, createdAt: DateTime(2026, 1, 3)),
    ]);
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();
    expect(chipOrder(tester), ['work', 'home', 'rest']);

    await addRole(tester, 'study');

    expect(chipOrder(tester), ['work', 'home', 'rest', 'study']);
  });

  testWidgets('a level that never had positions can still be reordered', (
    tester,
  ) async {
    final (repository, vm) = await seeded([
      node('work', priority: Priority.critical, createdAt: DateTime(2026, 1, 1)),
      node('home', priority: Priority.high, createdAt: DateTime(2026, 1, 2)),
      node('rest', priority: Priority.low, createdAt: DateTime(2026, 1, 3)),
    ]);
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    await openMenu(tester, 'rest');
    await tapMenuItem(tester, 'Move left');

    expect(chipOrder(tester), ['work', 'rest', 'home']);
    // And it survives a reload, which is the point of writing `position`.
    final reloaded = NodeTreeViewModel(repository);
    await reloaded.load();
    expect(
      reloaded.rolesInChipOrder.map((n) => n.id).toList(),
      ['work', 'rest', 'home'],
    );
  });

  testWidgets('two reds in storage still mark exactly one chip', (
    tester,
  ) async {
    // Another device can write a second red role between two of our reads;
    // the bar has to pick one rather than paint two active chips.
    final (_, vm) = await seeded([
      node('work', priority: Priority.critical),
      node('home', priority: Priority.critical, position: 1),
      node('rest', priority: Priority.low, position: 2),
    ]);
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    expect(activeChip(tester), 'work');

    // Switching away has to settle the level: both former reds drop to high.
    await tester.tap(chipOf('rest'));
    await tester.pumpAndSettle();

    expect(activeChip(tester), 'rest');
    expect(vm.tree.nodeById('work')!.priority, Priority.high);
    expect(vm.tree.nodeById('home')!.priority, Priority.high);
    expect(chipOrder(tester), ['work', 'home', 'rest']);
  });

  testWidgets('deleting the active role promotes the leftmost chip left', (
    tester,
  ) async {
    // The survivors share a priority, so sibling order comes down to position:
    // the leftmost chip is the one that must turn red.
    final (_, vm) = await seeded([
      node('work', priority: Priority.critical, position: 0),
      node('home', priority: Priority.low, position: 1),
      node('rest', priority: Priority.low, position: 2),
    ]);
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    await deleteRole(tester, 'work');

    expect(chipOrder(tester), ['home', 'rest']);
    expect(activeChip(tester), 'home');
    expect(vm.tree.nodeById('home')!.priority, Priority.critical);
    expect(vm.tree.nodeById('rest')!.priority, Priority.low);
  });

  testWidgets('roles added one after another keep going to the end', (
    tester,
  ) async {
    // Two adds in a row on a level that already has a hole: the second one has
    // to sit past the first, not reuse the position the first just took.
    final (repository, vm) = await seeded([
      node('work', priority: Priority.critical, position: 0),
      node('home', priority: Priority.high, position: 1),
      node('play', priority: Priority.low, position: 2),
    ]);
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    await deleteRole(tester, 'home');
    await addRole(tester, 'study');
    await addRole(tester, 'chores');

    expect(chipOrder(tester), ['work', 'play', 'study', 'chores']);
    final positions = vm.rolesInChipOrder.map((n) => n.position).toList();
    expect(
      positions.toSet(),
      hasLength(positions.length),
      reason: 'the level never holds two chips at the same position',
    );
    // And the row reads the same way after a restart.
    final reloaded = NodeTreeViewModel(repository);
    await reloaded.load();
    expect(
      reloaded.rolesInChipOrder.map((n) => n.title).toList(),
      ['work', 'play', 'study', 'chores'],
    );
  });

  testWidgets('a role added after the leading roles were deleted goes last', (
    tester,
  ) async {
    // The survivors start at position 2, so a count-based position would land
    // the new chip at the head of the row.
    final (_, vm) = await seeded([
      node('work', priority: Priority.critical, position: 0),
      node('home', priority: Priority.low, position: 1),
      node('rest', priority: Priority.low, position: 2),
      node('play', priority: Priority.low, position: 3),
    ]);
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    await deleteRole(tester, 'work');
    await deleteRole(tester, 'home');
    expect(chipOrder(tester), ['rest', 'play']);

    await addRole(tester, 'study');

    expect(chipOrder(tester), ['rest', 'play', 'study']);
  });

  testWidgets('a role added right after a move still goes last', (
    tester,
  ) async {
    // `Move right` renumbers the level, so the next add has to read the fresh
    // numbering rather than the one it was seeded with.
    final (_, vm) = await seeded([
      node('work', priority: Priority.critical, position: 0),
      node('home', priority: Priority.low, position: 5),
      node('play', priority: Priority.low, position: 9),
    ]);
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    await openMenu(tester, 'home');
    await tapMenuItem(tester, 'Move right');
    expect(chipOrder(tester), ['work', 'play', 'home']);

    await addRole(tester, 'study');

    expect(chipOrder(tester), ['work', 'play', 'home', 'study']);
    expect(activeChip(tester), 'work', reason: 'adding never switches role');
    expect(vm.tree.nodeById(vm.rolesInChipOrder.last.id)!.priority, Priority.low);
  });
}
