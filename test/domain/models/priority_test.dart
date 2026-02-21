import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/priority.dart';

void main() {
  group('Priority', () {
    test('has correct values', () {
      expect(Priority.critical.value, 1);
      expect(Priority.high.value, 2);
      expect(Priority.medium.value, 3);
      expect(Priority.low.value, 4);
    });

    test('has correct screen height fractions', () {
      expect(Priority.critical.screenHeightFraction, 0.50);
      expect(Priority.high.screenHeightFraction, 0.30);
      expect(Priority.medium.screenHeightFraction, 0.20);
      expect(Priority.low.screenHeightFraction, 0.10);
    });

    test('fromValue returns correct enum', () {
      expect(Priority.fromValue(1), Priority.critical);
      expect(Priority.fromValue(2), Priority.high);
      expect(Priority.fromValue(3), Priority.medium);
      expect(Priority.fromValue(4), Priority.low);
    });

    test('fromValue throws for invalid value', () {
      expect(() => Priority.fromValue(0), throwsArgumentError);
      expect(() => Priority.fromValue(5), throwsArgumentError);
    });
  });
}
