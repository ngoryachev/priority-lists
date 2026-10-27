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

void main() {
  test('load adopts the role stored for the account that just signed in',
      () async {
    final repository = _AccountScopedRepository(Role.father);
    final vm = RoleViewModel(repository: repository);
    await vm.load();
    expect(vm.selected, Role.father);

    // Sign out, sign in as somebody who picked a different role.
    repository.row = Role.myself;
    await vm.load();

    expect(vm.selected, Role.myself);
  });

  test('load clears the marker when the new account never picked a role',
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
  });

  test('a stored null never lingers as the previous selection', () async {
    final repository = _AccountScopedRepository(null);
    final vm = RoleViewModel(repository: repository);
    vm.select(Role.creator);
    // The pick wrote through, so a load after it legitimately returns creator.
    await vm.load();
    expect(vm.selected, Role.creator);
    expect(repository.row, Role.creator);
  });
}
