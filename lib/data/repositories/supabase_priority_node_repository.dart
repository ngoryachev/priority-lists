import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/color_preset.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/priority_node.dart';
import '../../domain/repositories/priority_node_repository.dart';

class SupabasePriorityNodeRepository implements PriorityNodeRepository {
  final SupabaseClient _client;

  SupabasePriorityNodeRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<List<PriorityNode>> getAllNodes() async {
    final response = await _client
        .from('nodes')
        .select()
        .eq('user_id', _userId)
        .order('created_at');

    return response.map(_toEntity).toList();
  }

  @override
  Future<void> saveNode(PriorityNode node) async {
    await _client.from('nodes').upsert(_toRow(node));
  }

  @override
  Future<void> saveNodes(List<PriorityNode> nodes) async {
    if (nodes.isEmpty) return;
    // Parents first: the FK (and the cycle guard) rejects a child whose parent
    // row does not exist yet, and a single upsert gives no ordering guarantee.
    for (final batch in _byDepth(nodes)) {
      await _client.from('nodes').upsert(batch.map(_toRow).toList());
    }
  }

  @override
  Future<void> deleteNode(String id) async {
    // `parent_id ... ON DELETE CASCADE` takes the subtree with it.
    await _client.from('nodes').delete().eq('id', id).eq('user_id', _userId);
  }

  /// Groups nodes into insertion waves: roots (or nodes whose parent is not
  /// part of this batch) first, then their children, and so on.
  List<List<PriorityNode>> _byDepth(List<PriorityNode> nodes) {
    final pending = List.of(nodes);
    final ids = {for (final node in nodes) node.id};
    final settled = <String>{};
    final waves = <List<PriorityNode>>[];

    while (pending.isNotEmpty) {
      final wave = pending
          .where((node) =>
              node.parentId == null ||
              !ids.contains(node.parentId) ||
              settled.contains(node.parentId))
          .toList();
      if (wave.isEmpty) {
        // Cyclic or otherwise unorderable input: write the rest as-is rather
        // than looping forever, and let the database reject what is invalid.
        waves.add(pending);
        break;
      }
      waves.add(wave);
      settled.addAll(wave.map((node) => node.id));
      pending.removeWhere((node) => settled.contains(node.id));
    }

    return waves;
  }

  Map<String, dynamic> _toRow(PriorityNode node) => {
        'id': node.id,
        'user_id': _userId,
        'parent_id': node.parentId,
        'title': node.title,
        'description': node.description,
        'priority': node.priority.value,
        'color_value': node.colorPreset?.colorValue,
        'created_at': node.createdAt.toUtc().toIso8601String(),
        'updated_at': node.updatedAt.toUtc().toIso8601String(),
      };

  PriorityNode _toEntity(Map<String, dynamic> json) => PriorityNode(
        id: json['id'] as String,
        parentId: json['parent_id'] as String?,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        priority: Priority.fromValue(json['priority'] as int),
        colorPreset:
            ColorPreset.tryFromColorValue((json['color_value'] as num?)?.toInt()),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}
