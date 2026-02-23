import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_item.dart';
import 'package:priority_lists/domain/models/priority_list.dart';

void main() {
  final now = DateTime(2024, 1, 1);

  PriorityItem makeItem(String id, Priority priority) {
    return PriorityItem(
      id: id,
      title: 'Item $id',
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );
  }

  PriorityList makeList({
    String id = 'list-1',
    String name = 'Test List',
    ColorPreset colorPreset = ColorPreset.blue,
    List<PriorityItem>? items,
  }) {
    return PriorityList(
      id: id,
      name: name,
      colorPreset: colorPreset,
      items: items,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('PriorityList', () {
    test('creates with valid data', () {
      final list = makeList();
      expect(list.id, 'list-1');
      expect(list.name, 'Test List');
      expect(list.colorPreset, ColorPreset.blue);
      expect(list.items, isEmpty);
    });

    test('throws on empty name', () {
      expect(() => makeList(name: ''), throwsArgumentError);
    });

    test('throws on name exceeding 50 characters', () {
      expect(() => makeList(name: 'a' * 51), throwsArgumentError);
    });

    test('items list is unmodifiable', () {
      final list = makeList(items: [makeItem('1', Priority.high)]);
      expect(() => (list.items as List).add(makeItem('2', Priority.low)),
          throwsUnsupportedError);
    });

    test('sortedItems returns items sorted by priority value', () {
      final list = makeList(items: [
        makeItem('low', Priority.low),
        makeItem('critical', Priority.critical),
        makeItem('medium', Priority.medium),
        makeItem('high', Priority.high),
      ]);

      final sorted = list.sortedItems;
      expect(sorted[0].id, 'critical');
      expect(sorted[1].id, 'high');
      expect(sorted[2].id, 'medium');
      expect(sorted[3].id, 'low');
    });

    test('addItem appends item', () {
      final list = makeList();
      final item = makeItem('1', Priority.high);
      final updated = list.addItem(item);

      expect(updated.items, hasLength(1));
      expect(updated.items.first, item);
      expect(list.items, isEmpty); // original unchanged
    });

    test('updateItem replaces item by id', () {
      final item = makeItem('1', Priority.high);
      final list = makeList(items: [item]);
      final modified = item.copyWith(title: 'Updated');
      final updated = list.updateItem(modified);

      expect(updated.items.first.title, 'Updated');
    });

    test('removeItem removes item by id', () {
      final list = makeList(items: [
        makeItem('1', Priority.high),
        makeItem('2', Priority.low),
      ]);
      final updated = list.removeItem('1');

      expect(updated.items, hasLength(1));
      expect(updated.items.first.id, '2');
    });

    test('copyWith creates new instance with updated fields', () {
      final list = makeList();
      final updated = list.copyWith(name: 'New Name', colorPreset: ColorPreset.red);

      expect(updated.id, list.id);
      expect(updated.name, 'New Name');
      expect(updated.colorPreset, ColorPreset.red);
    });

    test('equality is based on id', () {
      final list1 = makeList(id: 'same', name: 'Name A');
      final list2 = makeList(id: 'same', name: 'Name B');
      final list3 = makeList(id: 'different');

      expect(list1, equals(list2));
      expect(list1, isNot(equals(list3)));
    });

    test('defaults to medium priority', () {
      final list = makeList();
      expect(list.priority, Priority.medium);
    });

    test('accepts explicit priority', () {
      final list = PriorityList(
        id: 'id',
        name: 'Test',
        colorPreset: ColorPreset.blue,
        priority: Priority.critical,
        createdAt: now,
        updatedAt: now,
      );
      expect(list.priority, Priority.critical);
    });

    test('copyWith updates priority', () {
      final list = makeList();
      final updated = list.copyWith(priority: Priority.low);
      expect(updated.priority, Priority.low);
      expect(updated.name, list.name);
    });
  });
}
