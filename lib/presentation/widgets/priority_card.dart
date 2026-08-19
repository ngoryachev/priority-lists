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
    this.onSetPriority,
    this.onExtract,
    this.onMoveInto,
  });

  /// Height of the overlaid 1-4 priority row, reserved at the bottom of the
  /// column so chips never slide underneath it.
  static const double _levelRowHeight = 32;

  /// Below this height the card only has room for the badge row and the
  /// title, so chips and the subtitle are dropped. The threshold sits just
  /// under a medium tile on a phone (20% of an 800dp screen) so medium lists
  /// show their items too.
  bool get _isCompact => fixedHeight != null && fixedHeight! < 155;

  /// Medium tiles clear [_isCompact] by only a few pixels, so they trade some
  /// padding for the row of chips that would otherwise be clipped.
  bool get _isShort => fixedHeight != null && fixedHeight! < 190;

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
            padding: EdgeInsets.all(_isShort ? 12 : 16),
            // The priority-level row is overlaid via Stack so it doesn't eat
            // vertical space inside the Column — important for compact cards
            // (low/medium) where the Column is already tight.
            child: Stack(
              children: [
                Padding(
                  // Keep the column clear of the overlaid 1-4 row; without it
                  // the last chips render underneath those buttons.
                  padding: EdgeInsets.only(
                    bottom: onSetPriority != null && !_isCompact
                        ? _levelRowHeight
                        : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
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
                          // Expanded (not Spacer + Flexible, which would split
                          // the free space) hands the actions everything left of
                          // the badge; reverse keeps them right-aligned and lets
                          // them scroll instead of overflowing when a large text
                          // scale leaves the row too narrow.
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (onExtract != null)
                                    _CardAction(
                                      icon: Icons.open_in_new,
                                      onPressed: onExtract,
                                      tooltip: 'Extract to top level',
                                    ),
                                  if (onMoveInto != null)
                                    _CardAction(
                                      icon: Icons.move_to_inbox,
                                      onPressed: onMoveInto,
                                      tooltip: 'Move into list',
                                    ),
                                  if (onEdit != null)
                                    _CardAction(
                                      icon: Icons.edit_outlined,
                                      onPressed: onEdit,
                                      tooltip: 'Edit',
                                    ),
                                  if (onDelete != null)
                                    _CardAction(
                                      icon: Icons.delete_outline,
                                      onPressed: onDelete,
                                      tooltip: 'Delete',
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: _isShort ? 4 : 8),
                      Flexible(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!_isCompact &&
                          chipLabels != null &&
                          chipLabels!.isNotEmpty) ...[
                        SizedBox(height: _isShort ? 3 : 6),
                        Flexible(
                          child: ItemChips(labels: chipLabels!, color: color),
                        ),
                      ] else if (!_isCompact &&
                          subtitle != null &&
                          subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Flexible(
                          child: Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey.shade600),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 5,
                          ),
                        ),
                      ],
                    ],
                  ),
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

/// Compact icon button used for the card's action row.
class _CardAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  const _CardAction({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
    );
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
