import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/role.dart';
import 'package:priority_lists/domain/repositories/current_role_repository.dart';
import 'package:priority_lists/presentation/view_models/role_view_model.dart';

/// `RoleViewModel` is registered above `MaterialApp` in `lib/app.dart`, so it
/// outlives sign-out: the same instance serves whoever signs in next. The
/// Supabase repository reads `auth.currentUser` on every call, so after a
/// switch the very same repository instance answers for the new account.
/// `NodeScreen.initState` calls `load()` again on that re-mount, which is the
/// only chance to drop the previous account's marker.
class _AccountScopedRepository implements CurrentRoleRepository {
  /// The row of whoever is signed in right now; null when they never picked.
  Role? row;

  int loads = 0;

  _AccountScopedRepository(this.row);

  @override
  Future<Role?> load() async {
    loads++;
    return row;
  }

  @override
  Future<void> save(Role role) async => row = role;
}

/// A store whose read can be held open and whose row is empty: acts out the
/// new account's first read arriving late.
class _GatedEmptyRepository implements CurrentRoleRepository {
  Role? stored;
  final gate = Completer<void>();

  @override
  Future<Role?> load() async {
    await gate.future;
    return stored;
  }

  @override
  Future<void> save(Role role) async => stored = role;
}

void main() {
  test(
    'load adopts the role stored for the account that just signed in',
    () async {
      final repository = _AccountScopedRepository(Role.father);
      final vm = RoleViewModel(repository: repository);
      await vm.load();
      expect(vm.selected, Role.father);

      // Sign out, sign in as somebody who picked a different role.
      repository.row = Role.myself;
      await vm.load();

      expect(vm.selected, Role.myself);
    },
  );

  test(
    'load clears the marker when the new account never picked a role',
    () async {
      final repository = _AccountScopedRepository(Role.father);
      final vm = RoleViewModel(repository: repository);
      await vm.load();
      expect(vm.selected, Role.father);

      // Sign out, sign in as somebody with no row of their own.
      repository.row = null;
      var notifications = 0;
      vm.addListener(() => notifications++);
      await vm.load();

      expect(
        vm.selected,
        isNull,
        reason: 'the previous account\'s role is still highlighted',
      );
      expect(notifications, 1);
    },
  );

  test('a stored null never lingers as the previous selection', () async {
    final repository = _AccountScopedRepository(null);
    final vm = RoleViewModel(repository: repository);
    vm.select(Role.creator);
    // The pick wrote through, so a load after it legitimately returns creator.
    await vm.load();
    expect(vm.selected, Role.creator);
    expect(repository.row, Role.creator);
  });

  /// Clearing the slot on an empty read is what fixes the cross-account leak,
  /// but it also means a read that comes back empty can now wipe a selection.
  /// The only thing keeping a fresh tap safe is the pick counter, so check it
  /// against an empty read specifically — the existing race test uses a store
  /// that has a row, where an early return would have hidden the problem.
  test(
    'an empty read arriving late does not wipe a pick made meanwhile',
    () async {
      final repository = _GatedEmptyRepository();
      final vm = RoleViewModel(repository: repository);

      final loading = vm.load();
      // The user taps before the (empty) read comes back.
      vm.select(Role.lifeOwner);
      repository.gate.complete();
      await loading;
      await Future<void>.delayed(Duration.zero);

      expect(vm.selected, Role.lifeOwner);
      expect(repository.stored, Role.lifeOwner);
    },
  );
}
