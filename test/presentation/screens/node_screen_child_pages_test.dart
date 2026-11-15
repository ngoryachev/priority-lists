import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/card_page_view_model.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/priority_card.dart';
import 'package:provider/provider.dart';

/// The list tile's second axis: swiping a card sideways browses the node's
/// own children, each as a full-size face with only the 1-4 priority row.

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

/// "Parent" with three children in sort order (c1, c2, c3) next to a childless
/// root, so one level holds both a swipeable card and a card that must not
/// swipe.
Future<PriorityNodeRepository> seededLevel() => seeded([
  node('Parent', priority: Priority.critical),
  node('c1', parent: 'Parent', createdOffset: 1),
  node('c2', parent: 'Parent', createdOffset: 2),
  node('c3', parent: 'Parent', createdOffset: 3),
  node('Lonely', priority: Priority.high, createdOffset: 4),
]);

/// The production tree: the tree providers sit below `MaterialApp` while the
/// remembered card pages sit above it, like `lib/app.dart` does — the record
/// has to outlive the screens that read it.
Widget app(
  PriorityNodeRepository repository, {
  required CardPageViewModel cardPages,
  FilterViewModel? filter,
}) {
  return Provider<CardPageViewModel>.value(
    value: cardPages,
    child: MaterialApp(
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
    ),
  );
}

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Cards are found by the node they belong to, which is stable whatever page
/// they are showing.
Finder cardOf(String title) => find.byWidgetPredicate(
  (widget) => widget is PriorityCard && widget.title == title,
);

/// The title a card currently paints.
///
/// Picked by its text style rather than by matching a string: a page-0 face
/// also carries its children's titles as chips, and a child face carries the
/// owner's title in its label. Only the title is bold at 16dp or more — the
/// badge, the chips, the counter and the 1-4 buttons are all smaller.
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

NodeTreeViewModel treeOf(WidgetTester tester) => Provider.of<NodeTreeViewModel>(
  tester.element(find.byType(NodeScreen).first),
  listen: false,
);

void main() {
  group('child pages on a list tile', () {
    testWidgets('swiping walks the children in sort order and stops at the '
        'ends', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        app(await seededLevel(), cardPages: CardPageViewModel()),
      );
      await tester.pumpAndSettle();

      expect(shownTitle(tester, 'Parent'), 'Parent');
      final tileHeight = tester.getSize(cardOf('Parent')).height;

      // No wrap-around backwards: page 0 is the first page.
      await swipe(tester, 'Parent', back: true);
      expect(shownTitle(tester, 'Parent'), 'Parent');

      for (final child in ['c1', 'c2', 'c3']) {
        await swipe(tester, 'Parent');
        expect(shownTitle(tester, 'Parent'), child);
        // The tile keeps the owner's height on every page, so the list does
        // not jump while swiping.
        expect(tester.getSize(cardOf('Parent')).height, tileHeight);
        // Whose card this is, so a child page is not mistaken for its own.
        expect(
          find.descendant(of: cardOf('Parent'), matching: find.text('Parent ›')),
          findsOneWidget,
        );
      }

      // No wrap-around forwards either: the last child stays.
      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c3');

      await swipe(tester, 'Parent', back: true);
      expect(shownTitle(tester, 'Parent'), 'c2');
    });

    testWidgets('the counter counts children, not pages', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        app(await seededLevel(), cardPages: CardPageViewModel()),
      );
      await tester.pumpAndSettle();

      Finder counter(String label) =>
          find.descendant(of: cardOf('Parent'), matching: find.text(label));

      // Page 0 is the node itself and carries no counter.
      expect(counter('1/3'), findsNothing);
      expect(
        find.descendant(
          of: cardOf('Parent'),
          matching: find.byIcon(Icons.more_vert),
        ),
        findsOneWidget,
        reason: 'the dots hint at the swipe from page 0 too',
      );

      for (final page in ['1/3', '2/3', '3/3']) {
        await swipe(tester, 'Parent');
        expect(counter(page), findsOneWidget);
      }
    });

    testWidgets('swiping back to the node itself drops the counter and the '
        'remembered page', (tester) async {
      usePhoneSize(tester);
      final filter = FilterViewModel();
      final cardPages = CardPageViewModel();
      await tester.pumpWidget(
        app(await seededLevel(), cardPages: cardPages, filter: filter),
      );
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      expect(cardPages.childFor('Parent'), 'c1');

      // Anything that rebuilds the level while the card sits on a child page:
      // from here on the card is handed the page it is already on, and must
      // not read it back as "go there" once the user has left it.
      filter.setLevel(3);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('1/3')),
        findsOneWidget,
      );

      await swipe(tester, 'Parent', back: true);
      expect(shownTitle(tester, 'Parent'), 'Parent');
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('1/3')),
        findsNothing,
        reason: 'page 0 is the node itself and carries no counter',
      );
      expect(cardPages.childFor('Parent'), isNull);
    });

    testWidgets('a card with no visible children neither hints nor swipes',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        app(await seededLevel(), cardPages: CardPageViewModel()),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: cardOf('Lonely'),
          matching: find.byIcon(Icons.more_vert),
        ),
        findsNothing,
      );

      await swipe(tester, 'Lonely');
      expect(shownTitle(tester, 'Lonely'), 'Lonely');
    });

    testWidgets('children hidden by the filter are skipped', (tester) async {
      usePhoneSize(tester);
      final filter = FilterViewModel();
      final repository = await seeded([
        node('Parent', priority: Priority.critical),
        node('c1', parent: 'Parent', priority: Priority.high, createdOffset: 1),
        node('c2', parent: 'Parent', priority: Priority.low, createdOffset: 2),
        node('c3', parent: 'Parent', priority: Priority.high, createdOffset: 3),
        node('OnlyLow', priority: Priority.high, createdOffset: 4),
        node('hidden', parent: 'OnlyLow', priority: Priority.low),
      ]);
      await tester.pumpWidget(
        app(repository, cardPages: CardPageViewModel(), filter: filter),
      );
      await tester.pumpAndSettle();

      filter.setLevel(2); // critical + high
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c1');
      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c3', reason: 'c2 is filtered out');
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('2/2')),
        findsOneWidget,
      );

      // Every child filtered out is the same as having none.
      expect(
        find.descendant(
          of: cardOf('OnlyLow'),
          matching: find.byIcon(Icons.more_vert),
        ),
        findsNothing,
      );
      await swipe(tester, 'OnlyLow');
      expect(shownTitle(tester, 'OnlyLow'), 'OnlyLow');
    });

    testWidgets('setting a priority on a child page keeps the card on that '
        'child', (tester) async {
      usePhoneSize(tester);
      final repository = await seededLevel();
      await tester.pumpWidget(
        app(repository, cardPages: CardPageViewModel()),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        await swipe(tester, 'Parent');
      }
      expect(shownTitle(tester, 'Parent'), 'c3');
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('3/3')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: cardOf('Parent'), matching: find.text('1')),
      );
      await tester.pumpAndSettle();

      // The write went through the view model, so the critical node now sorts
      // first — the card follows the child, not the index.
      final stored = await repository.getAllNodes();
      expect(
        stored.firstWhere((n) => n.id == 'c3').priority,
        Priority.critical,
      );
      expect(shownTitle(tester, 'Parent'), 'c3');
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('1/3')),
        findsOneWidget,
      );
    });

    testWidgets('tapping a child page opens that child', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(
        app(await seededLevel(), cardPages: CardPageViewModel()),
      );
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      await tester.tap(
        find.descendant(of: cardOf('Parent'), matching: find.text('c1')),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('c1')),
        findsOneWidget,
      );
    });

    testWidgets('the page survives leaving the level and coming back',
        (tester) async {
      usePhoneSize(tester);
      final cardPages = CardPageViewModel();
      final repository = await seededLevel();
      await tester.pumpWidget(app(repository, cardPages: cardPages));
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c2');
      expect(cardPages.childFor('Parent'), 'c2');

      // Away and back: another level on top of this one.
      await tester.tap(find.text('Lonely'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(shownTitle(tester, 'Parent'), 'c2');

      // And across a screen that is built from scratch, which is what the
      // side record is for.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(repository, cardPages: cardPages));
      await tester.pumpAndSettle();
      expect(shownTitle(tester, 'Parent'), 'c2');
    });

    testWidgets('a remembered child that is gone falls back to page 0',
        (tester) async {
      usePhoneSize(tester);
      final cardPages = CardPageViewModel();
      await tester.pumpWidget(
        app(await seededLevel(), cardPages: cardPages),
      );
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c1');

      await treeOf(tester).deleteNode('c1');
      await tester.pumpAndSettle();

      expect(shownTitle(tester, 'Parent'), 'Parent');
      expect(
        find.descendant(of: cardOf('Parent'), matching: find.text('1/2')),
        findsNothing,
      );
    });

    testWidgets('a remembered child filtered out falls back to page 0',
        (tester) async {
      usePhoneSize(tester);
      final filter = FilterViewModel();
      // Two children, so the pages do not simply run out: the card has to
      // land on page 0 rather than on the sibling that is still visible.
      final repository = await seeded([
        node('Parent', priority: Priority.critical),
        node('kept', parent: 'Parent', priority: Priority.high),
        node('c1', parent: 'Parent', priority: Priority.low, createdOffset: 1),
      ]);
      await tester.pumpWidget(
        app(repository, cardPages: CardPageViewModel(), filter: filter),
      );
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c1');

      filter.setLevel(2);
      await tester.pumpAndSettle();
      expect(shownTitle(tester, 'Parent'), 'Parent');
    });

    testWidgets('the grip reorders the whole tile from a child page',
        (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        node('P1', priority: Priority.critical),
        node('a1', parent: 'P1', createdOffset: 1),
        node('P2', priority: Priority.critical, createdOffset: 2),
        node('b1', parent: 'P2', createdOffset: 3),
      ]);
      await tester.pumpWidget(app(repository, cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      List<String> order() => tester
          .widgetList<PriorityCard>(find.byType(PriorityCard))
          .map((card) => card.title)
          .toList();
      expect(order(), ['P1', 'P2']);

      await swipe(tester, 'P2');
      expect(shownTitle(tester, 'P2'), 'b1');

      // The grip belongs to the tile, so it drags the parent even while the
      // card shows one of its children.
      final grip = find.descendant(
        of: cardOf('P2'),
        matching: find.byIcon(Icons.drag_handle),
      );
      final gesture = await tester.startGesture(tester.getCenter(grip));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(order(), ['P2', 'P1']);
      // The page comes back with the tile: the dragged copy is rebuilt from
      // the remembered child.
      expect(shownTitle(tester, 'P2'), 'b1');
    });

    testWidgets('a vertical drag on a card still scrolls the level',
        (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        for (var i = 0; i < 8; i++)
          node('P$i', priority: Priority.high, createdOffset: i * 2),
        for (var i = 0; i < 8; i++)
          node('child of P$i', parent: 'P$i', createdOffset: i * 2 + 1),
      ]);
      await tester.pumpWidget(app(repository, cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      expect(cardOf('P0'), findsOneWidget);
      final before = tester.getTopLeft(cardOf('P1')).dy;

      await tester.drag(cardOf('P1'), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(cardOf('P1')).dy,
        lessThan(before),
        reason: 'the list scrolled rather than the card turning a page',
      );
      expect(shownTitle(tester, 'P1'), 'P1');
    });

    testWidgets('the left edge keeps the tap and the scroll, and gives up '
        'only the page turn', (tester) async {
      usePhoneSize(tester);
      final repository = await seeded([
        for (var i = 0; i < 8; i++)
          node('P$i', priority: Priority.high, createdOffset: i * 2),
        for (var i = 0; i < 8; i++)
          node('child of P$i', parent: 'P$i', createdOffset: i * 2 + 1),
      ]);
      await tester.pumpWidget(app(repository, cardPages: CardPageViewModel()));
      await tester.pumpAndSettle();

      // A point inside the strip the card hands back to the platform's back
      // gesture: the card's left edge plus half the gutter.
      Offset edgeOf(String title) {
        final box = tester.getRect(cardOf(title));
        return Offset(box.left + 12, box.center.dy);
      }

      // A horizontal drag there does not turn the page — that is the whole
      // point of the strip, and the only thing it gives up.
      await tester.dragFrom(edgeOf('P1'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(shownTitle(tester, 'P1'), 'P1');

      // A tap there still opens the node.
      await tester.tapAt(edgeOf('P1'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('P1')),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      // And a vertical drag still scrolls the level: the list sits above the
      // card, so it is in the arena whatever the card does with the strip.
      final before = tester.getTopLeft(cardOf('P1')).dy;
      await tester.dragFrom(edgeOf('P1'), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(cardOf('P1')).dy, lessThan(before));
    });

    testWidgets('a move in progress forces every card to page 0',
        (tester) async {
      usePhoneSize(tester);
      final cardPages = CardPageViewModel();
      await tester.pumpWidget(
        app(await seededLevel(), cardPages: cardPages),
      );
      await tester.pumpAndSettle();

      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'c1');

      // Pick the childless card up, so the swipeable one is a drop target.
      await tester.tap(
        find.descendant(
          of: cardOf('Lonely'),
          matching: find.byIcon(Icons.move_to_inbox),
        ),
      );
      await tester.pumpAndSettle();

      expect(shownTitle(tester, 'Parent'), 'Parent');
      expect(
        find.descendant(
          of: cardOf('Parent'),
          matching: find.byIcon(Icons.more_vert),
        ),
        findsNothing,
      );
      await swipe(tester, 'Parent');
      expect(shownTitle(tester, 'Parent'), 'Parent');
      expect(cardPages.childFor('Parent'), 'c1', reason: 'the page is kept');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(shownTitle(tester, 'Parent'), 'c1');
    });
  });
}
