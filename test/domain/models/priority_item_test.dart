import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_item.dart';

void main() {
  final now = DateTime(2024, 1, 1);

  PriorityItem createItem({
    String id = 'item-1',
    String title = 'Test Item',
    String description = 'Description',
    Priority priority = Priority.high,
  }) {
    return PriorityItem(
      id: id,
      title: title,
      description: description,
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('PriorityItem', () {
    test('creates with valid data', () {
      final item = createItem();
      expect(item.id, 'item-1');
      expect(item.title, 'Test Item');
      expect(item.description, 'Description');
      expect(item.priority, Priority.high);
    });

    test('throws on empty title', () {
      expect(() => createItem(title: ''), throwsArgumentError);
    });

    test('throws on title exceeding 200 characters', () {
      expect(() => createItem(title: 'a' * 201), throwsArgumentError);
    });

    test('description defaults to empty string', () {
      final item = PriorityItem(
        id: 'id',
        title: 'Title',
        priority: Priority.low,
        createdAt: now,
        updatedAt: now,
      );
      expect(item.description, '');
    });

    test('copyWith creates new instance with updated fields', () {
      final item = createItem();
      final later = DateTime(2024, 6, 1);
      final updated = item.copyWith(
        title: 'Updated',
        priority: Priority.critical,
        updatedAt: later,
      );

      expect(updated.id, item.id);
      expect(updated.title, 'Updated');
      expect(updated.priority, Priority.critical);
      expect(updated.updatedAt, later);
      expect(updated.description, item.description);
      expect(updated.createdAt, item.createdAt);
    });

    test('equality is based on id', () {
      final item1 = createItem(id: 'same-id', title: 'Title A');
      final item2 = createItem(id: 'same-id', title: 'Title B');
      final item3 = createItem(id: 'different-id');

      expect(item1, equals(item2));
      expect(item1, isNot(equals(item3)));
    });
  });
}
