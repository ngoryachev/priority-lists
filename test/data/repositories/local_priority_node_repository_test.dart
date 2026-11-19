import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/local_priority_node_repository.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/node_mark.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_node.dart';

void main() {
  late Directory tempDir;
  late String filePath;
  late LocalPriorityNodeRepository repository;

  final now = DateTime(2026, 1, 1);

  PriorityNode node(String id, {String? parent}) => PriorityNode(
        id: id,
        parentId: parent,
        title: id,
        priority: Priority.medium,
        createdAt: now,
        updatedAt: now,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('priority_nodes_test');
    filePath = '${tempDir.path}/nodes.json';
    repository = LocalPriorityNodeRepository(filePath: filePath);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LocalPriorityNodeRepository', () {
    test('returns nothing when the file is absent', () async {
      expect(await repository.getAllNodes(), isEmpty);
    });

    test('saves and reads back a nested tree', () async {
      await repository.saveNode(node('root'));
      await repository.saveNode(node('child', parent: 'root'));
      await repository.saveNode(node('grandchild', parent: 'child'));

      final nodes = await repository.getAllNodes();
      expect(nodes.map((n) => n.id), ['root', 'child', 'grandchild']);
      expect(
        nodes.firstWhere((n) => n.id == 'grandchild').parentId,
        'child',
      );
    });

    test('saveNode updates an existing node in place', () async {
      await repository.saveNode(node('root'));
      await repository.saveNode(
        node('root').copyWith(title: 'Renamed', priority: Priority.critical),
      );

      final nodes = await repository.getAllNodes();
      expect(nodes, hasLength(1));
      expect(nodes.single.title, 'Renamed');
      expect(nodes.single.priority, Priority.critical);
    });

    test('a mark survives a save and a read back', () async {
      await repository.saveNode(
        node('root').copyWith(mark: NodeMark.flame, position: 5),
      );
      await repository.saveNode(node('other').copyWith(mark: NodeMark.ice));
      await repository.saveNode(node('plain'));

      final nodes = await repository.getAllNodes();
      final byId = {for (final n in nodes) n.id: n};
      expect(byId['root']!.mark, NodeMark.flame);
      // The mark rides alongside the rest, not instead of it.
      expect(byId['root']!.position, 5);
      expect(byId['root']!.priority, Priority.medium);
      expect(byId['other']!.mark, NodeMark.ice);
      expect(byId['plain']!.mark, isNull);
    });

    test('clearing a mark is persisted, not just dropped locally', () async {
      await repository.saveNode(node('root').copyWith(mark: NodeMark.flame));
      await repository.saveNode(node('root').copyWith(clearMark: true));

      expect((await repository.getAllNodes()).single.mark, isNull);
    });

    test('a stored file written without the mark key loads as unmarked',
        () async {
      await File(filePath).writeAsString(
        jsonEncode({
          'nodes': [
            {
              'id': 'root',
              'parentId': null,
              'title': 'Root',
              'description': '',
              'priority': 2,
              'position': 1,
              'colorValue': null,
              'createdAt': '2026-01-01T00:00:00.000',
              'updatedAt': '2026-01-01T00:00:00.000',
            },
          ],
        }),
      );

      final stored = (await repository.getAllNodes()).single;
      expect(stored.mark, isNull);
      expect(stored.priority, Priority.high);
      expect(stored.position, 1);
    });

    test('saveNodes upserts a whole batch', () async {
      await repository.saveNodes([
        node('root'),
        node('a', parent: 'root'),
      ]);
      await repository.saveNodes([
        node('a', parent: 'root').copyWith(title: 'A!'),
        node('b', parent: 'root'),
      ]);

      final nodes = await repository.getAllNodes();
      expect(nodes.map((n) => n.id).toSet(), {'root', 'a', 'b'});
      expect(nodes.firstWhere((n) => n.id == 'a').title, 'A!');
    });

    test('deleting a node takes its whole subtree with it', () async {
      await repository.saveNodes([
        node('root'),
        node('a', parent: 'root'),
        node('a1', parent: 'a'),
        node('a1x', parent: 'a1'),
        node('b', parent: 'root'),
      ]);

      await repository.deleteNode('a');

      final nodes = await repository.getAllNodes();
      expect(nodes.map((n) => n.id).toSet(), {'root', 'b'});
    });

    test('flattens a pre-nesting file of lists with inlined items', () async {
      await File(filePath).writeAsString(jsonEncode([
        {
          'id': 'list-1',
          'name': 'Work',
          'colorValue': ColorPreset.red.colorValue,
          'priority': 1,
          'createdAt': '2026-01-01T00:00:00.000',
          'updatedAt': '2026-01-01T00:00:00.000',
          'items': [
            {
              'id': 'item-1',
              'title': 'Fix bug',
              'description': 'urgent',
              'priority': 2,
              'createdAt': '2026-01-01T00:00:00.000',
              'updatedAt': '2026-01-01T00:00:00.000',
            }
          ],
        }
      ]));

      final nodes = await repository.getAllNodes();
      expect(nodes.map((n) => n.id), ['list-1', 'item-1']);
      expect(nodes.first.title, 'Work');
      expect(nodes.first.parentId, isNull);
      expect(nodes.last.parentId, 'list-1');
      expect(nodes.last.description, 'urgent');
    });
  });
}
