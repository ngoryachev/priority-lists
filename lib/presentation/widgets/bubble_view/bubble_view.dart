import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../domain/models/priority_list.dart';
import 'bubble_physics.dart' as bp;
import 'bubble_widget.dart';

class BubbleView extends StatefulWidget {
  final List<PriorityList> lists;
  final void Function(PriorityList) onTap;
  final void Function(PriorityList updated) onUpdateList;

  const BubbleView({
    super.key,
    required this.lists,
    required this.onTap,
    required this.onUpdateList,
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
    // Cap dt to avoid physics explosions after pauses
    _physics!.step(dt.clamp(0, 0.05));
    setState(() {});
  }

  PriorityList? _listById(String id) {
    for (final list in widget.lists) {
      if (list.id == id) return list;
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
        _physics!.syncWithLists(widget.lists);

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final body in _physics!.bodies.values)
              if (_listById(body.id) case final list?)
                Positioned(
                  left: body.x - body.radius,
                  top: body.y - body.radius,
                  child: BubbleWidget(
                    name: list.name,
                    color: Color(list.colorPreset.colorValue),
                    diameter: body.radius * 2,
                    itemCountText:
                        '${list.items.length} item${list.items.length == 1 ? '' : 's'}',
                    onTap: () => widget.onTap(list),
                    onPriorityUp: list.priority.higher != null
                        ? () => widget.onUpdateList(list.copyWith(
                              priority: list.priority.higher!,
                              updatedAt: DateTime.now(),
                            ))
                        : null,
                    onPriorityDown: list.priority.lower != null
                        ? () => widget.onUpdateList(list.copyWith(
                              priority: list.priority.lower!,
                              updatedAt: DateTime.now(),
                            ))
                        : null,
                  ),
                ),
          ],
        );
      },
    );
  }
}
