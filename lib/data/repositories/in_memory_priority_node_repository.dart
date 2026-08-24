import '../../domain/models/node_tree.dart';
import '../../domain/models/priority_node.dart';
import '../../domain/repositories/priority_node_repository.dart';

/// Pre-auth storage for platforms without file access (web).
class InMemoryPriorityNodeRepository implements PriorityNodeRepository {
  final List<PriorityNode> _nodes = [];

  @override
  Future<List<PriorityNode>> getAllNodes() async => List.of(_nodes);

  @override
  Future<void> saveNode(PriorityNode node) async {
    final index = _nodes.indexWhere((n) => n.id == node.id);
    if (index >= 0) {
      _nodes[index] = node;
    } else {
      _nodes.add(node);
    }
  }

  @override
  Future<void> saveNodes(List<PriorityNode> nodes) async {
    for (final node in nodes) {
      await saveNode(node);
    }
  }

  @override
  Future<void> deleteNode(String id) async {
    final doomed = {
      id,
      ...NodeTree(_nodes).descendantsOf(id).map((node) => node.id),
    };
    _nodes.removeWhere((node) => doomed.contains(node.id));
  }
}
