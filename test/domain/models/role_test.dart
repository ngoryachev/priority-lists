import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/role.dart';

void main() {
  test('holds the six roles', () {
    expect(Role.values, hasLength(6));
  });

  test('ids, labels and descriptions are unique and non-empty', () {
    for (final role in Role.values) {
      expect(role.id, isNotEmpty, reason: '${role.name} id');
      expect(role.label, isNotEmpty, reason: '${role.name} label');
      expect(role.description, isNotEmpty, reason: '${role.name} description');
    }
    expect(Role.values.map((r) => r.id).toSet(), hasLength(6));
    expect(Role.values.map((r) => r.label).toSet(), hasLength(6));
    expect(Role.values.map((r) => r.description).toSet(), hasLength(6));
  });

  test('fromId round-trips every role', () {
    for (final role in Role.values) {
      expect(Role.fromId(role.id), role);
    }
  });

  test('fromId reads an unknown or missing id as no role', () {
    // A row written by a newer build must not crash an older client.
    expect(Role.fromId('mentor'), isNull);
    expect(Role.fromId(''), isNull);
    expect(Role.fromId(null), isNull);
  });
}
