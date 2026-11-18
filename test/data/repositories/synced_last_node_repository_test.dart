import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/in_memory_last_node_repository.dart';
import 'package:priority_lists/data/repositories/synced_last_node_repository.dart';
import 'package:priority_lists/domain/repositories/last_node_repository.dart';

class _Failing implements LastNodeRepository {
  @override
  Future<LastNodePointer?> load() => throw StateError('offline');

  @override
  Future<void> save(LastNodePointer pointer) => throw StateError('offline');

  @override
  Future<void> clear() => throw StateError('offline');
}

void main() {
  const here = LastNodePointer(userId: 'u', nodeId: 'here');
  const there = LastNodePointer(userId: 'u', nodeId: 'there');

  test('the server wins over this device', () async {
    final repo = SyncedLastNodeRepository(
      remote: InMemoryLastNodeRepository(there),
      local: InMemoryLastNodeRepository(here),
    );
    expect(await repo.load(), there);
  });

  test(
    'a server that never stored anything falls back to the device',
    () async {
      final repo = SyncedLastNodeRepository(
        remote: InMemoryLastNodeRepository(),
        local: InMemoryLastNodeRepository(here),
      );
      expect(await repo.load(), here);
    },
  );

  test('a server that cannot be read falls back to the device', () async {
    final repo = SyncedLastNodeRepository(
      remote: _Failing(),
      local: InMemoryLastNodeRepository(here),
    );
    expect(await repo.load(), here);
  });

  test('a save reaches both, the device even when the server fails', () async {
    final remote = InMemoryLastNodeRepository();
    final local = InMemoryLastNodeRepository();
    await SyncedLastNodeRepository(remote: remote, local: local).save(there);
    expect(await remote.load(), there);
    expect(await local.load(), there);

    final offlineLocal = InMemoryLastNodeRepository();
    await expectLater(
      SyncedLastNodeRepository(
        remote: _Failing(),
        local: offlineLocal,
      ).save(here),
      throwsStateError,
    );
    expect(await offlineLocal.load(), here);
  });
}
