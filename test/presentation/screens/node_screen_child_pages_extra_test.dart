import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/card_page_view_model.dart';
import 'package:priority_lists/data/repositories/in_memory_last_node_repository.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/last_node_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';
import 'package:provider/provider.dart';

/// The corners of the card's second axis the happy-path tests do not reach:
/// the grip's touch target competing with the page drag, the screen built
/// without the page record at all, and writes that move the shown child out
/// from under the card.

PriorityNode node(
  String id, {
  String? parent,
  Priority priority = Priority.high,
  int createdOffset = 0,
}) {
  final created = DateTime(2026, 1, 1).add(Duration(minutes: createdOffset));
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    description: '',
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

Widget app(
  PriorityNodeRepository repository, {
  CardPageViewModel? cardPages,
  FilterViewModel? filter,
}) {
  final tree = MaterialApp(
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
  if (cardPages == null) return tree;
  return Provider<CardPageViewModel>.value(value: cardPages, child: tree);
}

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder cardOf(String title) => find.byWidgetPredicate(
  (widget) => widget is PriorityCard && widget.title == title,
);

String shownTitle(WidgetTester tester, String owner) {
  final finder = find.descendant(
    of: cardOf(owner),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.style?.fontWeight == FontWeight.bold &&
          (widget.style?.fontSize ?? 0) >= 16,
    ),
  );
  return tester.widget<Text>(finder).data ?? '';
}

Future<void> swipe(WidgetTester tester, String owner, {bool back = false}) async {
  await tester.drag(cardOf(owner), Offset(back ? 300 : -300, 0));
  await tester.pumpAndSettle();
}

List<String> order(WidgetTester tester) => tester
    .widgetList<PriorityCard>(find.byType(PriorityCard))
    .map((card) => card.title)
    .toList();

Future<void> dragVerticallyFrom(WidgetTester tester, Offset start) async {
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.moveBy(const Offset(0, -20));
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('the grip as a touch target', () {
    /// Two parents, each with one child, so both cards swipe and a reorder is
    /// visible in the card order.
    Future<PriorityNodeRepository> level() => seeded([
      node('P1', priority: Priority.critical),
      node('a1', parent: 'P1', createdOffset: 1),
      node('P2', priority: Priority.critical, createdOffset: 2),
      node('b1', parent: 'P2', createdOffset: 3),
    ]);

    testWidgets('the whole 44x44 grip starts a reorder, not a page turn',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(app(await level(), cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();
      expect(order(tester), ['P1', 'P2']);

      // A thumb lands anywhere on the 44x44 target, not only on the glyph.
      final target = tester.getRect(
        find.descendant(
          of: cardOf('P2'),
          matching: find.byType(ReorderableDragStartListener),
        ),
      );
      expect(target.width, greaterThanOrEqualTo(44));
      await dragVerticallyFrom(
        tester,
        Offset(target.left + 4, target.top + 4),
      );

      expect(
        order(tester),
        ['P2', 'P1'],
        reason: 'a drag from the grip target reorders the level',
      );
    });

    testWidgets('a sideways drag on the grip does not turn the page',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(app(await level(), cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      final target = tester.getRect(
        find.descendant(
          of: cardOf('P2'),
          matching: find.byType(ReorderableDragStartListener),
        ),
      );
      await tester.dragFrom(
        Offset(target.left + 4, target.center.dy),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();

      expect(
        shownTitle(tester, 'P2'),
        'P2',
        reason: 'the grip owns the gesture; the page must stay put',
      );
      expect(order(tester), ['P1', 'P2']);
    });

    testWidgets('the dots do not cost the card a strip of swipeable width',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(app(await level(), cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      final dots = tester.getCenter(
        find.descendant(
          of: cardOf('P2'),
          matching: find.byIcon(Icons.more_vert),
        ),
      );
      await tester.dragFrom(dots, const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(shownTitle(tester, 'P2'), 'b1');
    });

    testWidgets('a tap in the grip band but off the grip still opens the node',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(app(await level(), cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      final card = tester.getRect(cardOf('P2'));
      // Bottom-left of the card: inside the grip's band, left of its target
      // and right of the back-gesture gutter.
      await tester.tapAt(Offset(card.left + 60, card.bottom - 14));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('P2')),
        findsOneWidget,
      );
    });

    testWidgets('the grip band on a child page still opens that child',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(app(await level(), cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      await swipe(tester, 'P2');
      expect(shownTitle(tester, 'P2'), 'b1');

      final card = tester.getRect(cardOf('P2'));
      await tester.tapAt(Offset(card.left + 60, card.bottom - 14));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('b1')),
        findsOneWidget,
      );
    });
  });

  group('without the page record', () {
    testWidgets('a screen built with no CardPageViewModel still swipes',
        (tester) async {
      usePhoneSize(tester);
      final filter = FilterViewModel();
      final repository = await seeded([
        node('Parent', priority: Priority.critical),
        node('c1', parent: 'Parent', createdOffset: 1),
        node('c2', parent: 'Parent', createdOffset: 2),
      ]);
      await tester.pumpWidget(app(repository, filter: filter));
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c2');

      // A rebuild of the level must not drag the card back to page 0 just
      // because there is nothing remembering the page.
      filter.setLevel(3);
      await tester.pumpAndSettle();
      expect(shownTitle(tester, 'Parent'), 'c2');
    });
  });

  group('writes that move the shown child', () {
    testWidgets('the critical slot is still exclusive from a child page',
        (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        node('Parent', priority: Priority.critical),
        node('red', parent: 'Parent', priority: Priority.critical,
            createdOffset: 1),
        node('other', parent: 'Parent', priority: Priority.low,
            createdOffset: 2),
      ]);
      await tester.pumpWidget(app(repository, cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      // Page 1 is "red" (critical sorts first), page 2 is "other".
      await swipe(tester, 'Parent');
      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'other');
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('2/2')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: cardOf('Parent'), matching: find.text('1')),
      );
      await tester.pumpAndSettle();

      final stored = await repository.getAllNodes();
      expect(stored.firstWhere((n) => n.id == 'other').priority,
          Priority.critical);
      expect(
        stored.firstWhere((n) => n.id == 'red').priority,
        isNot(Priority.critical),
        reason: 'the red slot stays exclusive, as on a normal card',
      );
      // The card follows the child it was on, which now sorts first.
      expect(shownTitle(tester, 'Parent'), 'other');
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('1/2')),
        findsOneWidget,
      );
    });

    testWidgets('a write that filters the shown child out falls back to page 0',
        (tester) async {
      usePhoneSize(tester);
      final filter = FilterViewModel();
      final repository = await seeded([
        node('Parent', priority: Priority.critical),
        node('kept', parent: 'Parent', priority: Priority.high),
        node('demoted', parent: 'Parent', priority: Priority.high,
            createdOffset: 1),
      ]);
      await tester.pumpWidget(
        app(repository, cardPages: CardPageViewModel(), filter: filter),
      );
      await tester.pumpAndSettle();

      filter.setLevel(2); // critical + high
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'demoted');

      // "4" is low, which this filter hides: the page the card is on goes
      // away under it.
      await tester.tap(
        find.descendant(of: cardOf('Parent'), matching: find.text('4')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(shownTitle(tester, 'Parent'), 'Parent');
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('1/1')),
        findsNothing,
        reason: 'page 0 carries no counter',
      );
    });

    testWidgets('a new child appearing does not move the card off its page',
        (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        node('Parent', priority: Priority.critical),
        node('c1', parent: 'Parent', priority: Priority.low, createdOffset: 1),
        node('c2', parent: 'Parent', priority: Priority.low, createdOffset: 2),
      ]);
      await tester.pumpWidget(app(repository, cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c2');

      final vm = Provider.of<NodeTreeViewModel>(
        tester.element(find.byType(NodeScreen).first),
        listen: false,
      );
      // A high child sorts ahead of both, so every page index shifts.
      await vm.addChild(
        parentId: 'Parent',
        title: 'fresh',
        priority: Priority.high,
      );
      await tester.pumpAndSettle();

      expect(shownTitle(tester, 'Parent'), 'c2');
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('3/3')),
        findsOneWidget,
      );
    });

    testWidgets('hiding a sibling shrinks the counter without moving the card',
        (tester) async {
      usePhoneSize(tester);
      final filter = FilterViewModel();
      // Sort order is priority first, so the pages read c1, c3, then the low
      // c2 last.
      final repository = await seeded([
        node('Parent', priority: Priority.critical),
        node('c1', parent: 'Parent', priority: Priority.high, createdOffset: 1),
        node('c2', parent: 'Parent', priority: Priority.low, createdOffset: 2),
        node('c3', parent: 'Parent', priority: Priority.high, createdOffset: 3),
      ]);
      await tester.pumpWidget(
        app(repository, cardPages: CardPageViewModel(), filter: filter),
      );
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c3');
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('2/3')),
        findsOneWidget,
      );

      filter.setLevel(2); // hides the low c2
      await tester.pumpAndSettle();

      expect(shownTitle(tester, 'Parent'), 'c3');
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('2/2')),
        findsOneWidget,
        reason: 'N counts the visible children only',
      );
    });
  });

  group('deeper levels and the bubble view', () {
    Future<PriorityNodeRepository> nested() => seeded([
      node('Parent', priority: Priority.critical),
      node('c1', parent: 'Parent', createdOffset: 1),
      node('g1', parent: 'c1', createdOffset: 2),
      node('g2', parent: 'c1', createdOffset: 3),
      node('c2', parent: 'Parent', createdOffset: 4),
    ]);

    testWidgets('a pushed level swipes and remembers its pages too',
        (tester) async {
      usePhoneSize(tester);
      final cardPages = CardPageViewModel();
      await tester.pumpWidget(app(await nested(), cardPages: cardPages));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Parent'));
      await tester.pumpAndSettle();

      await swipe(tester, 'c1');
      await swipe(tester, 'c1');
      expect(shownTitle(tester, 'c1'), 'g2');
      expect(cardPages.childFor('c1'), 'g2');

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parent'));
      await tester.pumpAndSettle();

      expect(
        shownTitle(tester, 'c1'),
        'g2',
        reason: 'NodeScreen.route has to carry the record into the push',
      );
    });

    testWidgets('the bubble view has no pages, and the list keeps its own',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(app(await nested(), cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c1');

      // The bubble canvas animates forever, so it is pumped rather than
      // settled, like the other bubble-view tests.
      await tester.tap(find.byIcon(Icons.bubble_chart));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PageView), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.view_list));
      await tester.pumpAndSettle();
      expect(shownTitle(tester, 'Parent'), 'c1');
    });

    testWidgets('a tap on a child page records that level for the next launch',
        (tester) async {
      usePhoneSize(tester);
      final store = InMemoryLastNodeRepository();
      final lastNodes = LastNodeViewModel(
        repository: store,
        currentUserId: () => 'user-1',
      );
      await tester.pumpWidget(
        Provider<LastNodeViewModel>.value(
          value: lastNodes,
          child: app(await nested(), cardPages: CardPageViewModel()),
        ),
      );
      await tester.pumpAndSettle();

      // Page 1 of the Parent card is c1; opening it must go through the same
      // path as a tap on a card, record included.
      await swipe(tester, 'Parent');
      await tester.tap(
        find.descendant(of: cardOf('Parent'), matching: find.text('c1')),
      );
      await tester.pumpAndSettle();
      await lastNodes.idle;

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('c1')),
        findsOneWidget,
      );
      expect((await store.load())?.nodeId, 'c1');
    });

    testWidgets('a phone-sized level with every priority never overflows',
        (tester) async {
      usePhoneSize(tester);
      final nodes = <PriorityNode>[];
      var offset = 0;
      for (final p in Priority.values) {
        nodes.add(node('owner ${p.label}', priority: p, createdOffset: offset++));
        for (var i = 0; i < 3; i++) {
          nodes.add(
            node(
              'kid $i of ${p.label}',
              parent: 'owner ${p.label}',
              priority: p,
              createdOffset: offset++,
            ),
          );
        }
      }
      await tester.pumpWidget(app(await seeded(nodes),
          cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final p in Priority.values) {
        final owner = 'owner ${p.label}';
        if (cardOf(owner).evaluate().isEmpty) continue;
        await tester.ensureVisible(cardOf(owner));
        await tester.pumpAndSettle();
        await swipe(tester, owner);
        expect(tester.takeException(), isNull, reason: owner);
        expect(shownTitle(tester, owner), 'kid 0 of ${p.label}');
        // The grip and the 1-4 row stay reachable on the child page.
        expect(
          find
              .descendant(
                of: cardOf(owner),
                matching: find.byIcon(Icons.drag_handle),
              )
              .hitTestable(),
          findsOneWidget,
          reason: owner,
        );
        for (final level in ['1', '2', '3', '4']) {
          expect(
            find
                .descendant(of: cardOf(owner), matching: find.text(level))
                .hitTestable(),
            findsOneWidget,
            reason: '$owner / $level',
          );
        }
      }
    });
  });

  group('the page controller over its lifetime', () {
    // Wider than the 360dp phone used above: at 360dp the move banner's own
    // buttons overflow its row, which is a pre-existing defect of that banner
    // and would mask what these cases are about.
    void useRoomyPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<PriorityNodeRepository> level() => seeded([
      node('Parent', priority: Priority.critical),
      node('c1', parent: 'Parent', createdOffset: 1),
      node('c2', parent: 'Parent', createdOffset: 2),
      node('Lonely', createdOffset: 3),
    ]);

    testWidgets('move mode toggled repeatedly leaves no stale controller',
        (tester) async {
      useRoomyPhone(tester);
      final cardPages = CardPageViewModel();
      await tester.pumpWidget(app(await level(), cardPages: cardPages));
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c1');

      for (var i = 0; i < 3; i++) {
        await tester.tap(
          find.descendant(
            of: cardOf('Lonely'),
            matching: find.byIcon(Icons.move_to_inbox),
          ),
        );
        await tester.pumpAndSettle();
        expect(shownTitle(tester, 'Parent'), 'Parent');

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(shownTitle(tester, 'Parent'), 'c1', reason: 'round $i');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('tearing the tree down mid-transition disposes cleanly',
        (tester) async {
      useRoomyPhone(tester);
      await tester.pumpWidget(app(await level(), cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      // Into move mode, then away before the frame's callbacks have run: the
      // controller the card dropped is still waiting to be disposed.
      await tester.tap(
        find.descendant(
          of: cardOf('Lonely'),
          matching: find.byIcon(Icons.move_to_inbox),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('deleting the owner card while it shows a child is clean',
        (tester) async {
      useRoomyPhone(tester);
      await tester.pumpWidget(app(await level(), cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c1');

      final vm = Provider.of<NodeTreeViewModel>(
        tester.element(find.byType(NodeScreen).first),
        listen: false,
      );
      await vm.deleteNode('Parent');
      await tester.pumpAndSettle();

      expect(cardOf('Parent'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('swiping writes nothing', (tester) async {
      useRoomyPhone(tester);
      final repository = await seeded([
        node('Parent', priority: Priority.critical),
        node('c1', parent: 'Parent', createdOffset: 1),
        node('c2', parent: 'Parent', createdOffset: 2),
      ]);
      await tester.pumpWidget(app(repository, cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      String snapshot(List<PriorityNode> nodes) => (nodes
            ..sort((a, b) => a.id.compareTo(b.id)))
          .map((n) => '${n.id}|${n.priority}|${n.position}|${n.updatedAt}')
          .join(',');
      final before = snapshot(await repository.getAllNodes());

      await swipe(tester, 'Parent');
      await swipe(tester, 'Parent');
      await swipe(tester, 'Parent', back: true);
      await swipe(tester, 'Parent', back: true);
      expect(shownTitle(tester, 'Parent'), 'Parent');

      expect(snapshot(await repository.getAllNodes()), before);
    });

    testWidgets('a rebuild during an in-flight swipe does not yank the thumb',
        (tester) async {
      useRoomyPhone(tester);
      final filter = FilterViewModel();
      await tester.pumpWidget(
        app(await level(), cardPages: CardPageViewModel(), filter: filter),
      );
      await tester.pumpAndSettle();

      // Start a swipe and stop halfway, then rebuild the level under it.
      final gesture = await tester.startGesture(
        tester.getCenter(cardOf('Parent')),
      );
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 16));
      filter.setLevel(3);
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        shownTitle(tester, 'Parent'),
        'c1',
        reason: 'the swipe the user started still settles on its page',
      );
    });
  });
}
