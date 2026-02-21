import 'dart:convert';
import 'dart:io';

import '../../domain/models/priority_list.dart';
import '../../domain/repositories/priority_list_repository.dart';
import '../dto/priority_list_dto.dart';

class LocalPriorityListRepository implements PriorityListRepository {
  final String filePath;

  LocalPriorityListRepository({required this.filePath});

  @override
  Future<List<PriorityList>> getAllLists() async {
    final file = File(filePath);
    if (!await file.exists()) {
      return [];
    }
    final content = await file.readAsString();
    if (content.isEmpty) {
      return [];
    }
    final jsonList = jsonDecode(content) as List<dynamic>;
    return jsonList
        .map((json) => PriorityListDto.fromJson(json as Map<String, dynamic>).toEntity())
        .toList();
  }

  @override
  Future<PriorityList?> getListById(String id) async {
    final lists = await getAllLists();
    try {
      return lists.firstWhere((list) => list.id == id);
    } on StateError {
      return null;
    }
  }

  @override
  Future<void> saveList(PriorityList list) async {
    final lists = await getAllLists();
    final index = lists.indexWhere((l) => l.id == list.id);
    if (index >= 0) {
      lists[index] = list;
    } else {
      lists.add(list);
    }
    await _writeLists(lists);
  }

  @override
  Future<void> deleteList(String id) async {
    final lists = await getAllLists();
    lists.removeWhere((list) => list.id == id);
    await _writeLists(lists);
  }

  Future<void> _writeLists(List<PriorityList> lists) async {
    final jsonList = lists.map((l) => PriorityListDto.fromEntity(l).toJson()).toList();
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(jsonList));
  }
}
