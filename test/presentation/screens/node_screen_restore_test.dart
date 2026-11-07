import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_last_node_repository.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/last_node_repository.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/last_node_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/widgets/breadcrumb_bar.dart';
import 'package:provider/provider.dart';

PriorityNode node(String id, {String? parent}) {
  final created = DateTime(2026, 1, 1);
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    description: '',
    priority: Priority.high,
    createdAt: created,
    updatedAt: created,
  );
}

Future<PriorityNodeRepository> seeded(List<PriorityNode> nodes) async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes(nodes);
  return repository;
}

/// A > B > C, plus a sibling root to prove the restore picks one branch.
Future<PriorityNodeRepository> seededTree() => seeded([
  node('A'),
  node('B', parent: 'A'),
  node('C', parent: 'B'),
  node('Other'),
]);

/// The production tree: the tree providers sit *below* `MaterialApp`, so the
/// [Navigator] is above them — which is what the restore pushes have to work
/// against too. The last-node view model is registered above the
/// `MaterialApp`, like `lib/app.dart` does, since it outlives a sign-out.
Widget wrapLikeProduction(
  PriorityNodeRepository repository, {
  required LastNodeViewModel lastNodes,
}) {
  return Provider<LastNodeViewModel>.value(
    value: lastNodes,
    child: MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<PriorityNodeRepository>.value(value: repository),
          ChangeNotifierProvider(create: (_) => NodeTreeViewModel(repository)),
          ChangeNotifierProvider(create: (_) => FilterViewModel()),
        ],
        child: const NodeScreen(),
      ),
    ),
  );
}

/// Records every write in order, so a breadcrumb jump can be checked for
/// which level it ended up storing.
class _RecordingRepository implements LastNodeRepository {
  final calls = <String>[];
  LastNodePointer? stored;

  _RecordingRepository([this.stored]);

  @override
  Future<LastNodePointer?> load() async => stored;

  @override
  Future<void> save(LastNodePointer pointer) async {
    calls.add(pointer.nodeId ?? 'root');
    stored = pointer;
  }

  @override
  Future<void> clear() async {
    calls.add('clear');
    stored = null;
  }
}

/// A tree that cannot be read: the error state owns the screen and the saved
/// pointer has nothing to resolve against.
class _BrokenNodeRepository implements PriorityNodeRepository {
  @override
  Future<List<PriorityNode>> getAllNodes() async => throw StateError('offline');

  @override
  Future<void> saveNode(PriorityNode node) async {}

  @override
  Future<void> saveNodes(List<PriorityNode> nodes) async {}

  @override
  Future<void> deleteNode(String id) async {}
}

/// A store whose read can be held open: acts out the settings round-trip
/// still being in flight after the tree has painted.
class _GatedRepository implements LastNodeRepository {
  final gate = Completer<void>();
  LastNodePointer? stored;

  _GatedRepository(this.stored);

  @override
  Future<LastNodePointer?> load() async {
    await gate.future;
    return stored;
  }

  @override
  Future<void> save(LastNodePointer pointer) async => stored = pointer;

  @override
  Future<void> clear() async => stored = null;
}

/// A settings store that cannot be read or written at all.
class _BrokenLastNodeRepository implements LastNodeRepository {
  @override
  Future<LastNodePointer?> load() async => throw StateError('no storage');

  @override
  Future<void> save(LastNodePointer pointer) async =>
      throw StateError('no storage');

  @override
  Future<void> clear() async => throw StateError('no storage');
}

LastNodeViewModel viewModel(
  LastNodeRepository repository, {
  String userId = 'user-1',
}) {
  return LastNodeViewModel(
    repository: repository,
    currentUserId: () => userId,
  );
}

/// The default 800x600 test view is too short for the tiles this suite taps.
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// The root level is `MaterialApp.home`, so its route carries the Navigator's
/// initial name rather than a `node/<id>` one — which is why breadcrumbs pop
/// back to it through `route.isFirst`.
const rootRouteName = '/';

/// Names of the stacked levels, deepest last — the stack as breadcrumbs see
/// it. Levels below the top one are offstage, hence [skipOffstage].
List<String> stackNames(WidgetTester tester) {
  return [
    for (final element in find.byType(NodeScreen, skipOffstage: false).evaluate())
      if (ModalRoute.of(element)?.settings.name case final String name) name,
  ];
}

void main() {
  group('restoring the last opened node', () {
    testWidgets('opens the saved deep node with its full trail', (
      tester,
    ) async {
      usePhoneSize(tester);
      final lastNodes = viewModel(
        InMemoryLastNodeRepository(
          const LastNodePointer(userId: 'user-1', nodeId: 'C'),
        ),
      );

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(AppBar, 'C'), findsOneWidget);
      // Root, A and B are below it, each as its own named route — exactly the
      // stack a by-hand drill-down would have left.
      expect(stackNames(tester), [
        rootRouteName,
        BreadcrumbBar.routeName('A'),
        BreadcrumbBar.routeName('B'),
        BreadcrumbBar.routeName('C'),
      ]);
      final crumbs = find.descendant(
        of: find.byType(BreadcrumbBar),
        matching: find.byType(Text),
      );
      expect(
        tester.widgetList<Text>(crumbs).map((t) => t.data),
        ['All', 'A', 'B'],
      );
    });

    testWidgets('back walks up the rebuilt stack one level at a time', (
      tester,
    ) async {
      usePhoneSize(tester);
      final repository = InMemoryLastNodeRepository(
        const LastNodePointer(userId: 'user-1', nodeId: 'C'),
      );
      final lastNodes = viewModel(repository);

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'B'), findsOneWidget);
      await lastNodes.idle;
      expect((await repository.load())!.nodeId, 'B');

      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'A'), findsOneWidget);
      await lastNodes.idle;
      expect((await repository.load())!.nodeId, 'A');

      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Priority Lists'), findsOneWidget);
      await lastNodes.idle;
      expect(
        (await repository.load())!.nodeId,
        isNull,
        reason: 'back at the root, so the next launch must open there',
      );
    });

    testWidgets('a crumb tapped on a restored stack jumps to that level', (
      tester,
    ) async {
      usePhoneSize(tester);
      final repository = InMemoryLastNodeRepository(
        const LastNodePointer(userId: 'user-1', nodeId: 'C'),
      );
      final lastNodes = viewModel(repository);

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(BreadcrumbBar),
          matching: find.text('A'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'A'), findsOneWidget);
      expect(stackNames(tester), [
        rootRouteName,
        BreadcrumbBar.routeName('A'),
      ]);
      await lastNodes.idle;
      expect(
        (await repository.load())!.nodeId,
        'A',
        reason: 'the crumb that was tapped, not a level popped on the way',
      );
    });

    testWidgets('the leading crumb returns to the root and stores it', (
      tester,
    ) async {
      usePhoneSize(tester);
      final repository = InMemoryLastNodeRepository(
        const LastNodePointer(userId: 'user-1', nodeId: 'C'),
      );
      final lastNodes = viewModel(repository);

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(BreadcrumbBar),
          matching: find.text('All'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Priority Lists'), findsOneWidget);
      await lastNodes.idle;
      expect((await repository.load())!.nodeId, isNull);
    });

    testWidgets('a saved id that is not in the tree opens the root', (
      tester,
    ) async {
      usePhoneSize(tester);
      final repository = InMemoryLastNodeRepository(
        const LastNodePointer(userId: 'user-1', nodeId: 'deleted'),
      );
      final lastNodes = viewModel(repository);

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(AppBar, 'Priority Lists'), findsOneWidget);
      expect(stackNames(tester), [rootRouteName]);
      await lastNodes.idle;
      expect(
        await repository.load(),
        isNull,
        reason: 'a pointer that can never resolve should not be retried',
      );
    });

    testWidgets('a pointer saved for another account opens the root', (
      tester,
    ) async {
      usePhoneSize(tester);
      final repository = InMemoryLastNodeRepository(
        const LastNodePointer(userId: 'somebody-else', nodeId: 'C'),
      );
      final lastNodes = viewModel(repository, userId: 'user-1');

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Priority Lists'), findsOneWidget);
      expect(stackNames(tester), [rootRouteName]);
      await lastNodes.idle;
      expect(await repository.load(), isNull);
    });

    testWidgets('a root pointer opens the root', (tester) async {
      usePhoneSize(tester);
      final lastNodes = viewModel(
        InMemoryLastNodeRepository(const LastNodePointer(userId: 'user-1')),
      );

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Priority Lists'), findsOneWidget);
      expect(stackNames(tester), [rootRouteName]);
    });

    testWidgets('drilling down stores each level it passes through', (
      tester,
    ) async {
      usePhoneSize(tester);
      final repository = InMemoryLastNodeRepository();
      final lastNodes = viewModel(repository);

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await lastNodes.idle;
      expect((await repository.load())!.nodeId, 'A');

      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      await lastNodes.idle;
      expect((await repository.load())!.nodeId, 'B');
    });

    /// A pop can be caused by this screen's own node going away, and by then
    /// the tree can no longer say what sat above it — so the level to store
    /// has to have been cached while the node was still there. Deleting the
    /// current node exercises both pops that do it: the explicit one from the
    /// delete action and the `maybePop` the vanished node triggers.
    testWidgets('a level closed by deleting its node stores the parent', (
      tester,
    ) async {
      usePhoneSize(tester);
      final repository = _RecordingRepository(
        const LastNodePointer(userId: 'user-1', nodeId: 'C'),
      );
      final lastNodes = viewModel(repository);

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'C'), findsOneWidget);
      repository.calls.clear();

      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      await lastNodes.idle;

      // Both pops record the level above them, so the pointer tracks where
      // the user actually ends up rather than the deleted node or the root.
      expect(repository.calls, ['B', 'A']);
      expect(find.widgetWithText(AppBar, 'A'), findsOneWidget);
      expect(repository.stored!.nodeId, 'A');
    });

    /// The levels a jump pops through each record the level above them, so
    /// the tapped crumb only wins if its own write is enqueued last.
    testWidgets('a breadcrumb jump stores the crumb, not an intermediate '
        'level', (tester) async {
      usePhoneSize(tester);
      final repository = _RecordingRepository(
        const LastNodePointer(userId: 'user-1', nodeId: 'C'),
      );
      final lastNodes = viewModel(repository);

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();
      repository.calls.clear();

      await tester.tap(
        find.descendant(
          of: find.byType(BreadcrumbBar),
          matching: find.text('A'),
        ),
      );
      await tester.pumpAndSettle();
      await lastNodes.idle;

      expect(repository.calls.last, 'A');
    });

    /// One route per level is pushed in a single go; with the usual forward
    /// slide the app would visibly fan through every ancestor on launch.
    testWidgets('rebuilds the stack without per-level animations', (
      tester,
    ) async {
      usePhoneSize(tester);
      final lastNodes = viewModel(
        InMemoryLastNodeRepository(
          const LastNodePointer(userId: 'user-1', nodeId: 'C'),
        ),
      );

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      final pushed = find
          .byType(NodeScreen, skipOffstage: false)
          .evaluate()
          .map(ModalRoute.of)
          .whereType<ModalRoute<Object?>>()
          .where((route) => !route.isFirst);
      expect(pushed, hasLength(3));
      for (final route in pushed) {
        expect(route.transitionDuration, Duration.zero);
        expect(
          route.reverseTransitionDuration,
          greaterThan(Duration.zero),
          reason: 'walking back up a restored stack animates as usual',
        );
      }
    });

    testWidgets('a settings store that throws leaves the user at the root', (
      tester,
    ) async {
      usePhoneSize(tester);
      final lastNodes = viewModel(_BrokenLastNodeRepository());

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(AppBar, 'Priority Lists'), findsOneWidget);
      expect(stackNames(tester), [rootRouteName]);
    });

    /// Restoring must not paper over a tree that failed to load: without a
    /// tree the pointer cannot be resolved, and the error belongs on screen.
    testWidgets('a tree that fails to load still shows its error', (
      tester,
    ) async {
      usePhoneSize(tester);
      final lastNodes = viewModel(
        InMemoryLastNodeRepository(
          const LastNodePointer(userId: 'user-1', nodeId: 'C'),
        ),
      );

      await tester.pumpWidget(
        wrapLikeProduction(_BrokenNodeRepository(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('offline'), findsOneWidget);
      expect(stackNames(tester), [rootRouteName]);
    });

    /// Nothing may be awaited before the first frame: the root level paints
    /// straight away, and the saved level arrives once the tree is there.
    testWidgets('does not block the first frame', (tester) async {
      usePhoneSize(tester);
      final lastNodes = viewModel(
        InMemoryLastNodeRepository(
          const LastNodePointer(userId: 'user-1', nodeId: 'C'),
        ),
      );

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );

      expect(find.widgetWithText(AppBar, 'Priority Lists'), findsOneWidget);
      expect(stackNames(tester), [rootRouteName]);

      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'C'), findsOneWidget);
    });

    /// The tree paints before the settings read comes back, so a tap can land
    /// in between. The user's own navigation is newer than the pointer and
    /// must not get a restored stack piled on top of it.
    testWidgets('leaves a stack the user navigated themselves alone', (
      tester,
    ) async {
      usePhoneSize(tester);
      final repository = _GatedRepository(
        const LastNodePointer(userId: 'user-1', nodeId: 'C'),
      );
      final lastNodes = viewModel(repository);

      await tester.pumpWidget(
        wrapLikeProduction(await seededTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      // The tree is on screen while the pointer is still being read.
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      repository.gate.complete();
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Other'), findsOneWidget);
      expect(stackNames(tester), [
        rootRouteName,
        BreadcrumbBar.routeName('Other'),
      ]);
    });

    /// The root screen is remounted on an in-session sign-in, which is the
    /// only chance to pick up the new account's pointer.
    testWidgets('restores on a remount, not only on a cold start', (
      tester,
    ) async {
      usePhoneSize(tester);
      final lastNodes = viewModel(
        InMemoryLastNodeRepository(
          const LastNodePointer(userId: 'user-1', nodeId: 'B'),
        ),
      );
      final repository = await seededTree();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpWidget(
        wrapLikeProduction(repository, lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'B'), findsOneWidget);
    });

    /// A screen built without the settings store still has to drill down.
    testWidgets('works with no last-node view model at all', (tester) async {
      usePhoneSize(tester);
      final repository = await seededTree();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              Provider<PriorityNodeRepository>.value(value: repository),
              ChangeNotifierProvider(
                create: (_) => NodeTreeViewModel(repository),
              ),
              ChangeNotifierProvider(create: (_) => FilterViewModel()),
            ],
            child: const NodeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(AppBar, 'A'), findsOneWidget);
    });
  });
}
