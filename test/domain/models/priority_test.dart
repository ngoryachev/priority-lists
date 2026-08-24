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

    test('critical, high and medium tiles share one height', () {
      expect(Priority.critical.cardHeightFraction, 0.20);
      expect(Priority.high.cardHeightFraction, 0.20);
      expect(Priority.medium.cardHeightFraction, 0.20);
      expect(Priority.low.cardHeightFraction, 0.10);
    });

    test('bubbles still scale by priority', () {
      expect(Priority.critical.bubbleWeight, 0.50);
      expect(Priority.high.bubbleWeight, 0.30);
      expect(Priority.medium.bubbleWeight, 0.20);
      expect(Priority.low.bubbleWeight, 0.10);
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
