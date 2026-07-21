import 'package:flutter/material.dart';

import '../../domain/models/priority.dart';
import '../utils/priority_colors.dart';
import 'item_chips.dart';

class PriorityCard extends StatelessWidget {
  final String title;
  final String badgeLabel;
  final Color color;
  final String? subtitle;

  /// When non-empty, rendered as mini chips in place of [subtitle].
  final List<String>? chipLabels;
  final Color? backgroundColor;
  final double? fixedHeight;
  final Priority? currentPriority;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onPriorityUp;
  final VoidCallback? onPriorityDown;
  final ValueChanged<Priority>? onSetPriority;
  final VoidCallback? onExtract;
  final VoidCallback? onMoveInto;

  const PriorityCard({
    super.key,
    required this.title,
    required this.badgeLabel,
    required this.color,
    this.subtitle,
    this.chipLabels,
    this.backgroundColor,
    this.fixedHeight,
    this.currentPriority,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onPriorityUp,
    this.onPriorityDown,
    this.onSetPriority,
    this.onExtract,
    this.onMoveInto,
  });

  bool get _isCompact => fixedHeight != null && fixedHeight! < 150;

  @override
  Widget build(BuildContext context) {
    Widget card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: backgroundColor,
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            // The priority-level row is overlaid via Stack so it doesn't eat
            // vertical space inside the Column — important for compact cards
            // (low/medium) where the Column is already tight.
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                          onPressed: onPriorityUp,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Increase priority',
                        ),
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                          onPressed: onPriorityDown,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Decrease priority',
                        ),
                        if (onExtract != null)
                          IconButton(
                            icon: const Icon(Icons.open_in_new, size: 20),
                            onPressed: onExtract,
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Extract to top level',
                          ),
                        if (onMoveInto != null)
                          IconButton(
                            icon: const Icon(Icons.move_to_inbox, size: 20),
                            onPressed: onMoveInto,
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Move into list',
                          ),
                        if (onEdit != null)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            onPressed: onEdit,
                            visualDensity: VisualDensity.compact,
                          ),
                        if (onDelete != null)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: onDelete,
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!_isCompact &&
                        chipLabels != null &&
                        chipLabels!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Flexible(
                        child: ItemChips(
                          labels: chipLabels!,
                          color: color,
                        ),
                      ),
                    ] else if (!_isCompact &&
                        subtitle != null &&
                        subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Flexible(
                        child: Text(
                          subtitle!,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 5,
                        ),
                      ),
                    ],
                  ],
                ),
                if (onSetPriority != null)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: _PriorityLevelRow(
                      current: currentPriority,
                      onSelect: onSetPriority!,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    if (fixedHeight != null) {
      return SizedBox(height: fixedHeight, child: card);
    }
    return card;
  }
}

/// Row of four square buttons "1" / "2" / "3" / "4" that directly assign a
/// [Priority] without going through up/down increments.
class _PriorityLevelRow extends StatelessWidget {
  final Priority? current;
  final ValueChanged<Priority> onSelect;

  const _PriorityLevelRow({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in Priority.values)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _PriorityLevelButton(
              priority: p,
              isActive: current == p,
              onTap: () => onSelect(p),
            ),
          ),
      ],
    );
  }
}

class _PriorityLevelButton extends StatelessWidget {
  final Priority priority;
  final bool isActive;
  final VoidCallback onTap;

  const _PriorityLevelButton({
    required this.priority,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(priority);
    return Material(
      color: isActive ? color : color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: color, width: isActive ? 0 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Text(
              '${priority.value}',
              style: TextStyle(
                color: isActive ? Colors.white : color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
