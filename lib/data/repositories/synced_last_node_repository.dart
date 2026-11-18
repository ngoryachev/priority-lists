import '../../domain/repositories/last_node_repository.dart';

/// The last opened node on the server, with this device's copy as a fallback.
///
/// The server is the answer whenever it has one, which is what makes another
/// device's position win. The local copy only steps in when the server cannot
/// be read (offline, the table not migrated yet) or has never been written,
/// so a device keeps reopening where it was even then.
class SyncedLastNodeRepository implements LastNodeRepository {
  final LastNodeRepository remote;
  final LastNodeRepository local;

  SyncedLastNodeRepository({required this.remote, required this.local});

  @override
  Future<LastNodePointer?> load() async {
    try {
      final pointer = await remote.load();
      if (pointer != null) return pointer;
    } catch (_) {
      // Fall through to the local copy.
    }
    return local.load();
  }

  /// Both are written; the local write goes first so a failing server does
  /// not cost the device its own copy. The server's failure is still reported.
  @override
  Future<void> save(LastNodePointer pointer) async {
    await local.save(pointer);
    await remote.save(pointer);
  }

  @override
  Future<void> clear() async {
    await local.clear();
    await remote.clear();
  }
}
