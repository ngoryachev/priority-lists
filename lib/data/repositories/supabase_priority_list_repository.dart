import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/color_preset.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/priority_item.dart';
import '../../domain/models/priority_list.dart';
import '../../domain/repositories/priority_list_repository.dart';

class SupabasePriorityListRepository implements PriorityListRepository {
  final SupabaseClient _client;

  SupabasePriorityListRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<List<PriorityList>> getAllLists() async {
    final response = await _client
        .from('priority_lists')
        .select('*, priority_items(*)')
        .eq('user_id', _userId)
        .order('created_at');

    return response.map(_mapToPriorityList).toList();
  }

  @override
  Future<PriorityList?> getListById(String id) async {
    final response = await _client
        .from('priority_lists')
        .select('*, priority_items(*)')
        .eq('id', id)
        .eq('user_id', _userId)
        .maybeSingle();

    if (response == null) return null;
    return _mapToPriorityList(response);
  }

  @override
  Future<void> saveList(PriorityList list) async {
    await _client.from('priority_lists').upsert({
      'id': list.id,
      'user_id': _userId,
      'name': list.name,
      'color_value': list.colorPreset.colorValue,
      'priority': list.priority.value,
      'created_at': list.createdAt.toUtc().toIso8601String(),
      'updated_at': list.updatedAt.toUtc().toIso8601String(),
    });

    // If the list has no items, drop everything still referencing it.
    if (list.items.isEmpty) {
      await _client.from('priority_items').delete().eq('list_id', list.id);
      return;
    }

    // Upsert the current items FIRST (inserts new ones, updates existing ones,
    // and re-parents items moved in from another list). Doing this before any
    // delete means the list is never left empty if a later step fails — which
    // is what previously wiped the destination list on move-into.
    await _client.from('priority_items').upsert(
          list.items
              .map((item) => {
                    'id': item.id,
                    'list_id': list.id,
                    'user_id': _userId,
                    'title': item.title,
                    'description': item.description,
                    'priority': item.priority.value,
                    'created_at': item.createdAt.toUtc().toIso8601String(),
                    'updated_at': item.updatedAt.toUtc().toIso8601String(),
                  })
              .toList(),
        );

    // Then remove only the items that are no longer part of this list.
    final keepIds = list.items.map((item) => item.id).join(',');
    await _client
        .from('priority_items')
        .delete()
        .eq('list_id', list.id)
        .not('id', 'in', '($keepIds)');
  }

  @override
  Future<void> deleteList(String id) async {
    await _client
        .from('priority_lists')
        .delete()
        .eq('id', id)
        .eq('user_id', _userId);
  }

  PriorityList _mapToPriorityList(Map<String, dynamic> json) {
    final itemsJson = json['priority_items'] as List? ?? [];
    return PriorityList(
      id: json['id'] as String,
      name: json['name'] as String,
      colorPreset: ColorPreset.fromColorValue(json['color_value'] as int),
      priority: Priority.fromValue(json['priority'] as int),
      items: itemsJson
          .map((itemJson) => PriorityItem(
                id: itemJson['id'] as String,
                title: itemJson['title'] as String,
                description: itemJson['description'] as String? ?? '',
                priority: Priority.fromValue(itemJson['priority'] as int),
                createdAt: DateTime.parse(itemJson['created_at'] as String),
                updatedAt: DateTime.parse(itemJson['updated_at'] as String),
              ))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
