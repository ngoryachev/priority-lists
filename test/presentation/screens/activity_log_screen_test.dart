import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_activity_log_repository.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/data/services/activity_logger.dart';
import 'package:priority_lists/domain/models/activity_event.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/repositories/activity_log_repository.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/activity_log_screen.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:provider/provider.dart';

ActivityEvent event(
  String id,
  DateTime at, {
  ActivityAction action = ActivityAction.created,
  String title = 'Node',
  List<String> path = const [],
  String details = '',
}) {
  return ActivityEvent(
    id: id,
    at: at,
    action: action,
    nodeId: 'n-$id',
    nodeTitle: title,
    path: path,
    details: details,
  );
}

DateTime todayAt(int hour) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour);
}

Widget screen(ActivityLogRepository log) {
  return MaterialApp(
    home: Provider<ActivityLogRepository>.value(
      value: log,
      child: const ActivityLogScreen(),
    ),
  );
}

void main() {
  late List<MethodCall> clipboard;

  setUp(() {
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('lists the day with its entries', (tester) async {
    final log = InMemoryActivityLogRepository();
    await log.append(event('1', todayAt(9), title: 'Fix login', details: 'High'));
    await log.append(event('2', todayAt(10),
        action: ActivityAction.prioritized,
        title: 'Fix logout',
        path: ['Work'],
        details: 'Medium → High'));

    await tester.pumpWidget(screen(log));
    await tester.pumpAndSettle();

    expect(find.text('Today · 2 changes'), findsOneWidget);
    expect(find.text('Fix login'), findsOneWidget);
    expect(find.text('Medium → High · in Work'), findsOneWidget);
  });

  testWidgets('says so when the period is empty', (tester) async {
    await tester.pumpWidget(screen(InMemoryActivityLogRepository()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing recorded'), findsOneWidget);
  });

  testWidgets('copies the day as a standup digest', (tester) async {
    final log = InMemoryActivityLogRepository();
    await log.append(event('1', todayAt(9), title: 'Fix login', details: 'High'));

    await tester.pumpWidget(screen(log));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pumpAndSettle();

    expect(clipboard, hasLength(1));
    expect(
      clipboard.single.arguments['text'],
      contains('- Added: "Fix login" — High'),
    );
    expect(find.textContaining('Copied'), findsOneWidget);
  });

  testWidgets('the Today period keeps this morning and drops yesterday',
      (tester) async {
    final log = InMemoryActivityLogRepository();
    await log.append(event('1', todayAt(0), title: 'This morning'));
    await log.append(event('2',
        todayAt(23).subtract(const Duration(days: 1)),
        title: 'Last night'));

    await tester.pumpWidget(screen(log));
    await tester.pumpAndSettle();
    expect(find.text('Last night'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.date_range));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today').last);
    await tester.pumpAndSettle();

    expect(find.text('This morning'), findsOneWidget);
    expect(find.text('Last night'), findsNothing);
  });

  testWidgets('shows the failure instead of an empty log', (tester) async {
    await tester.pumpWidget(screen(_BrokenLog()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load the history'), findsOneWidget);
  });

  testWidgets('the root screen opens the history and logs what it did',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = InMemoryPriorityNodeRepository();
    final log = InMemoryActivityLogRepository();
    final logger = ActivityLogger(log);
    final vm = NodeTreeViewModel(repository, logger: logger);

    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<PriorityNodeRepository>.value(value: repository),
          Provider<ActivityLogRepository>.value(value: log),
          ChangeNotifierProvider<NodeTreeViewModel>.value(value: vm),
          ChangeNotifierProvider(create: (_) => FilterViewModel()),
        ],
        child: const NodeScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    await vm.addChild(title: 'Fix login', priority: Priority.high);
    await logger.idle;
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();

    expect(find.text('History'), findsOneWidget);
    expect(find.text('Fix login'), findsOneWidget);
  });

  testWidgets('no history button when the app runs without a log',
      (tester) async {
    final repository = InMemoryPriorityNodeRepository();

    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<PriorityNodeRepository>.value(value: repository),
          ChangeNotifierProvider(create: (_) => NodeTreeViewModel(repository)),
          ChangeNotifierProvider(create: (_) => FilterViewModel()),
        ],
        child: const NodeScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.history), findsNothing);
  });
}

class _BrokenLog implements ActivityLogRepository {
  @override
  Future<void> append(ActivityEvent event) async => throw Exception('no table');

  @override
  Future<List<ActivityEvent>> recent({int limit = 500, DateTime? since}) async =>
      throw Exception('no table');
}
