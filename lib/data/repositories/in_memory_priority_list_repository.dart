import '../../domain/models/priority_list.dart';
import '../../domain/repositories/priority_list_repository.dart';

/// Pre-auth local storage for platforms without file access (web).
class InMemoryPriorityListRepository implements PriorityListRepository {
  final List<PriorityList> _lists = [];

  @override
  Future<List<PriorityList>> getAllLists() async => List.of(_lists);

  @override
  Future<PriorityList?> getListById(String id) async {
    try {
      return _lists.firstWhere((list) => list.id == id);
    } on StateError {
      return null;
    }
  }

  @override
  Future<void> saveList(PriorityList list) async {
    final index = _lists.indexWhere((l) => l.id == list.id);
    if (index >= 0) {
      _lists[index] = list;
    } else {
      _lists.add(list);
    }
  }

  @override
  Future<void> deleteList(String id) async {
    _lists.removeWhere((list) => list.id == id);
  }
}
