import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/data/repositories/shared_preferences_last_node_repository.dart';
import 'package:priority_lists/domain/repositories/last_node_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

const key = SharedPreferencesLastNodeRepository.key;

void main() {
  group('SharedPreferencesLastNodeRepository', () {
    test('round-trips a deep node', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPreferencesLastNodeRepository();

      await repository.save(
        const LastNodePointer(userId: 'user-1', nodeId: 'deep'),
      );

      expect(
        await repository.load(),
        const LastNodePointer(userId: 'user-1', nodeId: 'deep'),
      );
    });

    /// The root is a stored answer, not the absence of one: the user walked
    /// back up and the next launch has to open at the top level.
    test('round-trips the root', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPreferencesLastNodeRepository();

      await repository.save(const LastNodePointer(userId: 'user-1'));

      final loaded = await repository.load();
      expect(loaded, const LastNodePointer(userId: 'user-1'));
      expect(loaded!.nodeId, isNull);
    });

    test('the second save replaces the first', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPreferencesLastNodeRepository();

      await repository.save(
        const LastNodePointer(userId: 'user-1', nodeId: 'a'),
      );
      await repository.save(
        const LastNodePointer(userId: 'user-1', nodeId: 'b'),
      );

      expect(await repository.load(), isNotNull);
      expect((await repository.load())!.nodeId, 'b');
    });

    test('nothing stored reads back as null', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await SharedPreferencesLastNodeRepository().load(), isNull);
    });

    test('clear forgets the pointer', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPreferencesLastNodeRepository();
      await repository.save(
        const LastNodePointer(userId: 'user-1', nodeId: 'deep'),
      );

      await repository.clear();

      expect(await repository.load(), isNull);
    });

    /// A value we cannot read back must read as "nothing stored" rather than
    /// throw: a settings store the app cannot parse still has to let it open.
    group('a corrupt value reads back as null', () {
      final corrupt = <String, Object>{
        'not JSON at all': 'node-7',
        'a JSON list': jsonEncode(['user-1', 'node-7']),
        'a bare JSON string': jsonEncode('node-7'),
        'a map without a user id': jsonEncode({'nodeId': 'node-7'}),
        'a map with an empty user id': jsonEncode({'userId': ''}),
        'a map with a numeric user id': jsonEncode({'userId': 7}),
        'a map with a numeric node id': jsonEncode({
          'userId': 'user-1',
          'nodeId': 7,
        }),
      };

      for (final entry in corrupt.entries) {
        test(entry.key, () async {
          SharedPreferences.setMockInitialValues({key: entry.value});
          expect(await SharedPreferencesLastNodeRepository().load(), isNull);
        });
      }
    });
  });
}
