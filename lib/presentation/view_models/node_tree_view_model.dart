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

    final treeBefore = _tree;
    final saved = await _write(() => _repository.saveNode(node), () {
      _setNodes([..._nodes, node]);
    });
    if (saved) _logger?.created(node, treeBefore);
    return saved ? node : null;
  }

  Future<void> updateNode(PriorityNode node) async {
    final updated = node.copyWith(updatedAt: DateTime.now());
    final treeBefore = _tree;
    final before = treeBefore.nodeById(updated.id);
    final saved = await _write(() => _repository.saveNode(updated), () {
      _setNodes([
        for (final n in _nodes)
          if (n.id == updated.id) updated else n,
      ]);
    });
    if (saved && before != null) {
      _logger?.changed(before, updated, treeBefore);
    }
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

    final moved = node.withParent(newParentId, updatedAt: DateTime.now());
    final treeBefore = _tree;
    final saved = await _write(() => _repository.saveNode(moved), () {
      _setNodes([
        for (final n in _nodes)
          if (n.id == moved.id) moved else n,
      ]);
    });
    if (saved) _logger?.moved(node, treeBefore, newParentId);
    return saved;
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

    final now = DateTime.now();
    final changed = <PriorityNode>[];
    for (var i = 0; i < full.length; i++) {
      final node = full[i];
      final existing = _tree.nodeById(node.id)!;
      if (existing.position == i && existing.priority == node.priority) {
        continue;
      }
      changed.add(node.copyWith(position: i, updatedAt: now));
    }
    if (changed.isEmpty) return true;

    final byId = {for (final node in changed) node.id: node};
    final treeBefore = _tree;
    final draggedBefore = treeBefore.nodeById(moved.id);
    final saved = await _write(() => _repository.saveNodes(changed), () {
      _setNodes([for (final n in _nodes) byId[n.id] ?? n]);
    });
    final draggedAfter = byId[moved.id];
    if (saved && draggedBefore != null && draggedAfter != null) {
      _logger?.reordered(draggedBefore, draggedAfter, treeBefore);
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
