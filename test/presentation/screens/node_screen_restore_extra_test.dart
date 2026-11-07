import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// Flows the restore suite does not cover: the real ways up out of a level
/// (the app bar button and the system gesture), deeper and shallower stacks,
/// and what happens on the second launch / second account.

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

/// A > B > C > D, with a second branch under A and a second root.
Future<PriorityNodeRepository> deepTree() => seeded([
  node('A'),
  node('B', parent: 'A'),
  node('C', parent: 'B'),
  node('D', parent: 'C'),
  node('Bee', parent: 'A'),
  node('Other'),
]);

/// Records every write in order so a flow can be checked for what it stored.
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

void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

const rootRouteName = '/';

List<String> stackNames(WidgetTester tester) {
  return [
    for (final element
        in find.byType(NodeScreen, skipOffstage: false).evaluate())
      if (ModalRoute.of(element)?.settings.name case final String name) name,
  ];
}

Finder crumb(String label) => find.descendant(
  of: find.byType(BreadcrumbBar),
  matching: find.text(label),
);

void main() {
  group('ways up out of a level', () {
    testWidgets('the app bar back button stores the parent level', (
      tester,
    ) async {
      usePhoneSize(tester);
      final store = _RecordingRepository();
      final lastNodes = LastNodeViewModel(
        repository: store,
        currentUserId: () => 'user-1',
      );

      await tester.pumpWidget(
        wrapLikeProduction(await deepTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B'));
      await tester.pumpAndSettle();
      await lastNodes.idle;
      expect(store.stored!.nodeId, 'B');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await lastNodes.idle;

      expect(find.widgetWithText(AppBar, 'A'), findsOneWidget);
      expect(store.stored!.nodeId, 'A');
    });

    testWidgets('the system back gesture stores the parent level', (
      tester,
    ) async {
      usePhoneSize(tester);
      final store = _RecordingRepository();
      final lastNodes = LastNodeViewModel(
        repository: store,
        currentUserId: () => 'user-1',
      );

      await tester.pumpWidget(
        wrapLikeProduction(await deepTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      // What the platform channel does for the Android back gesture.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await lastNodes.idle;

      expect(find.widgetWithText(AppBar, 'Priority Lists'), findsOneWidget);
      expect(
        store.stored!.nodeId,
        isNull,
        reason: 'back at the root, so the next launch opens there',
      );
    });
  });

  group('restoring deeper and shallower stacks', () {
    testWidgets('a top-level node restores to a single pushed level', (
      tester,
    ) async {
      usePhoneSize(tester);
      final store = _RecordingRepository(
        const LastNodePointer(userId: 'user-1', nodeId: 'A'),
      );
      final lastNodes = LastNodeViewModel(
        repository: store,
        currentUserId: () => 'user-1',
      );

      await tester.pumpWidget(
        wrapLikeProduction(await deepTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'A'), findsOneWidget);
      expect(stackNames(tester), [rootRouteName, BreadcrumbBar.routeName('A')]);
      // A level directly under the root has no trail to show.
      expect(find.byType(BreadcrumbBar), findsNothing);
      // The restore itself is a read, not a write: the pointer is already
      // where it should be.
      await lastNodes.idle;
      expect(store.calls, isEmpty);
      expect(store.stored!.nodeId, 'A');
    });

    testWidgets('a four-deep node restores with its whole trail', (
      tester,
    ) async {
      usePhoneSize(tester);
      final lastNodes = LastNodeViewModel(
        repository: _RecordingRepository(
          const LastNodePointer(userId: 'user-1', nodeId: 'D'),
        ),
        currentUserId: () => 'user-1',
      );

      await tester.pumpWidget(
        wrapLikeProduction(await deepTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'D'), findsOneWidget);
      expect(stackNames(tester), [
        rootRouteName,
        BreadcrumbBar.routeName('A'),
        BreadcrumbBar.routeName('B'),
        BreadcrumbBar.routeName('C'),
        BreadcrumbBar.routeName('D'),
      ]);
      expect(
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(BreadcrumbBar),
                matching: find.byType(Text),
              ),
            )
            .map((t) => t.data),
        ['All', 'A', 'B', 'C'],
      );
      // A restored level has to look like a drilled-down one, back button
      // included.
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('a crumb in the middle of a deep restored stack', (
      tester,
    ) async {
      usePhoneSize(tester);
      final store = _RecordingRepository(
        const LastNodePointer(userId: 'user-1', nodeId: 'D'),
      );
      final lastNodes = LastNodeViewModel(
        repository: store,
        currentUserId: () => 'user-1',
      );

      await tester.pumpWidget(
        wrapLikeProduction(await deepTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();
      store.calls.clear();

      await tester.tap(crumb('B'));
      await tester.pumpAndSettle();
      await lastNodes.idle;

      expect(find.widgetWithText(AppBar, 'B'), findsOneWidget);
      expect(stackNames(tester), [
        rootRouteName,
        BreadcrumbBar.routeName('A'),
        BreadcrumbBar.routeName('B'),
      ]);
      expect(
        store.stored!.nodeId,
        'B',
        reason: 'the crumb that was tapped, not a level popped on the way',
      );
    });

    testWidgets('drilling on after a restore keeps the pointer in step', (
      tester,
    ) async {
      usePhoneSize(tester);
      final store = _RecordingRepository(
        const LastNodePointer(userId: 'user-1', nodeId: 'A'),
      );
      final lastNodes = LastNodeViewModel(
        repository: store,
        currentUserId: () => 'user-1',
      );

      await tester.pumpWidget(
        wrapLikeProduction(await deepTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'A'), findsOneWidget);

      // The other branch under A, to prove the restored stack is a normal one.
      await tester.tap(find.text('Bee'));
      await tester.pumpAndSettle();
      await lastNodes.idle;
      expect(store.stored!.nodeId, 'Bee');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await lastNodes.idle;
      expect(find.widgetWithText(AppBar, 'A'), findsOneWidget);
      expect(store.stored!.nodeId, 'A');
    });
  });

  group('later in the session', () {
    /// The tree is re-read when the app comes back to the foreground; that
    /// must not drag the user back down to where they launched.
    testWidgets('a resume after walking back up does not restore again', (
      tester,
    ) async {
      usePhoneSize(tester);
      final store = _RecordingRepository(
        const LastNodePointer(userId: 'user-1', nodeId: 'C'),
      );
      final lastNodes = LastNodeViewModel(
        repository: store,
        currentUserId: () => 'user-1',
      );

      await tester.pumpWidget(
        wrapLikeProduction(await deepTree(), lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'C'), findsOneWidget);

      await tester.tap(crumb('All'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Priority Lists'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Priority Lists'), findsOneWidget);
      expect(stackNames(tester), [rootRouteName]);
    });

    /// Signing in as somebody else remounts the root screen; the first
    /// account's pointer must not reopen their level under the new account.
    testWidgets('a second account signing in opens at the root', (
      tester,
    ) async {
      usePhoneSize(tester);
      final store = _RecordingRepository();
      var userId = 'user-1';
      final lastNodes = LastNodeViewModel(
        repository: store,
        currentUserId: () => userId,
      );
      final repository = await deepTree();

      await tester.pumpWidget(
        wrapLikeProduction(repository, lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();
      await lastNodes.idle;
      expect(store.stored, const LastNodePointer(userId: 'user-1', nodeId: 'A'));

      // Sign out, sign in as somebody else: the root screen is rebuilt from
      // scratch, which is where a restore would happen.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      userId = 'user-2';
      await tester.pumpWidget(
        wrapLikeProduction(repository, lastNodes: lastNodes),
      );
      await tester.pumpAndSettle();
      await lastNodes.idle;

      expect(find.widgetWithText(AppBar, 'Priority Lists'), findsOneWidget);
      expect(stackNames(tester), [rootRouteName]);
      expect(
        store.stored,
        isNull,
        reason: "the other account's pointer is dropped, not kept around",
      );
    });
  });

  /// The levels must not arrive one frame at a time: pushed in a single batch
  /// with no forward transition, the deepest level is already on top the
  /// first time anything below the root is on screen.
  group('no visible fan through the levels', () {
    testWidgets('the stack goes from the root straight to the saved level', (
      tester,
    ) async {
      usePhoneSize(tester);
      final lastNodes = LastNodeViewModel(
        repository: _RecordingRepository(
          const LastNodePointer(userId: 'user-1', nodeId: 'D'),
        ),
        currentUserId: () => 'user-1',
      );

      await tester.pumpWidget(
        wrapLikeProduction(await deepTree(), lastNodes: lastNodes),
      );

      // The deepest route of every frame between launch and settling.
      final tops = <String>{stackNames(tester).last};
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        tops.add(stackNames(tester).last);
      }

      expect(find.widgetWithText(AppBar, 'D'), findsOneWidget);
      expect(tops, {rootRouteName, BreadcrumbBar.routeName('D')});
    });
  });
}
