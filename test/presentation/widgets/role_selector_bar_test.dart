import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/priority_picker_widget.dart';
import 'package:priority_lists/presentation/widgets/role_selector_bar.dart';
import 'package:provider/provider.dart';

/// The chip bar is one chip per top-level node of the tree, the red one being
/// the active role. Everything the user can do to a role lives here: switching
/// by tapping, and renaming / recolouring / reordering / deleting from the
/// chip's own menu.

PriorityNode role(
  String id, {
  Priority priority = Priority.medium,
  int position = 0,
  String description = '',
  ColorPreset? color,
  String? parent,
}) {
  final created = DateTime(2026, 1, 1).add(Duration(minutes: position));
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    description: description,
    priority: priority,
    position: position,
    colorPreset: color,
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

/// Three roles in chip order, the first of them active.
Future<(InMemoryPriorityNodeRepository, NodeTreeViewModel)> seededRoles() =>
    seeded([
      role('work', priority: Priority.critical),
      role('home', priority: Priority.high, position: 1),
      role('rest', priority: Priority.low, position: 2),
    ]);

Widget wrap(NodeTreeViewModel vm) {
  return MaterialApp(
    home: ChangeNotifierProvider<NodeTreeViewModel>.value(
      value: vm,
      child: const Scaffold(
        body: Column(children: [RoleSelectorBar()]),
      ),
    ),
  );
}

Finder chipOf(String title) => find.widgetWithText(ChoiceChip, title);

/// The chips as painted, left to right.
List<String> chipOrder(WidgetTester tester) => tester
    .widgetList<ChoiceChip>(find.byType(ChoiceChip))
    .map((chip) => ((chip.label as Text).data)!)
    .toList();

String activeChip(WidgetTester tester) {
  final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
  final active = chips.where((chip) => chip.selected);
  expect(active, hasLength(1), reason: 'exactly one chip is ever active');
  return ((active.first.label as Text).data)!;
}

/// Opens a role's menu the way a long-press does, from anywhere in the row.
Future<void> openMenu(WidgetTester tester, String title) async {
  await tester.longPress(chipOf(title));
  await tester.pumpAndSettle();
}

Future<void> tapMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one chip per role, in chip order, the red one active', (
    tester,
  ) async {
    final (_, vm) = await seededRoles();
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    expect(chipOrder(tester), ['work', 'home', 'rest']);
    expect(activeChip(tester), 'work');
    // The trailing chip that creates a role is not one.
    expect(find.widgetWithText(ActionChip, '+'), findsOneWidget);
  });

  testWidgets('nodes below the top level are not roles', (tester) async {
    final (_, vm) = await seeded([
      role('work', priority: Priority.critical),
      role('a task', parent: 'work', priority: Priority.critical),
    ]);
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    expect(chipOrder(tester), ['work']);
  });

  testWidgets('a role with a colour wears it on its chip', (tester) async {
    final (_, vm) = await seeded([
      role('work', priority: Priority.critical, color: ColorPreset.teal),
      role('home', priority: Priority.high, position: 1),
    ]);
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    final chip = tester.widget<ChoiceChip>(chipOf('work'));
    expect(chip.selectedColor, Color(ColorPreset.teal.colorValue));
  });

  testWidgets('tapping another chip makes that role the active one', (
    tester,
  ) async {
    final (repository, vm) = await seededRoles();
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    await tester.tap(chipOf('rest'));
    await tester.pumpAndSettle();

    expect(activeChip(tester), 'rest');
    expect(vm.tree.nodeById('work')!.priority, Priority.high);
    final stored = {
      for (final node in await repository.getAllNodes()) node.id: node,
    };
    expect(stored['rest']!.priority, Priority.critical);
    expect(stored['work']!.priority, Priority.high);
    // Switching does not reshuffle the row.
    expect(chipOrder(tester), ['work', 'home', 'rest']);
  });

  testWidgets('the row keeps its order across repeated switches', (
    tester,
  ) async {
    final (_, vm) = await seededRoles();
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    for (final title in ['rest', 'home', 'work', 'rest']) {
      await tester.tap(chipOf(title));
      await tester.pumpAndSettle();
      expect(chipOrder(tester), ['work', 'home', 'rest']);
      expect(activeChip(tester), title);
    }
  });

  testWidgets('the "+" chip creates a low role without switching to it', (
    tester,
  ) async {
    final (_, vm) = await seededRoles();
    await tester.pumpWidget(wrap(vm));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, '+'));
    await tester.pumpAndSettle();
    // A role's priority is never picked in the form: the chip tap owns it.
    expect(find.byType(PriorityPickerWidget), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'play');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(chipOrder(tester), ['work', 'home', 'rest', 'play']);
    expect(vm.tree.nodeById(vm.rolesInChipOrder.last.id)!.priority,
        Priority.low);
    expect(activeChip(tester), 'work');
  });

  group('the chip menu', () {
    testWidgets('renames a role and sets its colour, priority untouched', (
      tester,
    ) async {
      final (_, vm) = await seededRoles();
      await tester.pumpWidget(wrap(vm));
      await tester.pumpAndSettle();

      await openMenu(tester, 'home');
      await tapMenuItem(tester, 'Rename / change colour');
      expect(find.byType(PriorityPickerWidget), findsNothing);

      await tester.enterText(find.byType(TextFormField).first, 'household');
      await tester.tap(find.text('No colour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ColorPreset.green.label));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final renamed = vm.tree.nodeById('home')!;
      expect(renamed.title, 'household');
      expect(renamed.colorPreset, ColorPreset.green);
      expect(renamed.priority, Priority.high);
      expect(activeChip(tester), 'work');
    });

    testWidgets('opens on a tap on the already active chip', (tester) async {
      final (_, vm) = await seededRoles();
      await tester.pumpWidget(wrap(vm));
      await tester.pumpAndSettle();

      await tester.tap(chipOf('work'));
      await tester.pumpAndSettle();

      expect(find.text('Rename / change colour'), findsOneWidget);
      expect(activeChip(tester), 'work', reason: 'the tap switched nothing');
    });

    testWidgets('moves a role left and right', (tester) async {
      final (_, vm) = await seededRoles();
      await tester.pumpWidget(wrap(vm));
      await tester.pumpAndSettle();

      await openMenu(tester, 'rest');
      await tapMenuItem(tester, 'Move left');
      expect(chipOrder(tester), ['work', 'rest', 'home']);

      await openMenu(tester, 'work');
      await tapMenuItem(tester, 'Move right');
      expect(chipOrder(tester), ['rest', 'work', 'home']);
      // Reordering is not switching: the red one is still the red one.
      expect(activeChip(tester), 'work');
    });

    testWidgets('cannot move the leftmost role further left', (tester) async {
      final (_, vm) = await seededRoles();
      await tester.pumpWidget(wrap(vm));
      await tester.pumpAndSettle();

      await openMenu(tester, 'work');
      await tapMenuItem(tester, 'Move left');

      expect(chipOrder(tester), ['work', 'home', 'rest']);
    });

    testWidgets('deletes a role after confirming, counting its subtree', (
      tester,
    ) async {
      final (_, vm) = await seeded([
        role('work', priority: Priority.critical),
        role('task', parent: 'work', priority: Priority.high),
        role('home', priority: Priority.high, position: 1),
      ]);
      await tester.pumpWidget(wrap(vm));
      await tester.pumpAndSettle();

      await openMenu(tester, 'work');
      await tapMenuItem(tester, 'Delete');
      expect(find.textContaining('and everything inside (1 node)'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(chipOrder(tester), ['home']);
      expect(vm.tree.nodeById('task'), isNull);
      // Deleting the active role hands the red slot to its successor.
      expect(activeChip(tester), 'home');
      expect(vm.tree.nodeById('home')!.priority, Priority.critical);
    });

    testWidgets('cancelling the confirm keeps the role', (tester) async {
      final (_, vm) = await seededRoles();
      await tester.pumpWidget(wrap(vm));
      await tester.pumpAndSettle();

      await openMenu(tester, 'home');
      await tapMenuItem(tester, 'Delete');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(chipOrder(tester), ['work', 'home', 'rest']);
    });

    testWidgets('the last role cannot be deleted', (tester) async {
      final (_, vm) = await seeded([
        role('work', priority: Priority.critical),
      ]);
      await tester.pumpWidget(wrap(vm));
      await tester.pumpAndSettle();

      await openMenu(tester, 'work');
      await tapMenuItem(tester, 'Delete');

      // The item is disabled, so nothing is even asked.
      expect(find.widgetWithText(FilledButton, 'Delete'), findsNothing);
      expect(chipOrder(tester), ['work']);
    });

    testWidgets('deleting an inactive role leaves the red one alone', (
      tester,
    ) async {
      final (_, vm) = await seededRoles();
      await tester.pumpWidget(wrap(vm));
      await tester.pumpAndSettle();

      await openMenu(tester, 'rest');
      await tapMenuItem(tester, 'Delete');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(chipOrder(tester), ['work', 'home']);
      expect(activeChip(tester), 'work');
    });
  });

  group('no roles to show', () {
    testWidgets('a tree with no top-level node renders nothing', (
      tester,
    ) async {
      final vm = NodeTreeViewModel(InMemoryPriorityNodeRepository());
      await tester.pumpWidget(wrap(vm));
      await tester.pumpAndSettle();

      // `load` was never called here, so the default role does not exist yet.
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
    });
  });

  group('keeping the active chip in view', () {
    void useNarrowPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<(InMemoryPriorityNodeRepository, NodeTreeViewModel)> manyRoles() =>
        seeded([
          for (var i = 0; i < 8; i++)
            role(
              'Role number $i',
              priority: i == 7 ? Priority.critical : Priority.low,
              position: i,
            ),
        ]);

    testWidgets('scrolls a trailing active chip into view', (tester) async {
      useNarrowPhone(tester);
      final (_, vm) = await manyRoles();

      await tester.pumpWidget(wrap(vm));
      await tester.pumpAndSettle();

      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final chip = tester.getRect(chipOf('Role number 7'));
      expect(chip.left, greaterThanOrEqualTo(viewport.left));
      expect(chip.right, lessThanOrEqualTo(viewport.right));
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        greaterThan(0),
      );
    });

    testWidgets('a chip tapped in plain sight leaves the row where it is', (
      tester,
    ) async {
      useNarrowPhone(tester);
      // Short labels, so the chip tapped below is wholly on screen: that is
      // the case this is about.
      final (_, vm) = await seeded([
        for (var i = 0; i < 8; i++)
          role(
            'R$i',
            priority: i == 0 ? Priority.critical : Priority.low,
            position: i,
          ),
      ]);
      await tester.pumpWidget(wrap(vm));
      await tester.pumpAndSettle();

      await tester.tap(chipOf('R1'));
      await tester.pumpAndSettle();

      expect(activeChip(tester), 'R1');
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        0,
      );
    });
  });
}
