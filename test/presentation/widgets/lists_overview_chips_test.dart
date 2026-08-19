import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_list_repository.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_item.dart';
import 'package:priority_lists/domain/models/priority_list.dart';
import 'package:priority_lists/domain/repositories/priority_list_repository.dart';
import 'package:priority_lists/presentation/screens/lists_overview_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/lists_overview_view_model.dart';
import 'package:priority_lists/presentation/widgets/bubble_view/bubble_widget.dart';
import 'package:provider/provider.dart';

PriorityItem _item(String title, Priority priority) {
  final now = DateTime(2026, 1, 1);
  return PriorityItem(
    id: title,
    title: title,
    priority: priority,
    createdAt: now,
    updatedAt: now,
  );
}

PriorityList _list(String name, Priority priority, List<PriorityItem> items) {
  final now = DateTime(2026, 1, 1);
  return PriorityList(
    id: name,
    name: name,
    colorPreset: ColorPreset.red,
    priority: priority,
    items: items,
    createdAt: now,
    updatedAt: now,
  );
}

Future<PriorityListRepository> _seededRepository() async {
  final repo = InMemoryPriorityListRepository();
  await repo.saveList(
    _list('Work', Priority.critical, [
      _item(
        'Very long item title that needs truncating badly',
        Priority.critical,
      ),
      _item('Fix bug', Priority.high),
      _item('Chore', Priority.low),
      _item('Docs', Priority.medium),
      _item('Fifth', Priority.critical),
      _item('Sixth', Priority.critical),
      _item('Seventh', Priority.critical),
    ]),
  );
  await repo.saveList(
    _list('Home', Priority.high, [_item('Buy milk', Priority.medium)]),
  );
  await repo.saveList(
    _list('Someday', Priority.medium, [_item('Learn piano', Priority.low)]),
  );
  await repo.saveList(_list('Empty red', Priority.critical, []));
  await repo.saveList(
    _list('Backlog', Priority.low, [_item('Later thing', Priority.low)]),
  );
  return repo;
}

Widget _wrap(PriorityListRepository repo) {
  return MultiProvider(
    providers: [
      Provider<PriorityListRepository>.value(value: repo),
      ChangeNotifierProvider(create: (_) => ListsOverviewViewModel(repo)),
      ChangeNotifierProvider(create: (_) => FilterViewModel()),
    ],
    child: const MaterialApp(home: ListsOverviewScreen()),
  );
}

void main() {
  testWidgets('overview bubble view renders chips without exceptions', (
    tester,
  ) async {
    final repo = await _seededRepository();
    await tester.pumpWidget(_wrap(repo));
    await tester.pump(); // loadLists microtask

    // The overview opens as a list, so switch to the bubble canvas first.
    await tester.tap(find.byIcon(Icons.bubble_chart));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100)); // physics ticks

    expect(tester.takeException(), isNull);
    // Critical bubble (7 items, 4 chips max) collapses the rest into "+3".
    expect(find.text('+3'), findsOneWidget);
    // High bubble shows its single item chip.
    expect(find.text('Buy milk'), findsOneWidget);
    // Medium bubbles show their items too.
    expect(find.text('Learn piano'), findsOneWidget);
    // Low bubbles stay plain — too small to carry chips.
    expect(find.text('Later thing'), findsNothing);
  });

  testWidgets('overview list view renders chips without exceptions', (
    tester,
  ) async {
    // A medium tile is 20% of the screen height, so it only clears the compact
    // threshold on a phone-sized screen — the default 800x600 test view is too
    // short for it.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = await _seededRepository();
    await tester.pumpWidget(_wrap(repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Fix bug'), findsWidgets);

    // Critical + high tiles alone fill the viewport, so the medium and low
    // tiles below have to be scrolled into view before they are built.
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Medium tiles show their items as chips as well.
    expect(find.textContaining('Learn piano'), findsWidgets);
    // Low tiles are too short for chips (or even a subtitle) — name only.
    expect(find.text('Backlog'), findsOneWidget);
    expect(find.textContaining('Later thing'), findsNothing);
    // Critical list without visible items falls back to the plain subtitle.
    expect(find.text('0 items'), findsWidgets);
  });

  testWidgets('chips honor the priority filter', (tester) async {
    final repo = await _seededRepository();
    final filter = FilterViewModel();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PriorityListRepository>.value(value: repo),
          ChangeNotifierProvider(create: (_) => ListsOverviewViewModel(repo)),
          ChangeNotifierProvider.value(value: filter),
        ],
        child: const MaterialApp(home: ListsOverviewScreen()),
      ),
    );
    await tester.pump();
    filter.setLevel(1); // only critical visible
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    // High-priority item is filtered out of the chips.
    expect(find.textContaining('Fix bug'), findsNothing);
  });

  testWidgets('BubbleWidget with chips survives tiny diameters', (
    tester,
  ) async {
    // Chips appear on critical/high/medium bubbles, whose real-world diameter
    // stays above 110 (see BubblePhysics.radiusForPriority).
    for (final diameter in [90.0, 120.0, 180.0, 260.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BubbleWidget(
              name: 'List',
              color: Colors.red,
              diameter: diameter,
              itemCountText: '3 items',
              chipLabels: const ['One', 'A very long chip label', 'Three'],
              onTap: () {},
              onPriorityUp: () {},
              onPriorityDown: () {},
              currentPriority: Priority.critical,
              onSetPriority: (_) {},
            ),
          ),
        ),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'diameter $diameter threw',
      );
    }
  });
}
