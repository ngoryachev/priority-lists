import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_current_role_repository.dart';
import 'package:priority_lists/domain/models/role.dart';
import 'package:priority_lists/domain/repositories/current_role_repository.dart';
import 'package:priority_lists/presentation/view_models/role_view_model.dart';

/// A store whose first write is slow, to act out two taps in quick succession
/// over a network: unordered, the second write would land before the first.
class _SlowFirstWriteRepository implements CurrentRoleRepository {
  final List<Role> writes = [];
  bool _firstWrite = true;

  @override
  Future<Role?> load() async => writes.isEmpty ? null : writes.last;

  @override
  Future<void> save(Role role) async {
    if (_firstWrite) {
      _firstWrite = false;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    writes.add(role);
  }
}

/// A store whose read can be held open, to act out a slow round-trip.
class _GatedRepository implements CurrentRoleRepository {
  Role? stored;
  final gate = Completer<void>();

  _GatedRepository(this.stored);

  @override
  Future<Role?> load() async {
    await gate.future;
    return stored;
  }

  @override
  Future<void> save(Role role) async => stored = role;
}

/// A stack where migration 005 has not been applied yet: every call throws.
class _BrokenRepository implements CurrentRoleRepository {
  int loads = 0;
  int saves = 0;

  @override
  Future<Role?> load() async {
    loads++;
    throw StateError('relation "user_role" does not exist');
  }

  @override
  Future<void> save(Role role) async {
    saves++;
    throw StateError('relation "user_role" does not exist');
  }
}

void main() {
  test('nothing is selected before the user picks', () {
    final vm = RoleViewModel();
    expect(vm.selected, isNull);
    for (final role in Role.values) {
      expect(vm.isSelected(role), isFalse);
    }
  });

  test('select notifies once and writes through', () async {
    final repository = InMemoryCurrentRoleRepository();
    final vm = RoleViewModel(repository: repository);
    var notifications = 0;
    vm.addListener(() => notifications++);

    vm.select(Role.partner);

    expect(vm.selected, Role.partner);
    expect(vm.isSelected(Role.partner), isTrue);
    expect(notifications, 1);
    await vm.idle;
    expect(await repository.load(), Role.partner);
  });

  test('two quick picks are written in the order they were made', () async {
    final repository = _SlowFirstWriteRepository();
    final vm = RoleViewModel(repository: repository);

    vm.select(Role.father);
    vm.select(Role.creator);
    await vm.idle;

    // Unchained, the fast second write would land first and the row would end
    // up holding the role the user moved away from.
    expect(repository.writes, [Role.father, Role.creator]);
    expect(await repository.load(), Role.creator);
    expect(vm.selected, Role.creator);
  });

  test('selecting another role replaces the previous one', () {
    final vm = RoleViewModel();
    vm.select(Role.partner);
    vm.select(Role.creator);

    expect(vm.selected, Role.creator);
    expect(vm.isSelected(Role.partner), isFalse);
    // Exactly one role is active at a time.
    expect(Role.values.where(vm.isSelected), [Role.creator]);
  });

  test('re-selecting the active role neither notifies nor writes', () async {
    final repository = InMemoryCurrentRoleRepository();
    final vm = RoleViewModel(repository: repository);
    vm.select(Role.father);
    await Future<void>.delayed(Duration.zero);

    var notifications = 0;
    vm.addListener(() => notifications++);
    vm.select(Role.father);

    expect(notifications, 0);
    expect(vm.selected, Role.father);
  });

  test('load restores a stored role and notifies', () async {
    final repository = InMemoryCurrentRoleRepository();
    await repository.save(Role.lifeOwner);
    final vm = RoleViewModel(repository: repository);
    var notifications = 0;
    vm.addListener(() => notifications++);

    await vm.load();

    expect(vm.selected, Role.lifeOwner);
    expect(notifications, 1);
  });

  test('load of an empty store leaves no selection and does not notify',
      () async {
    final vm = RoleViewModel(repository: InMemoryCurrentRoleRepository());
    var notifications = 0;
    vm.addListener(() => notifications++);

    await vm.load();

    expect(vm.selected, isNull);
    expect(notifications, 0);
  });

  test('a pick made during a slow load is not reverted by it', () async {
    final repository = _GatedRepository(Role.father);
    final vm = RoleViewModel(repository: repository);

    final loading = vm.load();
    // The user taps before the read comes back.
    vm.select(Role.creator);
    repository.gate.complete();
    await loading;
    await vm.idle;

    expect(vm.selected, Role.creator);
    expect(repository.stored, Role.creator);
  });

  test('a failing repository leaves the view model usable', () async {
    final repository = _BrokenRepository();
    final vm = RoleViewModel(repository: repository);

    await vm.load();
    expect(vm.selected, isNull);
    expect(repository.loads, 1);

    // The failing save must not surface over the tree, and the pick still
    // holds for this session.
    vm.select(Role.myself);
    await vm.idle;
    expect(vm.selected, Role.myself);
    expect(repository.saves, 1);
  });

  test('works with no repository at all', () async {
    final vm = RoleViewModel();
    await vm.load();
    vm.select(Role.professional);
    expect(vm.selected, Role.professional);
  });
}
