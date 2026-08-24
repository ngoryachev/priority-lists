import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  PriorityNode node({String? parentId, ColorPreset? color}) => PriorityNode(
        id: 'n1',
        parentId: parentId,
        title: 'Node',
        priority: Priority.medium,
        colorPreset: color,
        createdAt: now,
        updatedAt: now,
      );

  group('PriorityNode', () {
    test('rejects an empty title', () {
      expect(
        () => PriorityNode(
          id: 'n',
          title: '',
          priority: Priority.low,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a title over the limit', () {
      expect(
        () => PriorityNode(
          id: 'n',
          title: 'x' * (PriorityNode.maxTitleLength + 1),
          priority: Priority.low,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('rejects being its own parent', () {
      expect(
        () => PriorityNode(
          id: 'n',
          parentId: 'n',
          title: 'Node',
          priority: Priority.low,
          createdAt: now,
          updatedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test('isRoot reflects the parent', () {
      expect(node().isRoot, isTrue);
      expect(node(parentId: 'p').isRoot, isFalse);
    });

    test('copyWith keeps the parent and identity', () {
      final child = node(parentId: 'p').copyWith(title: 'Renamed');
      expect(child.parentId, 'p');
      expect(child.id, 'n1');
      expect(child.title, 'Renamed');
      expect(child.createdAt, now);
    });

    test('copyWith leaves the colour alone unless asked to clear it', () {
      final coloured = node(color: ColorPreset.red);
      expect(coloured.copyWith(title: 'x').colorPreset, ColorPreset.red);
      expect(coloured.copyWith(clearColorPreset: true).colorPreset, isNull);
    });

    test('withParent re-parents, including back to the top level', () {
      final child = node(parentId: 'p');
      expect(child.withParent('q').parentId, 'q');
      expect(child.withParent(null).parentId, isNull);
      expect(child.withParent(null).isRoot, isTrue);
    });
  });
}
