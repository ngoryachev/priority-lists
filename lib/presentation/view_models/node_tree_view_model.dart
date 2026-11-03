import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../data/services/activity_logger.dart';
import '../../domain/models/color_preset.dart';
import '../../domain/models/node_tree.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/priority_node.dart';
import '../../domain/repositories/priority_node_repository.dart';

/// Owns the whole priority tree.
///
/// One view model backs every level of the drill-down: screens are just a
/// window onto [tree] at a given parent id, so an edit made three levels deep
/// is immediately visible in the ancestor's chips without a reload.
class NodeTreeViewModel extends ChangeNotifier {
  final PriorityNodeRepository _repository;
  final Uuid _uuid;

  /// Records what the user changed, for the activity log. Optional and
  /// best-effort: it is absent in tests and before sign-in, and a log that
  /// fails never affects the mutation.
  final ActivityLogger? _logger;

  List<PriorityNode> _nodes = [];
  NodeTree _tree = NodeTree.empty();
  bool _isLoading = false;
  bool _isRefreshing = false;
  DateTime? _loadedAt;
  String? _error;

  /// How fresh the tree must be for [refresh] to skip the round-trip. Coming
  /// back to the foreground can fire several lifecycle events in a row.
  final Duration minRefreshAge;

  NodeTreeViewModel(
    this._repository, {
    Uuid? uuid,
    ActivityLogger? logger,
    this.minRefreshAge = const Duration(seconds: 2),
  })  : _uuid = uuid ?? const Uuid(),
        _logger = logger;

  NodeTree get tree => _tree;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _setNodes(await _repository.getAllNodes());
      _loadedAt = DateTime.now();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Quietly re-reads the tree, for when the app comes back to the
  /// foreground and another device may have written meanwhile. Unlike [load]
  /// it never flips [isLoading] (no spinner flash) and keeps the current tree
  /// on failure, so a flaky network can't blank a screen the user is reading.
  Future<void> refresh() async {
    if (_isLoading || _isRefreshing) return;
    final loadedAt = _loadedAt;
    if (loadedAt != null &&
        DateTime.now().difference(loadedAt) < minRefreshAge) {
      return;
    }
    _isRefreshing = true;
    try {
      _setNodes(await _repository.getAllNodes());
      _loadedAt = DateTime.now();
      notifyListeners();
    } catch (_) {
      // Stale data beats an empty screen; the next write or resume retries.
    } finally {
      _isRefreshing = false;
    }
  }

  /// Creates a child of [parentId] (top level when null) and returns it, or
  /// null if the write failed.
  Future<PriorityNode?> addChild({
    String? parentId,
    required String title,
    String description = '',
    required Priority priority,
    ColorPreset? colorPreset,
  }) async {
    final now = DateTime.now();
    final node = PriorityNode(
      id: _uuid.v4(),
      parentId: parentId,
      title: title,
      description: description,
      priority: priority,
      colorPreset: colorPreset,
      createdAt: now,
      updatedAt: now,
    );

    final saved = await _saveExclusive(
      node,
      now: now,
      // A node created as critical takes the red slot from its siblings.
      claimsCritical: priority == Priority.critical,
      log: (treeBefore) => _logger?.created(node, treeBefore),
    );
    return saved ? node : null;
  }

  Future<void> updateNode(PriorityNode node) async {
    final now = DateTime.now();
    final updated = node.copyWith(updatedAt: now);
    final before = _tree.nodeById(updated.id);
    await _saveExclusive(
      updated,
      now: now,
      // Only a node that *becomes* red evicts its siblings: re-saving one that
      // was red already (a rename, say) must leave the level alone.
      claimsCritical: updated.priority == Priority.critical &&
          before?.priority != Priority.critical,
      log: (treeBefore) {
        if (before != null) _logger?.changed(before, updated, treeBefore);
      },
    );
  }

  /// Deletes the node and everything under it.
  Future<void> deleteNode(String id) async {
    final doomed = {id, ..._tree.descendantsOf(id).map((n) => n.id)};
    final treeBefore = _tree;
    final node = treeBefore.nodeById(id);
    final deleted = await _write(() => _repository.deleteNode(id), () {
      _setNodes(_nodes.where((n) => !doomed.contains(n.id)).toList());
    });
    if (deleted && node != null) _logger?.deleted(node, treeBefore);
  }

  /// Re-parents a node, keeping its own subtree attached. Pass null to lift it
  /// back to the top level. Returns false when the move is impossible — into
  /// itself or into its own subtree, which would detach the tree from its root.
  Future<bool> moveNode(String id, String? newParentId) async {
    if (id == newParentId) return false;
    if (newParentId != null && _tree.isDescendantOf(newParentId, id)) {
      return false;
    }

    final node = _tree.nodeById(id);
    if (node == null) return false;
    if (node.parentId == newParentId) return true;

    final now = DateTime.now();
    final moved = node.withParent(newParentId, updatedAt: now);
    return _saveExclusive(
      moved,
      now: now,
      // A red node landing in a parent that already has one wins the slot.
      claimsCritical: moved.priority == Priority.critical,
      log: (treeBefore) => _logger?.moved(node, treeBefore, newParentId),
    );
  }

  /// Everything the node may be moved into, depth-first from the roots.
  List<PriorityNode> moveTargetsFor(String id) => _tree.moveTargetsFor(id);

  /// Applies a drag on one level.
  ///
  /// [visible] is the list as the user sees it — the priority filter may hide
  /// siblings, and those keep their place relative to the visible node they
  /// followed, so a filtered drag never silently reshuffles what is off-screen.
  ///
  /// A node dropped among a different priority adopts it, since the level is
  /// grouped by priority and it would otherwise snap back on the next rebuild.
  /// Landing exactly on the boundary of its own group keeps its priority.
  Future<bool> reorderChildren({
    required String? parentId,
    required List<PriorityNode> visible,
    required int oldIndex,
    required int newIndex,
  }) async {
    if (oldIndex < 0 || oldIndex >= visible.length) return false;
    // ReorderableListView reports the target index before the item is removed.
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (target == oldIndex) return true;

    final reordered = List.of(visible);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(target.clamp(0, reordered.length), moved);

    final landed = moved.copyWith(
      priority: _priorityAfterDrop(reordered, target, moved.priority),
    );
    reordered[target] = landed;

    final full = _weaveHiddenSiblings(parentId, visible, reordered);

    // Landing in the red group makes the node red, and red is exclusive: the
    // siblings that held it drop one level and follow the newcomer.
    final eviction = _evictCriticalSiblings(
      full,
      landed,
      claimsCritical: landed.priority == Priority.critical &&
          moved.priority != Priority.critical,
    );

    final now = DateTime.now();
    final changed = <PriorityNode>[];
    for (var i = 0; i < eviction.order.length; i++) {
      final node = eviction.order[i];
      final existing = _tree.nodeById(node.id)!;
      if (existing.position == i && existing.priority == node.priority) {
        continue;
      }
      changed.add(node.copyWith(position: i, updatedAt: now));
    }
    if (changed.isEmpty) return true;

    final byId = {for (final node in changed) node.id: node};
    final treeBefore = _tree;
    final saved = await _write(() => _repository.saveNodes(changed), () {
      _setNodes([for (final n in _nodes) byId[n.id] ?? n]);
    });
    if (saved) {
      // Logged from the on-screen ranks: the dragged node itself is often
      // absent from [changed] (its new index can equal the position it already
      // had), and the drag still happened.
      _logger?.reordered(
        landed,
        treeBefore,
        fromRank: oldIndex,
        toRank: target,
        previousPriority: moved.priority,
      );
      _logDisplaced(eviction.demoted, treeBefore, by: landed);
    }
    return saved;
  }

  /// The priority a dropped node takes on: its neighbours' when they agree,
  /// and its own when it landed on a boundary it already belongs to.
  Priority _priorityAfterDrop(
    List<PriorityNode> order,
    int index,
    Priority current,
  ) {
    final above = index > 0 ? order[index - 1].priority : null;
    final below = index < order.length - 1 ? order[index + 1].priority : null;
    if (above == null && below == null) return current;
    if (above == null) return below == current ? current : below!;
    if (below == null) return above == current ? current : above;
    if (above == below) return above;
    return current == above || current == below ? current : above;
  }

  /// Re-inserts siblings the filter hid, each straight after the visible node
  /// it used to follow (or at the front, if it led the level).
  List<PriorityNode> _weaveHiddenSiblings(
    String? parentId,
    List<PriorityNode> visibleBefore,
    List<PriorityNode> visibleAfter,
  ) {
    final visibleIds = {for (final node in visibleBefore) node.id};
    final leading = <PriorityNode>[];
    final trailing = <String, List<PriorityNode>>{};

    String? anchor;
    for (final node in _tree.childrenOf(parentId)) {
      if (visibleIds.contains(node.id)) {
        anchor = node.id;
      } else if (anchor == null) {
        leading.add(node);
      } else {
        trailing.putIfAbsent(anchor, () => []).add(node);
      }
    }

    return [
      ...leading,
      for (final node in visibleAfter) ...[node, ...?trailing[node.id]],
    ];
  }

  /// Saves [node] — new, edited or re-parented — and, when it claims the red
  /// slot of its level, the siblings that red slot belonged to.
  ///
  /// This is the single place that keeps a parent from ever showing two red
  /// children: with [claimsCritical] set, every sibling that was `critical`
  /// drops to `high` and is parked directly underneath [node], above the
  /// oranges that were already there. Sibling order is
  /// (priority, position, createdAt), so that placement means renumbering
  /// `position` across the whole level, exactly as a drag does — and the whole
  /// set goes out as one [PriorityNodeRepository.saveNodes] batch through
  /// [_write], so a rejected write reloads the tree instead of leaving half an
  /// eviction applied.
  ///
  /// [log] records the mutation that triggered all this; the demotions are
  /// logged after it.
  Future<bool> _saveExclusive(
    PriorityNode node, {
    required DateTime now,
    required bool claimsCritical,
    required void Function(NodeTree treeBefore) log,
  }) async {
    final level = [
      node,
      ..._tree.childrenOf(node.parentId).where((n) => n.id != node.id),
    ];
    final eviction =
        _evictCriticalSiblings(level, node, claimsCritical: claimsCritical);
    final treeBefore = _tree;

    if (eviction.demoted.isEmpty) {
      final saved = await _write(
        () => _repository.saveNode(node),
        () => _applyWrites([node]),
      );
      if (saved) log(treeBefore);
      return saved;
    }

    final changed = <PriorityNode>[];
    for (var i = 0; i < eviction.order.length; i++) {
      final sibling = eviction.order[i];
      final existing = _tree.nodeById(sibling.id);
      // [node] itself always goes: its save may carry a new title or colour
      // even when its place in the level is unchanged.
      if (sibling.id != node.id &&
          existing != null &&
          existing.position == i &&
          existing.priority == sibling.priority) {
        continue;
      }
      changed.add(sibling.copyWith(position: i, updatedAt: now));
    }

    final saved = await _write(
      () => _repository.saveNodes(changed),
      () => _applyWrites(changed),
    );
    if (saved) {
      log(treeBefore);
      _logDisplaced(eviction.demoted, treeBefore, by: node);
    }
    return saved;
  }

  /// Rewrites one level so that at most one child is `critical`.
  ///
  /// [level] is the level in sibling order with [red] already in it. When
  /// [claimsCritical] is false — [red] is not red, or was red before and so
  /// displaces nobody — the level comes back untouched and `demoted` is empty,
  /// which is the caller's signal that a plain single-node save will do.
  /// Otherwise the former reds drop one level and keep their relative order
  /// directly behind [red].
  ({List<PriorityNode> order, List<PriorityNode> demoted})
      _evictCriticalSiblings(
    List<PriorityNode> level,
    PriorityNode red, {
    required bool claimsCritical,
  }) {
    if (!claimsCritical) return (order: level, demoted: const []);

    final losers = [
      for (final n in level)
        if (n.id != red.id && n.priority == Priority.critical) n,
    ];
    if (losers.isEmpty) return (order: level, demoted: const []);

    final demoted = [
      for (final n in losers) n.copyWith(priority: Priority.high),
    ];
    final loserIds = {for (final n in losers) n.id};
    return (
      order: [
        red,
        ...demoted,
        for (final n in level)
          if (n.id != red.id && !loserIds.contains(n.id)) n,
      ],
      demoted: demoted,
    );
  }

  void _logDisplaced(
    List<PriorityNode> demoted,
    NodeTree treeBefore, {
    required PriorityNode by,
  }) {
    for (final node in demoted) {
      final before = treeBefore.nodeById(node.id);
      if (before != null) _logger?.displaced(before, node, treeBefore, by: by);
    }
  }

  /// Folds written nodes back into the in-memory list, appending the ones that
  /// are new.
  void _applyWrites(List<PriorityNode> written) {
    final byId = {for (final node in written) node.id: node};
    final merged = [for (final n in _nodes) byId.remove(n.id) ?? n];
    _setNodes([...merged, ...byId.values]);
  }

  void _setNodes(List<PriorityNode> nodes) {
    _nodes = nodes;
    _tree = NodeTree(nodes);
  }

  /// Applies a change locally only once the repository accepted it; on failure
  /// the tree is re-read so the UI can never drift from storage.
  Future<bool> _write(
    Future<void> Function() write,
    void Function() applyLocally,
  ) async {
    try {
      await write();
      applyLocally();
      _error = null;
      notifyListeners();
      return true;
    } catch (e) {
      final failure = e.toString();
      // Re-read so the UI matches storage, then restore the message: load()
      // clears _error on success and the failure must stay visible.
      await load();
      _error = failure;
      notifyListeners();
      return false;
    }
  }
}
