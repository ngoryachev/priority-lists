import 'dart:math';

import '../../../domain/models/priority.dart';
import '../../../domain/models/priority_list.dart';

class BubbleBody {
  final String id;
  double x;
  double y;
  double vx;
  double vy;
  double radius;
  double targetRadius;
  final double driftPhase;
  final double driftSpeed;

  BubbleBody({
    required this.id,
    required this.x,
    required this.y,
    this.vx = 0,
    this.vy = 0,
    required this.radius,
    required this.targetRadius,
    required this.driftPhase,
    required this.driftSpeed,
  });
}

class BubblePhysics {
  final Map<String, BubbleBody> bodies = {};
  final Random _random;
  Size canvasSize;
  double _elapsed = 0;

  static const double _driftForce = 8.0;
  static const double _damping = 0.97;
  static const double _radiusLerpSpeed = 0.08;
  static const double _collisionPush = 0.5;

  BubblePhysics({required this.canvasSize, Random? random})
      : _random = random ?? Random();

  static double radiusForPriority(Priority p, Size canvasSize) {
    final minDim = min(canvasSize.width, canvasSize.height);
    final baseRadius = minDim * 0.06;
    final scaled = minDim * 0.16 * sqrt(p.screenHeightFraction / 0.50);
    return baseRadius + scaled;
  }

  void syncWithLists(List<PriorityList> lists) {
    final activeIds = <String>{};

    for (final list in lists) {
      activeIds.add(list.id);
      final targetR = radiusForPriority(list.priority, canvasSize);

      if (bodies.containsKey(list.id)) {
        bodies[list.id]!.targetRadius = targetR;
      } else {
        final pos = _findNonOverlappingPosition(targetR);
        bodies[list.id] = BubbleBody(
          id: list.id,
          x: pos.x,
          y: pos.y,
          radius: targetR,
          targetRadius: targetR,
          driftPhase: _random.nextDouble() * 2 * pi,
          driftSpeed: 0.3 + _random.nextDouble() * 0.5,
        );
      }
    }

    bodies.removeWhere((id, _) => !activeIds.contains(id));
  }

  void step(double dt) {
    _elapsed += dt;

    for (final body in bodies.values) {
      // Sinusoidal drift
      body.vx += sin(_elapsed * body.driftSpeed + body.driftPhase) * _driftForce * dt;
      body.vy += cos(_elapsed * body.driftSpeed * 0.8 + body.driftPhase + 1.5) * _driftForce * dt;

      // Damping
      body.vx *= _damping;
      body.vy *= _damping;

      // Radius lerp
      body.radius += (body.targetRadius - body.radius) * _radiusLerpSpeed;
    }

    // Collision resolution
    final bodyList = bodies.values.toList();
    for (int i = 0; i < bodyList.length; i++) {
      for (int j = i + 1; j < bodyList.length; j++) {
        _resolveCollision(bodyList[i], bodyList[j]);
      }
    }

    // Position update + boundary clamping
    for (final body in bodies.values) {
      body.x += body.vx * dt;
      body.y += body.vy * dt;
      _clampToBounds(body);
    }
  }

  void _resolveCollision(BubbleBody a, BubbleBody b) {
    final dx = b.x - a.x;
    final dy = b.y - a.y;
    final dist = sqrt(dx * dx + dy * dy);
    final minDist = a.radius + b.radius;

    if (dist < minDist && dist > 0) {
      final overlap = minDist - dist;
      final nx = dx / dist;
      final ny = dy / dist;
      final push = overlap * _collisionPush;
      a.x -= nx * push;
      a.y -= ny * push;
      b.x += nx * push;
      b.y += ny * push;
    }
  }

  void _clampToBounds(BubbleBody body) {
    if (body.x - body.radius < 0) {
      body.x = body.radius;
      body.vx = body.vx.abs() * 0.3;
    }
    if (body.x + body.radius > canvasSize.width) {
      body.x = canvasSize.width - body.radius;
      body.vx = -body.vx.abs() * 0.3;
    }
    if (body.y - body.radius < 0) {
      body.y = body.radius;
      body.vy = body.vy.abs() * 0.3;
    }
    if (body.y + body.radius > canvasSize.height) {
      body.y = canvasSize.height - body.radius;
      body.vy = -body.vy.abs() * 0.3;
    }
  }

  ({double x, double y}) _findNonOverlappingPosition(double radius) {
    for (int attempt = 0; attempt < 30; attempt++) {
      final x = radius + _random.nextDouble() * (canvasSize.width - 2 * radius);
      final y = radius + _random.nextDouble() * (canvasSize.height - 2 * radius);

      bool overlaps = false;
      for (final body in bodies.values) {
        final dx = x - body.x;
        final dy = y - body.y;
        if (sqrt(dx * dx + dy * dy) < radius + body.radius + 4) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) return (x: x, y: y);
    }

    // Fallback: center with offset
    return (
      x: canvasSize.width / 2 + (_random.nextDouble() - 0.5) * 40,
      y: canvasSize.height / 2 + (_random.nextDouble() - 0.5) * 40,
    );
  }
}

class Size {
  final double width;
  final double height;
  const Size(this.width, this.height);
}
