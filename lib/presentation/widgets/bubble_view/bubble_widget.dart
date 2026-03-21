import 'package:flutter/material.dart';

class BubbleWidget extends StatelessWidget {
  final String name;
  final Color color;
  final double diameter;
  final String itemCountText;
  final VoidCallback onTap;
  final VoidCallback? onPriorityUp;
  final VoidCallback? onPriorityDown;

  const BubbleWidget({
    super.key,
    required this.name,
    required this.color,
    required this.diameter,
    required this.itemCountText,
    required this.onTap,
    this.onPriorityUp,
    this.onPriorityDown,
  });

  @override
  Widget build(BuildContext context) {
    final showControls = diameter >= 100;
    final showCount = diameter >= 80;
    final fontSize = (diameter * 0.11).clamp(10.0, 18.0);
    final iconSize = (diameter * 0.15).clamp(14.0, 22.0);

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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showControls && onPriorityUp != null)
                _buildIconButton(Icons.remove, onPriorityUp!, iconSize),
              Flexible(
                child: Text(
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
              ),
              if (showCount)
                Text(
                  itemCountText,
                  style: TextStyle(
                    fontSize: fontSize * 0.75,
                    color: Colors.grey.shade600,
                  ),
                ),
              if (showControls && onPriorityDown != null)
                _buildIconButton(Icons.add, onPriorityDown!, iconSize),
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
