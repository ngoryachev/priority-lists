import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

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

  List<PriorityNode> _nodes = [];
  NodeTree _tree = NodeTree.empty();
  bool _isLoading = false;
  String? _error;

  NodeTreeViewModel(this._repository, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  NodeTree get tree => _tree;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _setNodes(await _repository.getAllNodes());
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
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

    final saved = await _write(() => _repository.saveNode(node), () {
      _setNodes([..._nodes, node]);
    });
    return saved ? node : null;
  }

  Future<void> updateNode(PriorityNode node) async {
    final updated = node.copyWith(updatedAt: DateTime.now());
    await _write(() => _repository.saveNode(updated), () {
      _setNodes([
        for (final n in _nodes) if (n.id == updated.id) updated else n,
      ]);
    });
  }

  /// Deletes the node and everything under it.
  Future<void> deleteNode(String id) async {
    final doomed = {id, ..._tree.descendantsOf(id).map((n) => n.id)};
    await _write(() => _repository.deleteNode(id), () {
      _setNodes(_nodes.where((n) => !doomed.contains(n.id)).toList());
    });
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
    return _write(() => _repository.saveNode(moved), () {
      _setNodes([
        for (final n in _nodes) if (n.id == moved.id) moved else n,
      ]);
    });
  }

  /// Everything the node may be moved into, depth-first from the roots.
  List<PriorityNode> moveTargetsFor(String id) => _tree.moveTargetsFor(id);

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
