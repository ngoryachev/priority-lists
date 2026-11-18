import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/role_timeline.dart';
import '../view_models/node_tree_view_model.dart';
import '../view_models/role_time_view_model.dart';

/// A thin strip along the right edge: today, from the start of the day at the
/// top to now at the bottom, each counted stretch in the colour of the role
/// it went to — the role chips' colours. Uncounted time stays empty.
///
/// No labels and no interaction: a glance at how much of the day went where.
/// Renders nothing without a [RoleTimeViewModel].
class RoleTimeStrip extends StatelessWidget {
  static const double width = 4;

  const RoleTimeStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final roleTime = context.watch<RoleTimeViewModel?>();
    if (roleTime == null) return const SizedBox.shrink();
    final tree = context.watch<NodeTreeViewModel>().tree;
    final fallback = Theme.of(context).colorScheme.primary;
    final colors = <String, Color>{
      for (final span in roleTime.spans)
        if (tree.nodeById(span.roleId) case final role?)
          span.roleId: role.colorPreset == null
              ? fallback
              : Color(role.colorPreset!.colorValue),
    };
    return IgnorePointer(
      child: Semantics(
        label: 'Time per role today',
        child: SizedBox(
          width: width,
          child: CustomPaint(
            painter: _StripPainter(
              spans: roleTime.spans,
              colors: colors,
              dayStart: roleTime.dayStart,
              now: roleTime.now,
            ),
          ),
        ),
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  final List<RoleSpan> spans;
  final Map<String, Color> colors;
  final DateTime dayStart;
  final DateTime now;

  _StripPainter({
    required this.spans,
    required this.colors,
    required this.dayStart,
    required this.now,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = now.difference(dayStart).inMilliseconds;
    if (total <= 0) return;
    double y(DateTime at) =>
        size.height * at.difference(dayStart).inMilliseconds / total;
    for (final span in spans) {
      // A deleted role has no colour any more; its time stays blank.
      final color = colors[span.roleId];
      if (color == null) continue;
      canvas.drawRect(
        Rect.fromLTRB(0, y(span.start), size.width, y(span.end)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) => true;
}
