import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/dto/priority_list_dto.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_item.dart';
import 'package:priority_lists/domain/models/priority_list.dart';

void main() {
  final now = DateTime(2024, 1, 15, 10, 30);

  group('PriorityListDto', () {
    test('fromJson and toJson round-trip', () {
      final json = {
        'id': 'list-1',
        'name': 'My List',
        'colorValue': ColorPreset.blue.colorValue,
        'priority': 2,
        'items': [
          {
            'id': 'item-1',
            'title': 'Task',
            'description': '',
            'priority': 1,
            'createdAt': '2024-01-15T10:30:00.000',
            'updatedAt': '2024-01-15T10:30:00.000',
          }
        ],
        'createdAt': '2024-01-15T10:30:00.000',
        'updatedAt': '2024-01-15T10:30:00.000',
      };

      final dto = PriorityListDto.fromJson(json);
      final result = dto.toJson();

      expect(result['id'], json['id']);
      expect(result['name'], json['name']);
      expect(result['colorValue'], json['colorValue']);
      expect(result['priority'], 2);
      expect((result['items'] as List).length, 1);
    });

    test('fromJson without priority defaults to medium (migration)', () {
      final json = {
        'id': 'list-1',
        'name': 'Old List',
        'colorValue': ColorPreset.blue.colorValue,
        'items': [],
        'createdAt': '2024-01-15T10:30:00.000',
        'updatedAt': '2024-01-15T10:30:00.000',
      };

      final dto = PriorityListDto.fromJson(json);
      expect(dto.priority, Priority.medium.value);

      final entity = dto.toEntity();
      expect(entity.priority, Priority.medium);
    });

    test('fromEntity and toEntity round-trip', () {
      final list = PriorityList(
        id: 'list-1',
        name: 'My List',
        colorPreset: ColorPreset.green,
        priority: Priority.high,
        items: [
          PriorityItem(
            id: 'item-1',
            title: 'Task',
            priority: Priority.critical,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );

      final dto = PriorityListDto.fromEntity(list);
      final restored = dto.toEntity();

      expect(restored.id, list.id);
      expect(restored.name, list.name);
      expect(restored.colorPreset, list.colorPreset);
      expect(restored.priority, Priority.high);
      expect(restored.items.length, 1);
      expect(restored.items.first.title, 'Task');
      expect(restored.items.first.priority, Priority.critical);
    });
  });
}
