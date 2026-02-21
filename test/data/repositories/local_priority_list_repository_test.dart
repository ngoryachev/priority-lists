import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/local_priority_list_repository.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_item.dart';
import 'package:priority_lists/domain/models/priority_list.dart';

void main() {
  late Directory tempDir;
  late LocalPriorityListRepository repository;
  final now = DateTime(2024, 1, 15);

  PriorityList makeList({
    String id = 'list-1',
    String name = 'Test List',
    List<PriorityItem>? items,
  }) {
    return PriorityList(
      id: id,
      name: name,
      colorPreset: ColorPreset.blue,
      items: items,
      createdAt: now,
      updatedAt: now,
    );
  }

  PriorityItem makeItem(String id, Priority priority) {
    return PriorityItem(
      id: id,
      title: 'Item $id',
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('priority_lists_test_');
    repository = LocalPriorityListRepository(
      filePath: '${tempDir.path}/data.json',
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('LocalPriorityListRepository', () {
    test('getAllLists returns empty list when file does not exist', () async {
      final lists = await repository.getAllLists();
      expect(lists, isEmpty);
    });

    test('saveList and getAllLists round-trip', () async {
      final list = makeList(items: [makeItem('i1', Priority.high)]);
      await repository.saveList(list);

      final lists = await repository.getAllLists();
      expect(lists, hasLength(1));
      expect(lists.first.id, list.id);
      expect(lists.first.name, list.name);
      expect(lists.first.items, hasLength(1));
    });

    test('saveList updates existing list', () async {
      final list = makeList();
      await repository.saveList(list);

      final updated = list.copyWith(name: 'Updated Name');
      await repository.saveList(updated);

      final lists = await repository.getAllLists();
      expect(lists, hasLength(1));
      expect(lists.first.name, 'Updated Name');
    });

    test('getListById returns list when found', () async {
      await repository.saveList(makeList(id: 'a'));
      await repository.saveList(makeList(id: 'b', name: 'Second'));

      final result = await repository.getListById('b');
      expect(result, isNotNull);
      expect(result!.name, 'Second');
    });

    test('getListById returns null when not found', () async {
      await repository.saveList(makeList());
      final result = await repository.getListById('nonexistent');
      expect(result, isNull);
    });

    test('deleteList removes list', () async {
      await repository.saveList(makeList(id: 'a'));
      await repository.saveList(makeList(id: 'b', name: 'Second'));

      await repository.deleteList('a');

      final lists = await repository.getAllLists();
      expect(lists, hasLength(1));
      expect(lists.first.id, 'b');
    });

    test('deleteList on nonexistent id does nothing', () async {
      await repository.saveList(makeList());
      await repository.deleteList('nonexistent');

      final lists = await repository.getAllLists();
      expect(lists, hasLength(1));
    });
  });
}
