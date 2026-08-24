import 'priority_node.dart';

/// An immutable index over a flat list of [PriorityNode]s.
///
/// The repositories hand back the whole tree as a flat list; this class is what
/// turns it into something navigable — children per parent, ancestor paths for
/// breadcrumbs, subtree sizes, and the ancestor checks that keep a move from
/// creating a cycle.
///
/// A node whose [PriorityNode.parentId] points at something missing is treated
/// as a root, so a partially-loaded or inconsistent list can never hide nodes.
class NodeTree {
  final List<PriorityNode> nodes;

  final Map<String, PriorityNode> _byId;
  final Map<String?, List<PriorityNode>> _childrenByParent;

  NodeTree._(this.nodes, this._byId, this._childrenByParent);

  factory NodeTree(Iterable<PriorityNode> nodes) {
    final all = List<PriorityNode>.unmodifiable(nodes);
    final byId = {for (final node in all) node.id: node};
    final childrenByParent = <String?, List<PriorityNode>>{};

    for (final node in all) {
      final parentId = node.parentId != null && byId.containsKey(node.parentId)
          ? node.parentId
          : null;
      childrenByParent.putIfAbsent(parentId, () => []).add(node);
    }

    for (final siblings in childrenByParent.values) {
      siblings.sort(_bySiblingOrder);
    }

    return NodeTree._(all, byId, childrenByParent);
  }

  factory NodeTree.empty() => NodeTree(const []);

  /// Most urgent first, then the manual order the user dragged into, and
  /// finally age — so siblings never reshuffle on their own.
  static int _bySiblingOrder(PriorityNode a, PriorityNode b) {
    final byPriority = a.priority.value.compareTo(b.priority.value);
    if (byPriority != 0) return byPriority;
    final byPosition = a.position.compareTo(b.position);
    if (byPosition != 0) return byPosition;
    return a.createdAt.compareTo(b.createdAt);
  }

  bool get isEmpty => nodes.isEmpty;
  bool get isNotEmpty => nodes.isNotEmpty;

  List<PriorityNode> get roots => childrenOf(null);

  /// Direct children of [parentId], sorted; `null` yields the top level.
  List<PriorityNode> childrenOf(String? parentId) =>
      List.unmodifiable(_childrenByParent[parentId] ?? const []);

  PriorityNode? nodeById(String? id) => id == null ? null : _byId[id];

  bool hasChildren(String id) => (_childrenByParent[id] ?? const []).isNotEmpty;

  int childCount(String id) => (_childrenByParent[id] ?? const []).length;

  /// Root-to-node chain including the node itself; empty if [id] is unknown.
  List<PriorityNode> pathTo(String? id) {
    final path = <PriorityNode>[];
    final seen = <String>{};
    var current = nodeById(id);
    while (current != null && seen.add(current.id)) {
      path.add(current);
      current = nodeById(current.parentId);
    }
    return List.unmodifiable(path.reversed.toList());
  }

  /// Zero for a root node, one for its children, and so on.
  int depthOf(String id) {
    final path = pathTo(id);
    return path.isEmpty ? 0 : path.length - 1;
  }

  /// Every node below [id], in depth-first order.
  List<PriorityNode> descendantsOf(String id) {
    final result = <PriorityNode>[];
    final queue = <String>[id];
    final seen = <String>{id};
    while (queue.isNotEmpty) {
      for (final child in _childrenByParent[queue.removeLast()] ?? const []) {
        if (seen.add(child.id)) {
          result.add(child);
          queue.add(child.id);
        }
      }
    }
    return List.unmodifiable(result);
  }

  int descendantCount(String id) => descendantsOf(id).length;

  /// True when [candidateId] sits anywhere below [ancestorId].
  bool isDescendantOf(String candidateId, String ancestorId) {
    final seen = <String>{};
    var current = nodeById(candidateId)?.parentId;
    while (current != null && seen.add(current)) {
      if (current == ancestorId) return true;
      current = nodeById(current)?.parentId;
    }
    return false;
  }

  /// Destinations a node may legally move to: anything but itself and its own
  /// subtree (moving into those would detach the tree or make a cycle).
  /// Depth-first from the roots, so the caller can indent the list as a tree.
  List<PriorityNode> moveTargetsFor(String id) {
    final result = <PriorityNode>[];
    void walk(String? parentId) {
      for (final node in childrenOf(parentId)) {
        if (node.id == id) continue;
        result.add(node);
        walk(node.id);
      }
    }

    walk(null);
    return List.unmodifiable(result);
  }
}
