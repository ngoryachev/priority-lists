import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/node_mark.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  PriorityNode node({String? parentId, ColorPreset? color, NodeMark? mark}) =>
      PriorityNode(
        id: 'n1',
        parentId: parentId,
        title: 'Node',
        priority: Priority.medium,
        position: 7,
        colorPreset: color,
        mark: mark,
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

    test('a node is unmarked unless told otherwise', () {
      expect(node().mark, isNull);
      expect(node(mark: NodeMark.flame).mark, NodeMark.flame);
    });

    test('copyWith leaves the mark alone unless asked to clear it', () {
      final marked = node(mark: NodeMark.flame);
      expect(marked.copyWith(title: 'x').mark, NodeMark.flame);
      expect(marked.copyWith(mark: NodeMark.ice).mark, NodeMark.ice);
      expect(marked.copyWith(clearMark: true).mark, isNull);
    });

    test('setting or clearing a mark touches nothing else', () {
      final plain = node();
      for (final changed in [
        plain.copyWith(mark: NodeMark.flame, updatedAt: now.add(const Duration(days: 1))),
        plain.copyWith(mark: NodeMark.ice).copyWith(clearMark: true),
      ]) {
        expect(changed.priority, Priority.medium);
        expect(changed.position, 7);
        expect(changed.createdAt, now);
        expect(changed.title, 'Node');
      }
    });

    test('withParent carries the mark through', () {
      expect(node(mark: NodeMark.ice).withParent('q').mark, NodeMark.ice);
      expect(node(mark: NodeMark.ice).withParent(null).mark, NodeMark.ice);
      expect(node().withParent('q').mark, isNull);
    });

    test('withParent re-parents, including back to the top level', () {
      final child = node(parentId: 'p');
      expect(child.withParent('q').parentId, 'q');
      expect(child.withParent(null).parentId, isNull);
      expect(child.withParent(null).isRoot, isTrue);
    });
  });
}
