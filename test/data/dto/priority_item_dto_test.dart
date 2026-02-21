import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/dto/priority_item_dto.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_item.dart';

void main() {
  final now = DateTime(2024, 1, 15, 10, 30);

  group('PriorityItemDto', () {
    test('fromJson and toJson round-trip', () {
      final json = {
        'id': 'item-1',
        'title': 'Test',
        'description': 'Desc',
        'priority': 2,
        'createdAt': '2024-01-15T10:30:00.000',
        'updatedAt': '2024-01-15T10:30:00.000',
      };

      final dto = PriorityItemDto.fromJson(json);
      final result = dto.toJson();

      expect(result['id'], json['id']);
      expect(result['title'], json['title']);
      expect(result['priority'], json['priority']);
    });

    test('fromEntity and toEntity round-trip', () {
      final item = PriorityItem(
        id: 'item-1',
        title: 'Test',
        description: 'Desc',
        priority: Priority.high,
        createdAt: now,
        updatedAt: now,
      );

      final dto = PriorityItemDto.fromEntity(item);
      final restored = dto.toEntity();

      expect(restored.id, item.id);
      expect(restored.title, item.title);
      expect(restored.description, item.description);
      expect(restored.priority, item.priority);
      expect(restored.createdAt, item.createdAt);
      expect(restored.updatedAt, item.updatedAt);
    });
  });
}
