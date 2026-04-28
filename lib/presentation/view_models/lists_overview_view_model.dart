import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/color_preset.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/priority_item.dart';
import '../../domain/models/priority_list.dart';
import '../../domain/repositories/priority_list_repository.dart';

class ListsOverviewViewModel extends ChangeNotifier {
  final PriorityListRepository _repository;
  final Uuid _uuid;

  List<PriorityList> _lists = [];
  bool _isLoading = false;
  String? _error;

  ListsOverviewViewModel(this._repository, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  List<PriorityList> get lists => _lists;
  List<PriorityList> get sortedLists => List.of(_lists)
    ..sort((a, b) => a.priority.value.compareTo(b.priority.value));
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadLists() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _lists = await _repository.getAllLists();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createList(String name, ColorPreset colorPreset, Priority priority) async {
    final now = DateTime.now();
    final list = PriorityList(
      id: _uuid.v4(),
      name: name,
      colorPreset: colorPreset,
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.saveList(list);
    await loadLists();
  }

  Future<void> deleteList(String id) async {
    await _repository.deleteList(id);
    await loadLists();
  }

  Future<void> updateList(PriorityList list) async {
    await _repository.saveList(list);
    await loadLists();
  }

  Future<void> moveListIntoList(String sourceListId, String targetListId) async {
    final allLists = await _repository.getAllLists();
    final sourceList = allLists.firstWhere((l) => l.id == sourceListId);
    var targetList = allLists.firstWhere((l) => l.id == targetListId);

    final now = DateTime.now();

    final newItem = PriorityItem(
      id: _uuid.v4(),
      title: sourceList.name,
      priority: sourceList.priority,
      createdAt: now,
      updatedAt: now,
    );

    targetList = targetList.addItem(newItem);
    for (final item in sourceList.items) {
      targetList = targetList.addItem(item);
    }
    targetList = targetList.copyWith(updatedAt: now);

    await _repository.saveList(targetList);
    await _repository.deleteList(sourceListId);
    await loadLists();
  }
}
