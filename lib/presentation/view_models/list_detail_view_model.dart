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

  Future<void> updateListDetails(String name, ColorPreset colorPreset) async {
    final now = DateTime.now();
    _list = _list.copyWith(name: name, colorPreset: colorPreset, updatedAt: now);
    await _save();
  }

  Future<void> _save() async {
    await _repository.saveList(_list);
    notifyListeners();
  }
}
