import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/role.dart';
import 'package:priority_lists/domain/repositories/current_role_repository.dart';
import 'package:priority_lists/presentation/view_models/role_view_model.dart';

/// A store whose write can be left in flight and whose row is empty: acts out
/// a sign-in to an account that never picked a role, while the previous
/// account's upsert is still on the wire.
class _EmptyStoreWithHeldWrite implements CurrentRoleRepository {
  Role? row;

  /// Released by the test, to let the held write land.
  final heldWrite = Completer<void>();

  final List<Role> writes = [];
  bool _seenFirstWrite = false;

  @override
  Future<Role?> load() async => row;

  @override
  Future<void> save(Role role) async {
    if (!_seenFirstWrite) {
      _seenFirstWrite = true;
      await heldWrite.future;
    }
    writes.add(role);
    row = role;
  }
}

/// Account-scoped, the way the Supabase repository is: a read answers for
/// whoever is signed in now, while a write already on the wire still carries
/// the row it was issued against.
class _AccountScopedHeldWrite implements CurrentRoleRepository {
  final Map<int, Role?> _rows = {};
  int _account = 0;

  final heldWrite = Completer<void>();
  bool _seenFirstWrite = false;

  void signInAsSomebodyNew() => _account++;

  @override
  Future<Role?> load() async => _rows[_account];

  @override
  Future<void> save(Role role) async {
    final account = _account;
    if (!_seenFirstWrite) {
      _seenFirstWrite = true;
      await heldWrite.future;
    }
    _rows[account] = role;
  }
}

void main() {
  // `load()` awaits the write queue before reading, so a tap can land during
  // that wait. The pick counter is snapshotted before the await for exactly
  // this reason; when the read then comes back empty the clearing branch is
  // the one that has to be skipped, otherwise the bar goes blank under a
  // finger that just picked something.
  test(
    'a pick made while load waits for an earlier write survives an empty read',
    () async {
      final repository = _EmptyStoreWithHeldWrite();
      final vm = RoleViewModel(repository: repository);

      // The previous account's pick, whose write is still on the wire.
      vm.select(Role.father);
      await pumpEventQueue();

      // The root screen re-mounts for the new account and re-reads.
      final loading = vm.load();
      await pumpEventQueue();

      // The user picks a role before that read could come back.
      vm.select(Role.creator);
      await pumpEventQueue();

      var notifications = 0;
      vm.addListener(() => notifications++);

      // The held write lands, which releases `load`, and the read answers
      // with the empty row the new account has.
      repository.heldWrite.complete();
      await loading;
      await vm.idle;

      expect(
        vm.selected,
        Role.creator,
        reason: 'the tap is newer than the read it raced',
      );
      expect(
        notifications,
        0,
        reason: 'load must not notify a selection it did not change',
      );
      expect(repository.writes, [Role.father, Role.creator]);
      expect(repository.row, Role.creator);
    },
  );

  // The counterpart: with no tap in the window, a read that answers for a
  // different account must still clear the previous marker. Moving the
  // snapshot earlier must not have made the guard fire where there was
  // nothing to protect.
  test(
    'without a tap the read still clears the previous account marker',
    () async {
      final repository = _AccountScopedHeldWrite();
      final vm = RoleViewModel(repository: repository);

      // Account A picks, and the upsert is left on the wire.
      vm.select(Role.father);
      await pumpEventQueue();

      // Sign out, sign in as somebody who never picked. The root screen
      // re-mounts and re-reads while A's write is still pending.
      repository.signInAsSomebodyNew();
      final loading = vm.load();
      await pumpEventQueue();

      repository.heldWrite.complete();
      await loading;
      await vm.idle;

      expect(
        vm.selected,
        isNull,
        reason: 'the account that just signed in never picked a role',
      );
    },
  );
}
