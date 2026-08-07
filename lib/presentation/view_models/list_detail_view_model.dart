import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/color_preset.dart';
import '../../domain/models/priority.dart';
import '../../domain/models/priority_item.dart';
import '../../domain/models/priority_list.dart';
import '../../domain/repositories/priority_list_repository.dart';

class ListDetailViewModel extends ChangeNotifier {
  final PriorityListRepository _repository;
  final Uuid _uuid;

  PriorityList _list;

  ListDetailViewModel(this._repository, this._list, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  PriorityList get list => _list;
  List<PriorityItem> get sortedItems => _list.sortedItems;

  Future<void> addItem(String title, String description, Priority priority) async {
    final now = DateTime.now();
    final item = PriorityItem(
      id: _uuid.v4(),
      title: title,
      description: description,
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );
    _list = _list.addItem(item).copyWith(updatedAt: now);
    await _save();
  }

  Future<void> updateItem(PriorityItem item) async {
    final now = DateTime.now();
    final updated = item.copyWith(updatedAt: now);
    _list = _list.updateItem(updated).copyWith(updatedAt: now);
    await _save();
  }

  Future<void> deleteItem(String itemId) async {
    final now = DateTime.now();
    _list = _list.removeItem(itemId).copyWith(updatedAt: now);
    await _save();
  }

  Future<void> extractItemToList(String itemId) async {
    final item = _list.items.firstWhere((i) => i.id == itemId);
    final now = DateTime.now();

    _list = _list.removeItem(itemId).copyWith(updatedAt: now);
    await _repository.saveList(_list);

    final newList = PriorityList(
      id: _uuid.v4(),
      name: item.title,
      colorPreset: ColorPreset.blue,
      priority: item.priority,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.saveList(newList);
    notifyListeners();
  }

  /// All lists except the one being viewed — the possible destinations for
  /// [moveItemToList], ordered like the overview screen.
  Future<List<PriorityList>> loadMoveTargets() async {
    final all = await _repository.getAllLists();
    return all.where((l) => l.id != _list.id).toList()
      ..sort((a, b) => a.priority.value.compareTo(b.priority.value));
  }

  Future<void> moveItemToList(String itemId, String targetListId) async {
    final item = _list.items.firstWhere((i) => i.id == itemId);
    final target = await _repository.getListById(targetListId);
    if (target == null) return;

    final now = DateTime.now();

    // Save the destination FIRST: that re-parents the item row. Only then drop
    // it from the source, so a failure in between duplicates the item instead
    // of losing it — and the source save can no longer delete a moved row.
    await _repository.saveList(
      target.addItem(item.copyWith(updatedAt: now)).copyWith(updatedAt: now),
    );

    _list = _list.removeItem(itemId).copyWith(updatedAt: now);
    await _save();
  }

  Future<void> updateListDetails(String name, ColorPreset colorPreset) async {
    final now = DateTime.now();
    _list = _list.copyWith(name: name, colorPreset: colorPreset, updatedAt: now);
    await _save();
  }

  Future<void> deleteList() async {
    await _repository.deleteList(_list.id);
  }

  Future<void> _save() async {
    await _repository.saveList(_list);
    notifyListeners();
  }
}
