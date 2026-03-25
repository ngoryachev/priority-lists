import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' hide Priority;

import '../../../domain/models/priority.dart';
import 'bubble_physics.dart' as bp;
import 'bubble_widget.dart';

class BubbleEntry {
  final String id;
  final String name;
  final Color color;
  final Priority priority;
  final String? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onPriorityUp;
  final VoidCallback? onPriorityDown;

  const BubbleEntry({
    required this.id,
    required this.name,
    required this.color,
    required this.priority,
    this.subtitle,
    this.onTap,
    this.onPriorityUp,
    this.onPriorityDown,
  });
}

class BubbleView extends StatefulWidget {
  final List<BubbleEntry> entries;

  const BubbleView({
    super.key,
    required this.entries,
  });

  @override
  State<BubbleView> createState() => _BubbleViewState();
}

class _BubbleViewState extends State<BubbleView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  bp.BubblePhysics? _physics;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_physics == null) return;
    final dt = _lastTick == Duration.zero
        ? 0.016
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _physics!.step(dt.clamp(0, 0.05));
    setState(() {});
  }

  BubbleEntry? _entryById(String id) {
    for (final e in widget.entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = bp.Size(constraints.maxWidth, constraints.maxHeight);

        if (_physics == null) {
          _physics = bp.BubblePhysics(canvasSize: size);
        } else {
          _physics!.canvasSize = size;
        }

        final entries = <String, Priority>{};
        for (final e in widget.entries) {
          entries[e.id] = e.priority;
        }
        _physics!.sync(entries);

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final body in _physics!.bodies.values)
              if (_entryById(body.id) case final entry?)
                Positioned(
                  left: body.x - body.radius,
                  top: body.y - body.radius,
                  child: BubbleWidget(
                    name: entry.name,
                    color: entry.color,
                    diameter: body.radius * 2,
                    itemCountText: entry.subtitle ?? '',
                    onTap: entry.onTap ?? () {},
                    onPriorityUp: entry.onPriorityUp,
                    onPriorityDown: entry.onPriorityDown,
                  ),
                ),
          ],
        );
      },
    );
  }
}
