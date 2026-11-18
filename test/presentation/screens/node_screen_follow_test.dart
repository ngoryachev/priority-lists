import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/repositories/card_page_repository.dart';
import 'package:priority_lists/domain/repositories/last_node_repository.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/card_page_view_model.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/last_node_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:provider/provider.dart';

/// Another device moves around the tree while this one is in the background:
/// coming back to the foreground follows it, the same moment the tree itself
/// is refreshed.

PriorityNode node(String id, {String? parent, Priority? priority}) {
  final created = DateTime(2026, 1, 1);
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    description: '',
    priority: priority ?? Priority.high,
    createdAt: created,
    updatedAt: created,
  );
}

const roleId = 'Root';
const userId = 'user-1';

Future<PriorityNodeRepository> deepTree() async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes([
    node(roleId, priority: Priority.critical),
    node('A', parent: roleId),
    node('B', parent: 'A'),
    node('C', parent: 'B'),
    node('A1', parent: 'A'),
    node('A2', parent: 'A'),
    node('Other', parent: roleId),
  ]);
  return repository;
}

/// The shared server row, as seen by this device.
class _SharedPointer implements LastNodeRepository {
  LastNodePointer? stored;
  bool failing = false;

  _SharedPointer([this.stored]);

  @override
  Future<LastNodePointer?> load() async {
    if (failing) throw StateError('offline');
    return stored;
  }

  @override
  Future<void> save(LastNodePointer pointer) async {
    if (failing) throw StateError('offline');
    stored = pointer;
  }

  @override
  Future<void> clear() async => stored = null;
}

class _SharedPages implements CardPageRepository {
  Map<String, String>? stored;

  @override
  Future<Map<String, String>?> load() async =>
      stored == null ? null : Map.of(stored!);

  @override
  Future<void> save(Map<String, String> pages) async => stored = Map.of(pages);
}

Widget app(
  PriorityNodeRepository repository, {
  required LastNodeViewModel lastNodes,
  CardPageViewModel? cardPages,
}) {
  return MultiProvider(
    providers: [
      Provider<LastNodeViewModel>.value(value: lastNodes),
      if (cardPages != null)
        Provider<CardPageViewModel>.value(value: cardPages),
    ],
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

List<String> stackNames(WidgetTester tester) => [
  for (final element in find.byType(NodeScreen, skipOffstage: false).evaluate())
    if (ModalRoute.of(element)?.settings.name case final String name) name,
];

Future<void> resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  late _SharedPointer server;
  late LastNodeViewModel lastNodes;

  /// Built inside each test body, not in `setUp`: the view model's write
  /// queue has to live in the test's fake-async zone, or its awaits never
  /// complete under `pump`.
  void startAtC() {
    server = _SharedPointer(const LastNodePointer(userId: userId, nodeId: 'C'));
    lastNodes = LastNodeViewModel(
      repository: server,
      currentUserId: () => userId,
    );
  }

  group('coming back to the foreground', () {
    testWidgets('follows the level another device left', (tester) async {
      usePhoneSize(tester);
      startAtC();
      await tester.pumpWidget(app(await deepTree(), lastNodes: lastNodes));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'C'), findsOneWidget);

      // The other device walks over to another branch.
      server.stored = const LastNodePointer(userId: userId, nodeId: 'Other');
      await resume(tester);

      expect(find.widgetWithText(AppBar, 'Other'), findsOneWidget);
      expect(stackNames(tester), ['/', 'node/Other']);
      expect(server.stored?.nodeId, 'Other');
    });

    testWidgets('follows another device back to the main screen', (
      tester,
    ) async {
      usePhoneSize(tester);
      startAtC();
      await tester.pumpWidget(app(await deepTree(), lastNodes: lastNodes));
      await tester.pumpAndSettle();

      server.stored = const LastNodePointer(userId: userId);
      await resume(tester);

      expect(find.widgetWithText(AppBar, roleId), findsOneWidget);
      expect(stackNames(tester), ['/']);
    });

    testWidgets('stays put when nothing changed elsewhere', (tester) async {
      usePhoneSize(tester);
      startAtC();
      await tester.pumpWidget(app(await deepTree(), lastNodes: lastNodes));
      await tester.pumpAndSettle();
      final before = stackNames(tester);

      await resume(tester);

      expect(stackNames(tester), before);
      expect(find.widgetWithText(AppBar, 'C'), findsOneWidget);
    });

    testWidgets('a store that cannot be read leaves the user where they are', (
      tester,
    ) async {
      usePhoneSize(tester);
      startAtC();
      await tester.pumpWidget(app(await deepTree(), lastNodes: lastNodes));
      await tester.pumpAndSettle();

      server.failing = true;
      await resume(tester);

      expect(find.widgetWithText(AppBar, 'C'), findsOneWidget);
      expect(stackNames(tester), ['/', 'node/A', 'node/B', 'node/C']);
    });

    testWidgets('a dialog on top is left alone', (tester) async {
      usePhoneSize(tester);
      startAtC();
      await tester.pumpWidget(app(await deepTree(), lastNodes: lastNodes));
      await tester.pumpAndSettle();
      final context = tester.element(find.widgetWithText(AppBar, 'C'));
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('editing')),
      );
      await tester.pumpAndSettle();

      server.stored = const LastNodePointer(userId: userId, nodeId: 'Other');
      await resume(tester);

      expect(find.text('editing'), findsOneWidget);
      expect(stackNames(tester), ['/', 'node/A', 'node/B', 'node/C']);
    });
  });

  group('card pages from another device', () {
    testWidgets('a launch opens every card on its stored page', (tester) async {
      usePhoneSize(tester);
      startAtC();
      server.stored = const LastNodePointer(userId: userId);
      final pages = _SharedPages()..stored = {'A': 'A2'};
      final cardPages = CardPageViewModel(repository: pages);

      await tester.pumpWidget(
        app(await deepTree(), lastNodes: lastNodes, cardPages: cardPages),
      );
      await tester.pumpAndSettle();

      expect(cardPages.childFor('A'), 'A2');
      expect(find.text('3/3'), findsOneWidget);
    });

    testWidgets('a resume moves a card to the page another device left', (
      tester,
    ) async {
      usePhoneSize(tester);
      startAtC();
      server.stored = const LastNodePointer(userId: userId);
      final pages = _SharedPages();
      final cardPages = CardPageViewModel(repository: pages);

      await tester.pumpWidget(
        app(await deepTree(), lastNodes: lastNodes, cardPages: cardPages),
      );
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsNothing);

      pages.stored = {'A': 'A1'};
      await resume(tester);

      expect(find.text('2/3'), findsOneWidget);
    });
  });
}
