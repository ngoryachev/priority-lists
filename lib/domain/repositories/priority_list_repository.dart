import '../models/priority_list.dart';

abstract class PriorityListRepository {
  Future<List<PriorityList>> getAllLists();
  Future<PriorityList?> getListById(String id);
  Future<void> saveList(PriorityList list);
  Future<void> deleteList(String id);
}
