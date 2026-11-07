import '../../domain/models/node_tree.dart';
import '../../domain/models/priority_node.dart';
import '../../domain/repositories/last_node_repository.dart';

/// Remembers which level the user is on, and decides what to reopen on launch.
///
/// Not a [ChangeNotifier]: nothing on screen is driven by this value. It is a
/// side record, like the current role — the screens write to it as the user
/// moves, and the root screen reads it exactly once, when the tree has loaded.
///
/// Persistence is best-effort throughout. A settings store that throws, holds
/// a value from another account, or points at a node that is gone all mean the
/// same thing: open at the root. Nothing here may surface an error over the
/// tree.
class LastNodeViewModel {
  final LastNodeRepository? _repository;

  /// Read lazily, not captured: this view model is registered above the
  /// `MaterialApp` and so outlives a sign-out, and the pointer belongs to
  /// whoever is signed in at the moment of the write.
  final String? Function() _currentUserId;

  /// Writes are chained, like `RoleViewModel`'s: a breadcrumb jump pops
  /// several levels in one go, and unordered those writes can leave an
  /// intermediate level stored while the user is looking at the crumb they
  /// tapped.
  Future<void> _queue = Future.value();

  LastNodeViewModel({
    LastNodeRepository? repository,
    required String? Function() currentUserId,
  })  : _repository = repository,
        _currentUserId = currentUserId;

  /// Completes once every level change recorded so far has been written (or
  /// failed). For tests, and for [resolveRestorePath] to avoid reading across
  /// its own pending write.
  Future<void> get idle => _queue;

  /// Records that the user is now looking at [nodeId]'s level; null = root.
  ///
  /// Fire and forget: the screen has already changed, and a pointer that
  /// cannot be stored only means the next launch opens at the root.
  void remember(String? nodeId) {
    final repository = _repository;
    if (repository == null) return;
    final userId = _currentUserId();
    // No signed-in user means no pointer to scope: skip rather than store a
    // value the account check could never match.
    if (userId == null) return;
    final pointer = LastNodePointer(userId: userId, nodeId: nodeId);
    _queue = _queue
        .then((_) => repository.save(pointer))
        .catchError((_) {});
  }

  /// The levels to reopen, root-first and excluding the top level itself —
  /// empty when the app should just stay at the root.
  ///
  /// Called once [NodeTreeViewModel.load] has produced [tree], since the
  /// pointer is only usable against a tree that is actually there.
  Future<List<PriorityNode>> resolveRestorePath(NodeTree tree) async {
    final repository = _repository;
    if (repository == null) return const [];
    // Let a pending write land first: reading across our own in-flight save
    // would hand back the previous level.
    await _queue;
    final LastNodePointer? pointer;
    try {
      pointer = await repository.load();
    } catch (_) {
      return const [];
    }
    if (pointer == null) return const [];
    final nodeId = pointer.nodeId;
    if (nodeId == null) return const [];
    // Nobody signed in is not "somebody else's pointer": a sign-out landing
    // between the mount and this read must not cost the user their pointer.
    // `remember` takes the same stance and skips the write.
    final userId = _currentUserId();
    if (userId == null) return const [];
    // Somebody else's pointer, or one pointing at a node that was deleted (or
    // orphaned out of reach): drop it rather than keep retrying it on every
    // launch. An orphan whose parent is missing needs no special case —
    // `NodeTree` treats it as a root, so `pathTo` yields its single-node path.
    if (pointer.userId != userId) {
      _forget();
      return const [];
    }
    final path = tree.pathTo(nodeId);
    if (path.isEmpty) {
      _forget();
      return const [];
    }
    return path;
  }

  /// Best-effort clear, chained behind the pending writes like [remember] so
  /// it cannot race them.
  void _forget() {
    final repository = _repository;
    if (repository == null) return;
    _queue = _queue.then((_) => repository.clear()).catchError((_) {});
  }
}
