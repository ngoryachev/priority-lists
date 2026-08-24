import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/dto/priority_node_dto.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';

void main() {
  final now = DateTime(2024, 1, 15, 10, 30);

  group('PriorityNodeDto', () {
    test('round-trips through JSON', () {
      final json = {
        'id': 'node-1',
        'parentId': 'node-0',
        'title': 'Task',
        'description': 'details',
        'priority': 2,
        'colorValue': ColorPreset.blue.colorValue,
        'createdAt': '2024-01-15T10:30:00.000',
        'updatedAt': '2024-01-15T10:30:00.000',
      };

      final dto = PriorityNodeDto.fromJson(json);
      expect(dto.toJson(), json);

      final entity = dto.toEntity();
      expect(entity.id, 'node-1');
      expect(entity.parentId, 'node-0');
      expect(entity.title, 'Task');
      expect(entity.description, 'details');
      expect(entity.priority, Priority.high);
      expect(entity.colorPreset, ColorPreset.blue);
    });

    test('round-trips an entity without a parent or colour', () {
      final node = PriorityNode(
        id: 'root-1',
        title: 'Top',
        priority: Priority.critical,
        createdAt: now,
        updatedAt: now,
      );

      final restored = PriorityNodeDto.fromJson(
        PriorityNodeDto.fromEntity(node).toJson(),
      ).toEntity();

      expect(restored.parentId, isNull);
      expect(restored.colorPreset, isNull);
      expect(restored.priority, Priority.critical);
      expect(restored.isRoot, isTrue);
    });

    test('reads a pre-nesting list row, whose label lived under "name"', () {
      final dto = PriorityNodeDto.fromJson({
        'id': 'list-1',
        'name': 'My List',
        'colorValue': ColorPreset.red.colorValue,
        'createdAt': '2024-01-15T10:30:00.000',
        'updatedAt': '2024-01-15T10:30:00.000',
      });

      final entity = dto.toEntity();
      expect(entity.title, 'My List');
      expect(entity.description, '');
      // Missing priority defaults to medium, as the old DTO did.
      expect(entity.priority, Priority.medium);
      expect(entity.parentId, isNull);
    });

    test('a colour that is no longer a preset degrades to none', () {
      final entity = PriorityNodeDto.fromJson({
        'id': 'n',
        'title': 'T',
        'priority': 1,
        'colorValue': 0x12345678,
        'createdAt': '2024-01-15T10:30:00.000',
        'updatedAt': '2024-01-15T10:30:00.000',
      }).toEntity();

      expect(entity.colorPreset, isNull);
    });
  });
}
