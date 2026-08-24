import 'dart:convert';
import 'dart:io';

import '../../domain/models/node_tree.dart';
import '../../domain/models/priority_node.dart';
import '../../domain/repositories/priority_node_repository.dart';
import '../dto/priority_node_dto.dart';

/// Flat-file storage for the pre-auth tree.
class LocalPriorityNodeRepository implements PriorityNodeRepository {
  final String filePath;

  LocalPriorityNodeRepository({required this.filePath});

  @override
  Future<List<PriorityNode>> getAllNodes() async {
    final file = File(filePath);
    if (!await file.exists()) return [];

    final content = await file.readAsString();
    if (content.isEmpty) return [];

    final decoded = jsonDecode(content);
    // Files written before nesting held a list of lists, each with its items
    // inlined; flatten them into nodes so old local data still opens.
    final json = decoded is Map<String, dynamic>
        ? decoded['nodes'] as List<dynamic>
        : _flattenLegacy(decoded as List<dynamic>);

    return json
        .map((node) =>
            PriorityNodeDto.fromJson(node as Map<String, dynamic>).toEntity())
        .toList();
  }

  static List<Map<String, dynamic>> _flattenLegacy(List<dynamic> lists) {
    final nodes = <Map<String, dynamic>>[];
    for (final entry in lists) {
      final list = entry as Map<String, dynamic>;
      if (!list.containsKey('items')) {
        nodes.add(list);
        continue;
      }
      nodes.add({...list, 'items': null, 'parentId': null});
      for (final item in list['items'] as List<dynamic>) {
        nodes.add({...item as Map<String, dynamic>, 'parentId': list['id']});
      }
    }
    return nodes;
  }

  @override
  Future<void> saveNode(PriorityNode node) async {
    final nodes = await getAllNodes();
    final index = nodes.indexWhere((n) => n.id == node.id);
    if (index >= 0) {
      nodes[index] = node;
    } else {
      nodes.add(node);
    }
    await _write(nodes);
  }

  @override
  Future<void> saveNodes(List<PriorityNode> incoming) async {
    if (incoming.isEmpty) return;
    final nodes = await getAllNodes();
    for (final node in incoming) {
      final index = nodes.indexWhere((n) => n.id == node.id);
      if (index >= 0) {
        nodes[index] = node;
      } else {
        nodes.add(node);
      }
    }
    await _write(nodes);
  }

  @override
  Future<void> deleteNode(String id) async {
    final nodes = await getAllNodes();
    // No database cascade here, so the subtree has to be collected by hand.
    final doomed = {
      id,
      ...NodeTree(nodes).descendantsOf(id).map((node) => node.id),
    };
    nodes.removeWhere((node) => doomed.contains(node.id));
    await _write(nodes);
  }

  Future<void> _write(List<PriorityNode> nodes) async {
    final json = {
      'version': 2,
      'nodes': nodes.map((n) => PriorityNodeDto.fromEntity(n).toJson()).toList(),
    };
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json));
  }
}
