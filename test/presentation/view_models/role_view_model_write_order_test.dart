import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/role.dart';
import 'package:priority_lists/domain/repositories/current_role_repository.dart';
import 'package:priority_lists/presentation/view_models/role_view_model.dart';

/// A store that behaves like a remote one: a read answers with the row as it
/// stood when the query was issued, and the first write is held open so it can
/// be left in flight the way a slow round-trip would be.
class _RemoteLikeRepository implements CurrentRoleRepository {
  Role? row;

  /// Released by the test, to let the first write land.
  final firstWrite = Completer<void>();

  /// Released by the test, to let a read answer.
  Completer<void>? readGate;

  final List<Role> writes = [];
  bool _seenFirstWrite = false;

  @override
  Future<Role?> load() async {
    // What the server holds when the query leaves: a read overtaken by a
    // later write still answers with the older row.
    final answer = row;
    final gate = readGate;
    if (gate != null) await gate.future;
    return answer;
  }

  @override
  Future<void> save(Role role) async {
    if (!_seenFirstWrite) {
      _seenFirstWrite = true;
      await firstWrite.future;
    }
    writes.add(role);
    row = role;
  }
}

void main() {
  test(
    'a pick made while load is waiting for an earlier write is not reverted',
    () async {
      final repository = _RemoteLikeRepository();
      final vm = RoleViewModel(repository: repository);

      // A pick whose write is still on the wire.
      vm.select(Role.father);
      await pumpEventQueue();

      // The account is re-read (a re-mount of the root screen) while that
      // write is in flight, and the read itself is slow.
      repository.readGate = Completer<void>();
      final loading = vm.load();
      await pumpEventQueue();

      // The user taps another chip before anything has come back.
      vm.select(Role.creator);
      await pumpEventQueue();

      // The first write lands, which releases `load`; then the read answers.
      repository.firstWrite.complete();
      await pumpEventQueue();
      repository.readGate!.complete();
      await loading;
      await vm.idle;

      expect(repository.writes, [Role.father, Role.creator]);
      expect(repository.row, Role.creator);
      expect(
        vm.selected,
        Role.creator,
        reason: 'the newest tap must win over a read it raced',
      );
    },
  );
}
