import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/node_tree.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';

PriorityNode node(
  String id, {
  String? parent,
  Priority priority = Priority.medium,
  int createdOffset = 0,
}) {
  final created = DateTime(2026, 1, 1).add(Duration(minutes: createdOffset));
  return PriorityNode(
    id: id,
    parentId: parent,
    title: id,
    priority: priority,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  group('NodeTree', () {
    test('groups children under their parent', () {
      final tree = NodeTree([
        node('root'),
        node('a', parent: 'root'),
        node('b', parent: 'root'),
        node('a1', parent: 'a'),
      ]);

      expect(tree.roots.map((n) => n.id), ['root']);
      expect(tree.childrenOf('root').map((n) => n.id), ['a', 'b']);
      expect(tree.childrenOf('a').map((n) => n.id), ['a1']);
      expect(tree.childrenOf('a1'), isEmpty);
    });

    test('sorts siblings by priority, then by age', () {
      final tree = NodeTree([
        node('low', priority: Priority.low, createdOffset: 0),
        node('second-critical', priority: Priority.critical, createdOffset: 2),
        node('first-critical', priority: Priority.critical, createdOffset: 1),
        node('high', priority: Priority.high, createdOffset: 3),
      ]);

      expect(
        tree.roots.map((n) => n.id),
        ['first-critical', 'second-critical', 'high', 'low'],
      );
    });

    test('treats a node with a missing parent as a root', () {
      final tree = NodeTree([node('orphan', parent: 'gone')]);

      expect(tree.roots.map((n) => n.id), ['orphan']);
      expect(tree.pathTo('orphan').map((n) => n.id), ['orphan']);
    });

    test('pathTo returns the root-to-node chain', () {
      final tree = NodeTree([
        node('root'),
        node('mid', parent: 'root'),
        node('leaf', parent: 'mid'),
      ]);

      expect(tree.pathTo('leaf').map((n) => n.id), ['root', 'mid', 'leaf']);
      expect(tree.pathTo('root').map((n) => n.id), ['root']);
      expect(tree.pathTo('nope'), isEmpty);
    });

    test('depthOf counts levels from the root', () {
      final tree = NodeTree([
        node('root'),
        node('mid', parent: 'root'),
        node('leaf', parent: 'mid'),
      ]);

      expect(tree.depthOf('root'), 0);
      expect(tree.depthOf('mid'), 1);
      expect(tree.depthOf('leaf'), 2);
    });

    test('descendants cover the whole subtree, at any depth', () {
      final tree = NodeTree([
        node('root'),
        node('a', parent: 'root'),
        node('a1', parent: 'a'),
        node('a1x', parent: 'a1'),
        node('a1xy', parent: 'a1x'),
        node('b', parent: 'root'),
      ]);

      expect(
        tree.descendantsOf('root').map((n) => n.id).toSet(),
        {'a', 'a1', 'a1x', 'a1xy', 'b'},
      );
      expect(tree.descendantCount('a'), 3);
      expect(tree.descendantCount('a1xy'), 0);
    });

    test('isDescendantOf walks the whole ancestor chain', () {
      final tree = NodeTree([
        node('root'),
        node('a', parent: 'root'),
        node('a1', parent: 'a'),
        node('b', parent: 'root'),
      ]);

      expect(tree.isDescendantOf('a1', 'root'), isTrue);
      expect(tree.isDescendantOf('a1', 'a'), isTrue);
      expect(tree.isDescendantOf('a1', 'b'), isFalse);
      expect(tree.isDescendantOf('root', 'a1'), isFalse);
    });

    test('a cycle in stored data does not hang the walks', () {
      // Guarded in the database, but the in-memory walks must not spin if it
      // ever slips through.
      final tree = NodeTree([
        node('x', parent: 'y'),
        node('y', parent: 'x'),
      ]);

      expect(tree.pathTo('x').length, lessThanOrEqualTo(2));
      expect(tree.isDescendantOf('x', 'y'), isTrue);
      expect(tree.descendantCount('x'), lessThanOrEqualTo(2));
    });

    test('move targets exclude the node and its own subtree', () {
      final tree = NodeTree([
        node('root'),
        node('a', parent: 'root'),
        node('a1', parent: 'a'),
        node('a1x', parent: 'a1'),
        node('b', parent: 'root'),
      ]);

      expect(
        tree.moveTargetsFor('a').map((n) => n.id),
        ['root', 'b'],
      );
      expect(
        tree.moveTargetsFor('a1x').map((n) => n.id),
        ['root', 'a', 'a1', 'b'],
      );
    });

    test('move targets come out depth-first for indenting', () {
      final tree = NodeTree([
        node('root'),
        node('a', parent: 'root'),
        node('a1', parent: 'a'),
        node('b', parent: 'root'),
      ]);

      expect(tree.moveTargetsFor('zzz').map((n) => n.id), [
        'root',
        'a',
        'a1',
        'b',
      ]);
    });

    test('childCount and hasChildren report direct children only', () {
      final tree = NodeTree([
        node('root'),
        node('a', parent: 'root'),
        node('a1', parent: 'a'),
      ]);

      expect(tree.childCount('root'), 1);
      expect(tree.hasChildren('root'), isTrue);
      expect(tree.hasChildren('a1'), isFalse);
    });
  });
}
