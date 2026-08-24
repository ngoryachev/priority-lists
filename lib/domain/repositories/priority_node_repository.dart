import '../models/priority_node.dart';

/// Storage for the priority tree.
///
/// Nodes are read and written individually — the tree is a flat list of rows
/// linked by `parentId`, not a nested aggregate, so an edit deep inside it never
/// rewrites its ancestors.
abstract class PriorityNodeRepository {
  /// Every node owned by the current user, in no particular order.
  Future<List<PriorityNode>> getAllNodes();

  Future<void> saveNode(PriorityNode node);

  /// Bulk upsert, used when seeding a tree (migration). Implementations must
  /// insert parents before their children.
  Future<void> saveNodes(List<PriorityNode> nodes);

  /// Deletes the node together with its whole subtree.
  Future<void> deleteNode(String id);
}
