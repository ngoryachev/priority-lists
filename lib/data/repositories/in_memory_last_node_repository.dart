import '../../domain/repositories/last_node_repository.dart';

/// Last-node storage for tests and for entry points without local settings.
/// Lives only as long as the process does.
class InMemoryLastNodeRepository implements LastNodeRepository {
  LastNodePointer? _pointer;

  /// The optional seed stands in for "the app was last closed here", which is
  /// what a test needs to exercise a restore.
  InMemoryLastNodeRepository([this._pointer]);

  @override
  Future<LastNodePointer?> load() async => _pointer;

  @override
  Future<void> save(LastNodePointer pointer) async => _pointer = pointer;

  @override
  Future<void> clear() async => _pointer = null;
}
