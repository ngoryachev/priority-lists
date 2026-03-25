import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/presentation/widgets/bubble_view/bubble_physics.dart'
    as bp;

bp.Size _canvas = const bp.Size(400, 800);

Map<String, Priority> _entries(Map<String, Priority> map) => map;

void main() {
  group('BubblePhysics', () {
    late bp.BubblePhysics physics;

    setUp(() {
      physics = bp.BubblePhysics(
        canvasSize: _canvas,
        random: Random(42),
      );
    });

    test('sync creates bodies for each entry', () {
      physics.sync(_entries({'a': Priority.medium, 'b': Priority.high, 'c': Priority.low}));

      expect(physics.bodies.length, 3);
      expect(physics.bodies.containsKey('a'), true);
      expect(physics.bodies.containsKey('b'), true);
      expect(physics.bodies.containsKey('c'), true);
    });

    test('sync removes deleted entries', () {
      physics.sync(_entries({'a': Priority.medium, 'b': Priority.medium}));
      expect(physics.bodies.length, 2);

      physics.sync(_entries({'a': Priority.medium}));
      expect(physics.bodies.length, 1);
      expect(physics.bodies.containsKey('b'), false);
    });

    test('sync updates targetRadius on priority change', () {
      physics.sync(_entries({'a': Priority.low}));
      final oldTarget = physics.bodies['a']!.targetRadius;

      physics.sync(_entries({'a': Priority.critical}));
      final newTarget = physics.bodies['a']!.targetRadius;

      expect(newTarget, greaterThan(oldTarget));
    });

    test('sync preserves position of existing bodies', () {
      physics.sync(_entries({'a': Priority.medium}));
      physics.bodies['a']!.x = 100;
      physics.bodies['a']!.y = 200;

      physics.sync(_entries({'a': Priority.medium}));
      expect(physics.bodies['a']!.x, 100);
      expect(physics.bodies['a']!.y, 200);
    });

    test('radiusForPriority returns larger radius for higher priority', () {
      final rCritical = bp.BubblePhysics.radiusForPriority(Priority.critical, _canvas);
      final rHigh = bp.BubblePhysics.radiusForPriority(Priority.high, _canvas);
      final rMedium = bp.BubblePhysics.radiusForPriority(Priority.medium, _canvas);
      final rLow = bp.BubblePhysics.radiusForPriority(Priority.low, _canvas);

      expect(rCritical, greaterThan(rHigh));
      expect(rHigh, greaterThan(rMedium));
      expect(rMedium, greaterThan(rLow));
      expect(rLow, greaterThan(0));
    });

    test('step keeps bodies within canvas bounds', () {
      physics.sync(_entries({'a': Priority.medium}));
      physics.bodies['a']!.x = -50;
      physics.bodies['a']!.y = 900;

      for (int i = 0; i < 10; i++) {
        physics.step(0.016);
      }

      final body = physics.bodies['a']!;
      expect(body.x, greaterThanOrEqualTo(body.radius));
      expect(body.x, lessThanOrEqualTo(_canvas.width - body.radius));
      expect(body.y, greaterThanOrEqualTo(body.radius));
      expect(body.y, lessThanOrEqualTo(_canvas.height - body.radius));
    });

    test('step resolves collisions between overlapping bodies', () {
      physics.sync(_entries({'a': Priority.medium, 'b': Priority.medium}));
      physics.bodies['a']!.x = 200;
      physics.bodies['a']!.y = 400;
      physics.bodies['b']!.x = 200;
      physics.bodies['b']!.y = 400;

      for (int i = 0; i < 60; i++) {
        physics.step(0.016);
      }

      final a = physics.bodies['a']!;
      final b = physics.bodies['b']!;
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final dist = sqrt(dx * dx + dy * dy);

      expect(dist, greaterThanOrEqualTo(a.radius + b.radius - 1));
    });

    test('step applies drift so positions change over time', () {
      physics.sync(_entries({'a': Priority.medium}));
      final startX = physics.bodies['a']!.x;
      final startY = physics.bodies['a']!.y;

      for (int i = 0; i < 120; i++) {
        physics.step(0.016);
      }

      final body = physics.bodies['a']!;
      final moved = (body.x - startX).abs() + (body.y - startY).abs();
      expect(moved, greaterThan(0.1));
    });

    test('radius lerps toward targetRadius over time', () {
      physics.sync(_entries({'a': Priority.low}));
      final body = physics.bodies['a']!;
      body.targetRadius = body.radius * 2;
      final startRadius = body.radius;

      for (int i = 0; i < 30; i++) {
        physics.step(0.016);
      }

      expect(body.radius, greaterThan(startRadius));
      expect(body.radius, lessThanOrEqualTo(body.targetRadius));
    });
  });
}
