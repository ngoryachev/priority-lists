import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/role_timeline.dart';
import '../view_models/node_tree_view_model.dart';
import '../view_models/role_time_view_model.dart';

/// A thin strip along the right edge: today, from the start of the day at the
/// top to now at the bottom, each counted stretch in the colour of the role
/// it went to — the role chips' colours. Uncounted time stays empty.
///
/// A glance at how much of the day went where; how much exactly is there on
/// demand. Hovering (desktop, web) or tapping (touch) a stretch inside an
/// invisible band over the strip names its duration in a small chip to the
/// strip's left, which goes away three seconds after it came up. The band
/// only takes taps and hover: a drag that starts in it still scrolls the list,
/// and the label never costs a card underneath a tap.
///
/// Renders nothing without a [RoleTimeViewModel].
class RoleTimeStrip extends StatefulWidget {
  /// Painted width of the strip.
  static const double width = 4;

  /// Width of the invisible band that takes taps and hover — four pixels is
  /// no target for a finger.
  static const double hitWidth = 20;

  /// How long a label stays up after it came up.
  static const Duration showFor = Duration(seconds: 3);

  const RoleTimeStrip({super.key});

  @override
  State<RoleTimeStrip> createState() => _RoleTimeStripState();
}

class _RoleTimeStripState extends State<RoleTimeStrip> {
  /// The stretch whose duration is on screen, if any.
  RoleSpan? _labelled;
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  /// Puts [span]'s duration up, or takes the label down when there is nothing
  /// at the height the pointer went to. Landing on another stretch restarts
  /// the three seconds; staying on the same one changes nothing.
  void _show(RoleSpan? span) {
    if (span == _labelled) return;
    _hide?.cancel();
    setState(() => _labelled = span);
    if (span == null) return;
    // Counted from when it came up, not from when the pointer left: leaving
    // the band early is not a reason to lose the reading.
    _hide = Timer(RoleTimeStrip.showFor, () {
      if (mounted) setState(() => _labelled = null);
    });
  }

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
    final dayStart = roleTime.dayStart;
    final now = roleTime.now;
    final total = now.difference(dayStart).inMilliseconds;
    // A deleted role is not painted, so there is nothing to name at its
    // height either.
    final painted = [
      for (final span in roleTime.spans)
        if (colors.containsKey(span.roleId)) span,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        double fraction(DateTime at) =>
            total <= 0 ? 0 : at.difference(dayStart).inMilliseconds / total;
        RoleSpan? spanAt(double dy) {
          if (total <= 0 || height <= 0) return null;
          final at = dayStart.add(
            Duration(milliseconds: (total * dy / height).round()),
          );
          for (final span in painted) {
            if (!at.isBefore(span.start) && at.isBefore(span.end)) return span;
          }
          return null;
        }

        final labelled = _labelled;
        return Stack(
          children: [
            if (labelled != null)
              Positioned(
                // Left to right of the whole body: the chip is laid out
                // against the strip inside that, by _LabelLayout.
                left: 0,
                right: RoleTimeStrip.width,
                top: 0,
                bottom: 0,
                // IgnorePointer: the chip is far wider than the strip, and
                // none of that width may swallow a tap meant for a card.
                child: IgnorePointer(
                  child: CustomSingleChildLayout(
                    delegate: _LabelLayout(
                      height *
                          (fraction(labelled.start) + fraction(labelled.end)) /
                          2,
                    ),
                    child: _DurationChip(duration: labelled.duration),
                  ),
                ),
              ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: RoleTimeStrip.hitWidth,
              // Not an opaque mouse region: opaque to the mouse is opaque to
              // every pointer, and that would take the drag away from the
              // list too. The card beneath therefore still sees the hover —
              // the tap, which is what matters here, is still the band's.
              child: MouseRegion(
                opaque: false,
                onHover: (event) => _show(spanAt(event.localPosition.dy)),
                // Translucent, and the tap taken on up rather than on down:
                // the band wins a tap over the card beneath it, while a
                // vertical drag goes to the list as before.
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) => _show(spanAt(details.localPosition.dy)),
                  child: Semantics(
                    label: 'Time per role today',
                    child: Stack(
                      children: [
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          width: RoleTimeStrip.width,
                          child: CustomPaint(
                            painter: _StripPainter(
                              spans: roleTime.spans,
                              colors: colors,
                              dayStart: dayStart,
                              now: now,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The duration of one stretch, as a chip that stays readable over whatever
/// card content it lands on.
class _DurationChip extends StatelessWidget {
  final Duration duration;

  const _DurationChip({required this.duration});

  /// Hours and minutes, short: `1h 25m`, `2h`, `40m`, `<1m`.
  static String label(Duration duration) {
    if (duration < const Duration(minutes: 1)) return '<1m';
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 2,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(
            label(duration),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays the chip against the right edge of the strip's height, centred on
/// [centerY] but never hanging off the top or the bottom of it.
class _LabelLayout extends SingleChildLayoutDelegate {
  final double centerY;

  const _LabelLayout(this.centerY);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    size.width - childSize.width,
    (centerY - childSize.height / 2).clamp(
      0.0,
      (size.height - childSize.height).clamp(0.0, double.infinity),
    ),
  );

  @override
  bool shouldRelayout(_LabelLayout old) => old.centerY != centerY;
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
