import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:priority_lists/domain/models/color_preset.dart';
import 'package:priority_lists/domain/models/priority.dart';
import 'package:priority_lists/domain/models/priority_list.dart';
import 'package:priority_lists/presentation/widgets/bubble_view/bubble_physics.dart'
    as bp;

bp.Size _canvas = const bp.Size(400, 800);

PriorityList _makeList(String id, {Priority priority = Priority.medium}) {
  final now = DateTime.now();
  return PriorityList(
    id: id,
    name: 'List $id',
    colorPreset: ColorPreset.blue,
    priority: priority,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('BubblePhysics', () {
    late bp.BubblePhysics physics;

    setUp(() {
      physics = bp.BubblePhysics(
        canvasSize: _canvas,
        random: Random(42),
      );
    });

    test('syncWithLists creates bodies for each list', () {
      final lists = [_makeList('a'), _makeList('b'), _makeList('c')];
      physics.syncWithLists(lists);

      expect(physics.bodies.length, 3);
      expect(physics.bodies.containsKey('a'), true);
      expect(physics.bodies.containsKey('b'), true);
      expect(physics.bodies.containsKey('c'), true);
    });

    test('syncWithLists removes deleted lists', () {
      physics.syncWithLists([_makeList('a'), _makeList('b')]);
      expect(physics.bodies.length, 2);

      physics.syncWithLists([_makeList('a')]);
      expect(physics.bodies.length, 1);
      expect(physics.bodies.containsKey('b'), false);
    });

    test('syncWithLists updates targetRadius on priority change', () {
      physics.syncWithLists([_makeList('a', priority: Priority.low)]);
      final oldTarget = physics.bodies['a']!.targetRadius;

      physics.syncWithLists([_makeList('a', priority: Priority.critical)]);
      final newTarget = physics.bodies['a']!.targetRadius;

      expect(newTarget, greaterThan(oldTarget));
    });

    test('syncWithLists preserves position of existing bodies', () {
      physics.syncWithLists([_makeList('a')]);
      physics.bodies['a']!.x = 100;
      physics.bodies['a']!.y = 200;

      physics.syncWithLists([_makeList('a')]);
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
      physics.syncWithLists([_makeList('a')]);
      // Push body out of bounds
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
      physics.syncWithLists([_makeList('a'), _makeList('b')]);
      // Place them on top of each other
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
      physics.syncWithLists([_makeList('a')]);
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
      physics.syncWithLists([_makeList('a', priority: Priority.low)]);
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
