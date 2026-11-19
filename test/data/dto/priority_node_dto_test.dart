import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/dto/priority_node_dto.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/node_mark.dart';
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
        'position': 4,
        'colorValue': ColorPreset.blue.colorValue,
        'mark': NodeMark.flame.value,
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
      expect(entity.position, 4);
      expect(entity.colorPreset, ColorPreset.blue);
      expect(entity.mark, NodeMark.flame);
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
      // No stored order either: 0 leaves such nodes sorted by age.
      expect(entity.position, 0);
      expect(entity.parentId, isNull);
    });

    test('a stored row with no mark key loads as unmarked', () {
      final entity = PriorityNodeDto.fromJson({
        'id': 'n',
        'title': 'T',
        'priority': 1,
        'position': 3,
        'createdAt': '2024-01-15T10:30:00.000',
        'updatedAt': '2024-01-15T10:30:00.000',
      }).toEntity();

      expect(entity.mark, isNull);
      // Nothing else is read differently for want of the key.
      expect(entity.priority, Priority.critical);
      expect(entity.position, 3);
    });

    test('a mark value this build does not know degrades to unmarked', () {
      final entity = PriorityNodeDto.fromJson({
        'id': 'n',
        'title': 'T',
        'priority': 1,
        'mark': 'thunder',
        'createdAt': '2024-01-15T10:30:00.000',
        'updatedAt': '2024-01-15T10:30:00.000',
      }).toEntity();

      expect(entity.mark, isNull);
    });

    test('both marks round-trip through an entity', () {
      for (final mark in NodeMark.values) {
        final node = PriorityNode(
          id: 'n',
          title: 'T',
          priority: Priority.low,
          mark: mark,
          createdAt: now,
          updatedAt: now,
        );
        final json = PriorityNodeDto.fromEntity(node).toJson();
        expect(json['mark'], mark.value);
        expect(PriorityNodeDto.fromJson(json).toEntity().mark, mark);
      }
    });

    test('an unmarked entity writes a null mark, not a missing key', () {
      final json = PriorityNodeDto.fromEntity(
        PriorityNode(
          id: 'n',
          title: 'T',
          priority: Priority.low,
          createdAt: now,
          updatedAt: now,
        ),
      ).toJson();

      expect(json.containsKey('mark'), isTrue);
      expect(json['mark'], isNull);
      expect(PriorityNodeDto.fromJson(json).toEntity().mark, isNull);
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
