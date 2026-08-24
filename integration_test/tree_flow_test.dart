// Runs the real app — Supabase client, real network, real gestures — on a
// device or emulator. Widget tests stub the repository and the browser E2E
// only covers web; this is what says the tree works on a phone.
//
//   flutter test integration_test/tree_flow_test.dart \
//     --dart-define-from-file=.env.json -d <device>
//
// It signs in as a throwaway account and deletes what it creates.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:priority_lists/app.dart';
import 'package:priority_lists/config/env.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/data/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const email = String.fromEnvironment(
  'E2E_EMAIL',
  defaultValue: 'e2e-mobile@example.com',
);
const password = String.fromEnvironment(
  'E2E_PASSWORD',
  defaultValue: 'E2ePassw0rd!mobile',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signs in and nests nodes several levels deep', (tester) async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );
    final client = Supabase.instance.client;
    await client.auth.signOut();

    await tester.pumpWidget(
      PriorityListsApp(
        // The pre-auth repository is irrelevant here: the test signs in, and
        // an in-memory one keeps the device's files out of the run.
        localRepository: InMemoryPriorityNodeRepository(),
        authService: AuthService(client),
      ),
    );
    await tester.pumpAndSettle();

    // --- sign in -----------------------------------------------------------
    expect(find.text('Sign In'), findsWidgets);
    await tester.enterText(find.byType(TextFormField).at(0), email);
    await tester.enterText(find.byType(TextFormField).at(1), password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));

    await _settle(tester, find.byIcon(Icons.logout));
    expect(find.byIcon(Icons.logout), findsOneWidget,
        reason: 'sign-in should land on the top level of the tree');

    // Start from a clean tree so a previous, interrupted run cannot skew the
    // counts below. This is a throwaway account with nothing worth keeping.
    await client.from('nodes').delete().eq('user_id', client.auth.currentUser!.id);
    await tester.pumpAndSettle();

    // --- build a chain -----------------------------------------------------
    await _addNode(tester, 'Android Root');
    expect(find.text('Android Root'), findsWidgets);

    await _openCard(tester, 'Android Root');
    await _addNode(tester, 'A1');

    await _openCard(tester, 'A1');
    await _addNode(tester, 'A2');

    await _openCard(tester, 'A2');
    await _addNode(tester, 'A3');
    expect(find.text('A3'), findsWidgets,
        reason: 'the fourth level should hold children like any other');

    // The trail names every ancestor of the current level.
    expect(find.text('Android Root'), findsWidgets);
    expect(find.text('A1'), findsWidgets);

    // --- persistence: the server has the whole chain -----------------------
    final rows = await client
        .from('nodes')
        .select('id, title, parent_id, priority')
        .inFilter('title', ['Android Root', 'A1', 'A2', 'A3']);
    expect(rows.length, 4, reason: 'every level should have been saved');
    final byTitle = {for (final row in rows) row['title']: row};
    expect(byTitle['Android Root']!['parent_id'], isNull);
    expect(byTitle['A1']!['parent_id'], byTitle['Android Root']!['id']);
    expect(byTitle['A2']!['parent_id'], byTitle['A1']!['id']);
    expect(byTitle['A3']!['parent_id'], byTitle['A2']!['id']);
    // Nodes take the dialog's default priority.
    expect(rows.every((row) => row['priority'] == 3), isTrue,
        reason: 'each node should have been saved as medium');

    // --- raising a priority from the card's 1..4 row -----------------------
    await tester.tap(find.widgetWithText(Material, '1').first);
    await _pumpFor(tester, const Duration(seconds: 3));
    final raised = await client
        .from('nodes')
        .select('priority')
        .eq('id', byTitle['A3']!['id'])
        .single();
    expect(raised['priority'], 1,
        reason: 'tapping "1" should promote the node to critical');

    // --- clean up: deleting the root takes the subtree with it -------------
    final createdIds = [for (final row in rows) row['id'] as String];
    await client.from('nodes').delete().eq('id', byTitle['Android Root']!['id']);

    final left = await client
        .from('nodes')
        .select('id')
        .inFilter('id', createdIds);
    expect(left, isEmpty,
        reason: 'the cascade should take every descendant with the root');
  });
}

/// Keeps the frame loop running for [duration] — used after taps whose effect
/// lands over the network rather than in the next frame.
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Pumps until [target] shows up, so network latency does not decide the test.
Future<void> _settle(
  WidgetTester tester,
  Finder target, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (target.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  // Dump what is on screen: a bare "not found" says nothing about which step
  // actually went wrong on a device.
  final onScreen = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .toList();
  fail('timed out waiting for $target; on screen: $onScreen');
}

/// Opens the card titled [title]. Taps target the card's ink well: a bare
/// `Text` does not take pointer events, so tapping the label can silently miss.
Future<void> _openCard(WidgetTester tester, String title) async {
  await tester.tap(
    find
        .ancestor(of: find.text(title).first, matching: find.byType(InkWell))
        .first,
  );
  await tester.pumpAndSettle();
}

Future<void> _addNode(WidgetTester tester, String title) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, title);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Create'));
  await _settle(tester, find.text(title));
}
