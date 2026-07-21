import 'package:flutter/material.dart';

import '../../../domain/models/priority.dart';
import '../../utils/priority_colors.dart';
import '../item_chips.dart';

class BubbleWidget extends StatelessWidget {
  final String name;
  final Color color;
  final double diameter;
  final String itemCountText;
  final List<String>? chipLabels;
  final VoidCallback onTap;
  final VoidCallback? onPriorityUp;
  final VoidCallback? onPriorityDown;
  final Priority? currentPriority;
  final ValueChanged<Priority>? onSetPriority;

  const BubbleWidget({
    super.key,
    required this.name,
    required this.color,
    required this.diameter,
    required this.itemCountText,
    this.chipLabels,
    required this.onTap,
    this.onPriorityUp,
    this.onPriorityDown,
    this.currentPriority,
    this.onSetPriority,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = (diameter * 0.11).clamp(10.0, 18.0);
    final iconSize = (diameter * 0.15).clamp(14.0, 22.0);
    final iconSlot = iconSize + 8;
    final levelButtonSize = (diameter * 0.13).clamp(14.0, 22.0);
    final levelFontSize = (levelButtonSize * 0.62).clamp(9.0, 13.0);
    final levelRowHeight = levelButtonSize;

    // Reserve vertical bands for the controls so the centered title doesn't
    // collide with the +/- buttons or the 1-4 row.
    final topInset = onPriorityUp != null ? iconSlot : 0.0;
    final bottomInset =
        (onPriorityDown != null ? iconSlot : 0.0) +
            (onSetPriority != null ? levelRowHeight + diameter * 0.04 : 0.0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.2),
          border: Border.all(color: color, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(diameter * 0.1),
          // Stack so the centred title stays visible at any bubble size and
          // the +/- buttons / 1-4 row overlay without flexing into it.
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
                child: Center(
                  // scaleDown keeps title+chips inside the bubble at any
                  // diameter instead of overflowing the reserved band.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: diameter * 0.8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: fontSize,
                              color: color.computeLuminance() > 0.5
                                  ? Colors.black87
                                  : color,
                            ),
                          ),
                          if (diameter >= 120 &&
                              chipLabels != null &&
                              chipLabels!.isNotEmpty) ...[
                            SizedBox(height: diameter * 0.03),
                            ItemChips(
                              labels: chipLabels!,
                              color: color,
                              maxChips: diameter > 220 ? 4 : 2,
                              maxTitleChars: 12,
                              fontSize: (diameter * 0.06).clamp(8.0, 10.0),
                              alignment: WrapAlignment.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (onPriorityUp != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildIconButton(Icons.add, onPriorityUp!, iconSize),
                  ),
                ),
              if (onSetPriority != null)
                Positioned(
                  bottom: onPriorityDown != null ? iconSlot : 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final p in Priority.values)
                          Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: diameter * 0.01),
                            child: _LevelButton(
                              priority: p,
                              isActive: currentPriority == p,
                              size: levelButtonSize,
                              fontSize: levelFontSize,
                              onTap: () => onSetPriority!(p),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (onPriorityDown != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _buildIconButton(
                        Icons.remove, onPriorityDown!, iconSize),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(
      IconData icon, VoidCallback onPressed, double iconSize) {
    return SizedBox(
      height: iconSize + 8,
      width: iconSize + 8,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(icon, size: iconSize),
        onPressed: onPressed,
        color: color,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _LevelButton extends StatelessWidget {
  final Priority priority;
  final bool isActive;
  final double size;
  final double fontSize;
  final VoidCallback onTap;

  const _LevelButton({
    required this.priority,
    required this.isActive,
    required this.size,
    required this.fontSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(priority);
    return Material(
      color: isActive ? color : color.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: color, width: isActive ? 0 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(
              '${priority.value}',
              style: TextStyle(
                color: isActive ? Colors.white : color,
                fontWeight: FontWeight.bold,
                fontSize: fontSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
