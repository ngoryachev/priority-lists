import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_priority_node_repository.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';
import 'package:priority_lists/domain/models/role.dart';
import 'package:priority_lists/domain/repositories/current_role_repository.dart';
import 'package:priority_lists/domain/repositories/priority_node_repository.dart';
import 'package:priority_lists/presentation/screens/node_screen.dart';
import 'package:priority_lists/presentation/view_models/filter_view_model.dart';
import 'package:priority_lists/presentation/view_models/node_tree_view_model.dart';
import 'package:priority_lists/presentation/view_models/role_view_model.dart';
import 'package:provider/provider.dart';

/// The cross-account fix rests on a claim about the widget tree, not just on
/// `RoleViewModel`: that signing out and back in unmounts the root
/// `NodeScreen` while the view model — registered above `MaterialApp` — keeps
/// living, so `initState` runs `load()` again and the new account's (possibly
/// empty) row reaches the chips. These tests exercise that through the real
/// screen rather than the view model alone.

/// Answers for whoever is signed in right now, the way the Supabase
/// repository does by reading `auth.currentUser` on every call.
class _AccountScopedRepository implements CurrentRoleRepository {
  Role? row;

  _AccountScopedRepository(this.row);

  @override
  Future<Role?> load() async => row;

  @override
  Future<void> save(Role role) async => row = role;
}

PriorityNode node(String id) {
  final created = DateTime(2026, 1, 1);
  return PriorityNode(
    id: id,
    parentId: null,
    title: id,
    description: '',
    priority: Priority.critical,
    createdAt: created,
    updatedAt: created,
  );
}

Future<PriorityNodeRepository> seeded() async {
  final repository = InMemoryPriorityNodeRepository();
  await repository.saveNodes([node('Root')]);
  return repository;
}

/// Stands in for `AuthGate`: the role view model sits above, the tree
/// providers and the root screen below, and `signedIn` flips the way
/// `AuthViewModel.isAuthenticated` does on sign-out / sign-in.
class _Harness extends StatefulWidget {
  final PriorityNodeRepository repository;
  final RoleViewModel roles;

  const _Harness({super.key, required this.repository, required this.roles});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool signedIn = true;

  void setSignedIn(bool value) => setState(() => signedIn = value);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<RoleViewModel>.value(
      value: widget.roles,
      child: MaterialApp(
        home: signedIn
            ? MultiProvider(
                providers: [
                  Provider<PriorityNodeRepository>.value(
                    value: widget.repository,
                  ),
                  ChangeNotifierProvider(
                    create: (_) => NodeTreeViewModel(widget.repository),
                  ),
                  ChangeNotifierProvider(create: (_) => FilterViewModel()),
                ],
                child: const NodeScreen(),
              )
            : const Scaffold(body: Center(child: Text('Login'))),
      ),
    );
  }
}

/// The roles the visible bar paints as active.
List<Role> activeRoles(WidgetTester tester) {
  final active = <Role>[];
  for (final role in Role.values) {
    final chip = tester.widget<ChoiceChip>(
      find
          .ancestor(
            of: find.text(role.label),
            matching: find.byType(ChoiceChip),
          )
          .first,
    );
    if (chip.selected) active.add(role);
  }
  return active;
}

Future<void> tapRole(WidgetTester tester, Role role) async {
  final label = find.text(role.label).first;
  await tester.ensureVisible(label);
  await tester.pumpAndSettle();
  await tester.tap(label);
  await tester.pumpAndSettle();
}

Future<void> _switchAccount(
  WidgetTester tester,
  GlobalKey<_HarnessState> key,
) async {
  key.currentState!.setSignedIn(false);
  await tester.pumpAndSettle();
  key.currentState!.setSignedIn(true);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a new account with no stored role sees no chip selected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = _AccountScopedRepository(null);
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(
        key: key,
        repository: await seeded(),
        roles: RoleViewModel(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    await tapRole(tester, Role.father);
    expect(activeRoles(tester), [Role.father]);
    expect(repository.row, Role.father);

    // Sign out; the next account never picked a role.
    repository.row = null;
    await _switchAccount(tester, key);

    expect(
      activeRoles(tester),
      isEmpty,
      reason: "the previous account's role is still painted as current",
    );
  });

  testWidgets('a new account sees its own stored role, not the previous one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repository = _AccountScopedRepository(null);
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(
        key: key,
        repository: await seeded(),
        roles: RoleViewModel(repository: repository),
      ),
    );
    await tester.pumpAndSettle();

    await tapRole(tester, Role.father);
    repository.row = Role.myself;
    await _switchAccount(tester, key);

    expect(activeRoles(tester), [Role.myself]);
  });

  testWidgets('a broken store keeps the signed-in pick for the session', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Migration 005 not applied: every call throws, so nothing is ever read
    // back and the pick must simply survive as an in-memory marker.
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(
        key: key,
        repository: await seeded(),
        roles: RoleViewModel(repository: _ThrowingRepository()),
      ),
    );
    await tester.pumpAndSettle();

    await tapRole(tester, Role.creator);

    expect(activeRoles(tester), [Role.creator]);
    expect(tester.takeException(), isNull);
  });
}

class _ThrowingRepository implements CurrentRoleRepository {
  @override
  Future<Role?> load() async =>
      throw StateError('relation "user_role" does not exist');

  @override
  Future<void> save(Role role) async =>
      throw StateError('relation "user_role" does not exist');
}
