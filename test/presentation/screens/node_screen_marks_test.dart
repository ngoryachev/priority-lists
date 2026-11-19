import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/node_mark.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';
import 'package:priority_lists/presentation/widgets/role_selector_bar.dart';
import 'package:provider/provider.dart';

/// Marked children (🔥 / 🧊) leave the level's card list and are pinned above
/// it as one compact line each.

PriorityNode node(
  String id, {
  String? parent,
  Priority priority = Priority.high,
  NodeMark? mark,
  int position = 0,
  int createdOffset = 0,
}) {
  final created = DateTime(2026, 1, 1).add(Duration(minutes: createdOffset));
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    priority: priority,
    position: position,
    mark: mark,
    createdAt: created,
    updatedAt: created,
  );
}

const roleId = 'Role';

Future<PriorityNodeRepository> seeded(List<PriorityNode> nodes) async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes([
    node(roleId, priority: Priority.critical),
    for (final n in nodes) n.parentId == null ? n.withParent(roleId) : n,
  ]);
  return repository;
}

Widget app(
  PriorityNodeRepository repository, {
  FilterViewModel? filter,
  NodeTreeViewModel? vm,
}) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        Provider<PriorityNodeRepository>.value(value: repository),
        if (vm == null)
          ChangeNotifierProvider(create: (_) => NodeTreeViewModel(repository))
        else
          ChangeNotifierProvider.value(value: vm),
        if (filter == null)
          ChangeNotifierProvider(create: (_) => FilterViewModel())
        else
          ChangeNotifierProvider.value(value: filter),
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

/// Titles of the cards still in the list, in list order.
List<String> cardOrder(WidgetTester tester) => tester
    .widgetList<PriorityCard>(find.byType(PriorityCard))
    .map((card) => card.title)
    .toList();

/// Titles of the pinned rows, top to bottom.
List<String> pinnedOrder(WidgetTester tester) => tester
    .widgetList<PinnedMarkRow>(find.byType(PinnedMarkRow))
    .map((row) => row.title)
    .toList();

Finder pinnedRow(String title) => find.byWidgetPredicate(
  (widget) => widget is PinnedMarkRow && widget.title == title,
);

/// The mark button on a card, told apart from a pinned row's emoji by its
/// ancestor.
Finder markButtonOn(String card, NodeMark mark) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is PriorityCard && widget.title == card,
  ),
  matching: find.text(mark.emoji),
);

void main() {
  testWidgets('a marked child leaves the list and is pinned above it', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          node('Plain', createdOffset: 1),
          node('Burning', mark: NodeMark.flame, createdOffset: 2),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(cardOrder(tester), ['Plain']);
    expect(pinnedOrder(tester), ['Burning']);
    // Above the list, not inside it.
    expect(
      tester.getCenter(pinnedRow('Burning')).dy,
      lessThan(tester.getCenter(find.byType(PriorityCard)).dy),
    );
    expect(
      find.descendant(
        of: find.byType(ReorderableListView),
        matching: pinnedRow('Burning'),
      ),
      findsNothing,
    );
  });

  testWidgets('🔥 comes before 🧊 and each section keeps the tree order', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          // Deliberately shuffled: the sections are read off the level's own
          // (priority, position, createdAt) order, not off the seed order.
          node(
            'Ice low',
            priority: Priority.low,
            mark: NodeMark.ice,
            createdOffset: 1,
          ),
          node(
            'Flame low',
            priority: Priority.low,
            mark: NodeMark.flame,
            createdOffset: 2,
          ),
          node(
            'Ice red',
            priority: Priority.critical,
            mark: NodeMark.ice,
            createdOffset: 3,
          ),
          node(
            'Flame red',
            priority: Priority.critical,
            mark: NodeMark.flame,
            createdOffset: 4,
          ),
          node('Plain', createdOffset: 5),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(pinnedOrder(tester), [
      'Flame red',
      'Flame low',
      'Ice red',
      'Ice low',
    ]);
    expect(cardOrder(tester), ['Plain']);
  });

  testWidgets('an empty section takes no vertical space at all', (
    tester,
  ) async {
    usePhoneSize(tester);
    final repository = await seeded([
      node('Plain', createdOffset: 1),
      node('Other', createdOffset: 2),
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    double listTop() => tester.getTopLeft(find.byType(ReorderableListView)).dy;

    // Both sections empty: not a widget between the role bar and the list.
    final noRows = listTop();
    expect(find.byType(PinnedMarkRow), findsNothing);

    final vm = tester
        .state<State>(find.byType(NodeScreen))
        .context
        .read<NodeTreeViewModel>();

    // One 🔥 and no 🧊 at all.
    await vm.setMark(vm.tree.nodeById('Plain')!, NodeMark.flame);
    await tester.pumpAndSettle();
    expect(pinnedOrder(tester), ['Plain']);
    final rowHeight = tester.getSize(find.byType(PinnedMarkRow).first).height;
    final oneRow = listTop();
    // The block's own 8dp top padding, and then exactly one row — the empty
    // 🧊 section contributes nothing, not even a header.
    expect(oneRow - noRows, closeTo(rowHeight + 8, 0.01));

    // The 🧊 section opening costs exactly its one row.
    await vm.setMark(vm.tree.nodeById('Other')!, NodeMark.ice);
    await tester.pumpAndSettle();
    expect(pinnedOrder(tester), ['Plain', 'Other']);
    expect(listTop() - oneRow, closeTo(rowHeight, 0.01));
  });

  testWidgets('a level full of marked children scrolls its rows instead of '
      'overflowing', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          for (var i = 0; i < 40; i++)
            node('m$i', mark: NodeMark.flame, createdOffset: i),
          node('Plain', createdOffset: 100),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // The card list still has room; the rows gave way rather than the list.
    expect(cardOrder(tester), ['Plain']);
    final body = tester.getSize(find.byType(NodeScreen)).height;
    final block = tester
        .getSize(find.byType(SingleChildScrollView).first)
        .height;
    expect(block, lessThan(body / 2 + 1));
  });

  testWidgets('a pinned row is emoji and title and nothing else', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          node('Burning', priority: Priority.critical, mark: NodeMark.flame),
          node('Kid', parent: 'Burning', createdOffset: 1),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    final row = pinnedRow('Burning');
    expect(find.descendant(of: row, matching: find.text('🔥')), findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Burning')),
      findsOneWidget,
    );
    final title = tester.widget<Text>(
      find.descendant(of: row, matching: find.text('Burning')),
    );
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);

    // No badge, no 1-4 row, no child count, no actions, no pages.
    expect(
      find.descendant(of: row, matching: find.text(Priority.critical.label)),
      findsNothing,
    );
    for (final p in Priority.values) {
      expect(
        find.descendant(of: row, matching: find.text('${p.value}')),
        findsNothing,
      );
    }
    for (final icon in [
      Icons.subdirectory_arrow_right,
      Icons.edit_outlined,
      Icons.delete_outline,
      Icons.move_to_inbox,
      Icons.arrow_upward,
      Icons.drag_handle,
      Icons.more_vert,
    ]) {
      expect(
        find.descendant(of: row, matching: find.byIcon(icon)),
        findsNothing,
        reason: 'a pinned row must not carry $icon',
      );
    }
    expect(
      find.descendant(of: row, matching: find.byType(PageView)),
      findsNothing,
    );
    // The marked node's own title is not also on a card.
    expect(cardOrder(tester), isEmpty);
  });

  testWidgets('tapping a pinned row\'s title opens that level', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          node('Burning', priority: Priority.critical, mark: NodeMark.flame),
          node('Kid', parent: 'Burning', createdOffset: 1),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: pinnedRow('Burning'), matching: find.text('Burning')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Burning')),
      findsOneWidget,
    );
    expect(cardOrder(tester), ['Kid']);
  });

  testWidgets(
    'tapping the emoji unmarks and the card is back in its old place',
    (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        node('A', priority: Priority.critical, position: 0, createdOffset: 1),
        node('B', priority: Priority.critical, position: 1, createdOffset: 2),
        node('C', priority: Priority.critical, position: 2, createdOffset: 3),
      ]);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();

      await tester.tap(markButtonOn('B', NodeMark.ice));
      await tester.pumpAndSettle();
      expect(pinnedOrder(tester), ['B']);
      expect(cardOrder(tester), ['A', 'C']);

      await tester.tap(
        find.descendant(of: pinnedRow('B'), matching: find.text('🧊')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PinnedMarkRow), findsNothing);
      expect(cardOrder(tester), ['A', 'B', 'C']);
      // Its priority and position are the ones it had before the mark.
      final stored = {for (final n in await repository.getAllNodes()) n.id: n};
      expect(stored['B']!.mark, isNull);
      expect(stored['B']!.priority, Priority.critical);
      expect(stored['B']!.position, 1);
    },
  );

  testWidgets(
    'the card\'s buttons mark the node and swap one mark for the other',
    (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([node('A'), node('B', createdOffset: 1)]);
      await tester.pumpWidget(app(repository));
      await tester.pumpAndSettle();

      await tester.tap(markButtonOn('A', NodeMark.flame));
      await tester.pumpAndSettle();
      expect(pinnedOrder(tester), ['A']);
      expect(cardOrder(tester), ['B']);

      // 🔥 → 🧊 from the row: unmark, then mark the other way round.
      await tester.tap(
        find.descendant(of: pinnedRow('A'), matching: find.text('🔥')),
      );
      await tester.pumpAndSettle();
      await tester.tap(markButtonOn('A', NodeMark.ice));
      await tester.pumpAndSettle();

      expect(pinnedOrder(tester), ['A']);
      expect(
        find.descendant(of: pinnedRow('A'), matching: find.text('🧊')),
        findsOneWidget,
      );
      final stored = {for (final n in await repository.getAllNodes()) n.id: n};
      expect(stored['A']!.mark, NodeMark.ice);
    },
  );

  testWidgets('editing a marked node through the form keeps its mark', (
    tester,
  ) async {
    usePhoneSize(tester);
    final repository = await seeded([
      node('Burning', priority: Priority.critical, mark: NodeMark.flame),
      node('Plain', createdOffset: 1),
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    // A marked node has no card, so Edit is reached from its own level.
    await tester.tap(
      find.descendant(of: pinnedRow('Burning'), matching: find.text('Burning')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.edit_outlined),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // The form knows nothing about marks, and `copyWith` without `clearMark`
    // must leave it where it was.
    final stored = {for (final n in await repository.getAllNodes()) n.id: n};
    expect(stored['Burning']!.title, 'Renamed');
    expect(stored['Burning']!.mark, NodeMark.flame);
    expect(pinnedOrder(tester), ['Renamed']);
  });

  testWidgets('a level whose only children are marked shows no placeholder', (
    tester,
  ) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(
        await seeded([
          node('Burning', mark: NodeMark.flame),
          node('Frozen', mark: NodeMark.ice, createdOffset: 1),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(pinnedOrder(tester), ['Burning', 'Frozen']);
    expect(find.textContaining('Nothing here yet'), findsNothing);
    expect(find.textContaining('hidden by the priority filter'), findsNothing);
  });

  testWidgets('the priority filter hides cards but never a pinned row', (
    tester,
  ) async {
    usePhoneSize(tester);
    final filter = FilterViewModel();
    await tester.pumpWidget(
      app(
        await seeded([
          node('Frozen low', priority: Priority.low, mark: NodeMark.ice),
          node('Plain low', priority: Priority.low, createdOffset: 1),
          node('Plain red', priority: Priority.critical, createdOffset: 2),
        ]),
        filter: filter,
      ),
    );
    await tester.pumpAndSettle();

    expect(cardOrder(tester), ['Plain red', 'Plain low']);
    expect(pinnedOrder(tester), ['Frozen low']);

    filter.setLevel(1); // only critical stays visible
    await tester.pumpAndSettle();

    expect(cardOrder(tester), ['Plain red']);
    expect(
      pinnedOrder(tester),
      ['Frozen low'],
      reason: 'a pinned row is the user saying "this one, now"',
    );

    // Even when every card is filtered away: the rows are still there, so the
    // placeholder must not appear.
    filter.setLevel(1);
    await tester.pumpAndSettle();
    expect(find.textContaining('hidden by the priority filter'), findsNothing);
  });

  testWidgets(
    'a filter that hides every card leaves the rows and no placeholder',
    (tester) async {
      usePhoneSize(tester);
      final filter = FilterViewModel();
      await tester.pumpWidget(
        app(
          await seeded([
            node('Frozen low', priority: Priority.low, mark: NodeMark.ice),
            node('Plain low', priority: Priority.low, createdOffset: 1),
          ]),
          filter: filter,
        ),
      );
      await tester.pumpAndSettle();

      filter.setLevel(1);
      await tester.pumpAndSettle();

      expect(cardOrder(tester), isEmpty);
      expect(pinnedOrder(tester), ['Frozen low']);
      expect(
        find.textContaining('hidden by the priority filter'),
        findsNothing,
      );
    },
  );

  testWidgets('dragging the cards that are left reorders the right nodes', (
    tester,
  ) async {
    usePhoneSize(tester);
    final repository = await seeded([
      node('First', priority: Priority.critical, position: 0, createdOffset: 1),
      node(
        'Pinned',
        priority: Priority.critical,
        position: 1,
        mark: NodeMark.flame,
        createdOffset: 2,
      ),
      node(
        'Second',
        priority: Priority.critical,
        position: 2,
        createdOffset: 3,
      ),
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    expect(cardOrder(tester), ['First', 'Second']);

    // The second card's handle — index 1 of the *cards*, which is what the
    // reorder indices have to be counted in.
    final handle = find.byIcon(Icons.drag_handle).at(1);
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(cardOrder(tester), ['Second', 'First']);
    // The marked sibling was woven back into its place, not dragged along.
    final stored = {for (final n in await repository.getAllNodes()) n.id: n};
    expect(stored['Pinned']!.mark, NodeMark.flame);
    final level =
        (await repository.getAllNodes())
            .where((n) => n.parentId == roleId)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    expect(level.map((n) => n.id), ['Second', 'First', 'Pinned']);
  });

  testWidgets('a card\'s mark buttons stay tappable on the tightest phone', (
    tester,
  ) async {
    // 320x568 is the narrowest screen the app is tested on (iPhone SE, see
    // node_screen_mobile_test). The drag grip is centred in the band left of
    // PriorityCard's level-row reserve, and that reserve still pays only for
    // the four 1-4 buttons — so on a card this narrow the grip's 44dp target
    // drifts over the mark buttons that now sit left of them.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = await seeded([node('Plain', createdOffset: 1)]);
    final vm = NodeTreeViewModel(repository);
    await tester.pumpWidget(app(repository, vm: vm));
    await tester.pumpAndSettle();

    for (final mark in NodeMark.values) {
      expect(
        markButtonOn('Plain', mark).hitTestable(),
        findsOneWidget,
        reason: '${mark.emoji} is covered by the drag grip at 320dp',
      );
    }

    await tester.tap(markButtonOn('Plain', NodeMark.flame));
    await tester.pumpAndSettle();
    expect(vm.tree.nodeById('Plain')!.mark, NodeMark.flame);

    // Marking it took its card away — it is a pinned row now — so the 🧊
    // button is reached by unmarking from that row first.
    await tester.tap(
      find.descendant(
        of: pinnedRow('Plain'),
        matching: find.text(NodeMark.flame.emoji),
      ),
    );
    await tester.pumpAndSettle();
    expect(vm.tree.nodeById('Plain')!.mark, isNull);

    await tester.tap(markButtonOn('Plain', NodeMark.ice));
    await tester.pumpAndSettle();
    expect(vm.tree.nodeById('Plain')!.mark, NodeMark.ice);
  });

  testWidgets('the mark buttons do not push the grip into the card\'s '
      'back-gesture gutter', (tester) async {
    // The other end of the same band: widening the level-row reserve for the
    // two mark buttons moves the grip's 44dp target left, and on a narrow
    // card it lands on the leftmost 24dp of the card — the strip the card
    // keeps clear of its own gestures so the platform back swipe and a plain
    // tap still work there. 320x568 is the narrowest the app is tested on.
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A grandchild makes the card swipeable, which is what puts the gutter
    // there in the first place.
    final repository = await seeded([
      node('Parent', createdOffset: 1),
      node('Kid', parent: 'Parent', createdOffset: 2),
    ]);
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();

    final card = find.byWidgetPredicate(
      (widget) => widget is PriorityCard && widget.title == 'Parent',
    );
    // The Stack inside the Card is the card's content box, so the gutter is
    // its leftmost 24dp (PriorityCard._backGestureGutter).
    final content = tester.getRect(
      find.descendant(of: card, matching: find.byType(Stack)).first,
    );
    final gutter = Rect.fromLTRB(
      content.left,
      content.top,
      content.left + 24,
      content.bottom,
    );
    final grip = tester.getRect(
      find.descendant(
        of: card,
        matching: find.byType(ReorderableDragStartListener),
      ),
    );
    expect(
      grip.overlaps(gutter),
      isFalse,
      reason: 'the grip target $grip reaches into the gutter $gutter',
    );

    // And the behaviour that band protects: a tap in the gutter opens the
    // node instead of being eaten by the grip.
    await tester.tapAt(Offset(gutter.left + 6, grip.center.dy));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Parent')),
      findsOneWidget,
    );
  });

  testWidgets('roles get no mark buttons', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(
      app(await seeded([node('Child', createdOffset: 1)])),
    );
    await tester.pumpAndSettle();

    final bar = find.byType(RoleSelectorBar);
    expect(bar, findsOneWidget);
    for (final mark in NodeMark.values) {
      expect(
        find.descendant(of: bar, matching: find.text(mark.emoji)),
        findsNothing,
        reason: 'the chip bar is unchanged',
      );
    }
    // The role's own children do carry them.
    expect(markButtonOn('Child', NodeMark.flame), findsOneWidget);
  });

  group('while a node is being moved', () {
    Future<void> pickUp(WidgetTester tester, String title) async {
      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget is PriorityCard && widget.title == title,
          ),
          matching: find.byIcon(Icons.move_to_inbox),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'tapping a pinned row\'s title puts the moving node inside it',
      (tester) async {
        usePhoneSize(tester);
        final repository = await seeded([
          node('Burning', priority: Priority.critical, mark: NodeMark.flame),
          node('Mover', priority: Priority.high, createdOffset: 1),
        ]);
        await tester.pumpWidget(app(repository));
        await tester.pumpAndSettle();

        await pickUp(tester, 'Mover');
        expect(find.textContaining('Moving "Mover"'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: pinnedRow('Burning'),
            matching: find.text('Burning'),
          ),
        );
        await tester.pumpAndSettle();

        final stored = {
          for (final n in await repository.getAllNodes()) n.id: n,
        };
        expect(stored['Mover']!.parentId, 'Burning');
        // The move is over and the row is still pinned where it was.
        expect(find.textContaining('Moving "Mover"'), findsNothing);
        expect(pinnedOrder(tester), ['Burning']);
      },
    );

    testWidgets('a marked node cannot be picked up from its row', (
      tester,
    ) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        app(
          await seeded([
            node('Burning', priority: Priority.critical, mark: NodeMark.flame),
            node('Plain', priority: Priority.high, createdOffset: 1),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // One "move into" on the level, on the one card that is left.
      expect(find.byIcon(Icons.move_to_inbox), findsOneWidget);
      expect(
        find.descendant(
          of: pinnedRow('Burning'),
          matching: find.byIcon(Icons.move_to_inbox),
        ),
        findsNothing,
      );
    });
  });
}
