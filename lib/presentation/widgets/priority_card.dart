import 'package:flutter/material.dart';

import '../../domain/models/priority.dart';
import '../utils/priority_colors.dart';
import 'item_chips.dart';

class PriorityCard extends StatelessWidget {
  final String title;
  final String badgeLabel;
  final Color color;

  /// Number of nodes directly inside this one, shown next to the priority
  /// badge. Sits in the badge row rather than the subtitle so it survives on
  /// short tiles, where the column below is clipped away.
  final int? childCount;

  final String? subtitle;

  /// When non-empty, rendered as mini chips in place of [subtitle].
  final List<String>? chipLabels;
  final Color? backgroundColor;
  final double? fixedHeight;
  final Priority? currentPriority;

  /// Position in the enclosing [ReorderableListView]. When set, the card shows
  /// a drag handle; null outside a reorderable list.
  final int? dragIndex;

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
    this.childCount,
    this.subtitle,
    this.chipLabels,
    this.backgroundColor,
    this.fixedHeight,
    this.currentPriority,
    this.dragIndex,
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
            padding: EdgeInsets.all(
              _isCompact
                  ? 10
                  : _isShort
                  ? 12
                  : 16,
            ),
            // The priority-level row is overlaid via Stack so it doesn't eat
            // vertical space inside the Column — important for compact cards
            // (low/medium) where the Column is already tight.
            child: Stack(
              children: [
                Padding(
                  // Keep the column clear of the overlaid 1-4 row. This holds
                  // on compact tiles too: skipping it there let the buttons sit
                  // on top of the title, so tapping a short card's name set a
                  // priority instead of opening the node.
                  padding: EdgeInsets.only(
                    bottom: onSetPriority != null ? _levelRowHeight : 0,
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
                          if (childCount != null && childCount! > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.subdirectory_arrow_right,
                                      size: 12,
                                      color: color,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${childCount!}',
                                      style: TextStyle(
                                        color: color,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
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
                                  if (dragIndex != null)
                                    ReorderableDragStartListener(
                                      index: dragIndex!,
                                      // Tooltip doubles as the handle's
                                      // accessible name; a bare Icon would
                                      // reach a screen reader as nothing.
                                      child: Tooltip(
                                        message: 'Drag to reorder',
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 8,
                                          ),
                                          child: Icon(
                                            Icons.drag_indicator,
                                            size: 20,
                                            color: color.withValues(alpha: 0.7),
                                          ),
                                        ),
                                      ),
                                    ),
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
                                      tooltip: 'Move into another node',
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
                          // A compact tile has room for the badge row, one
                          // line of title and the 1-4 row — the large style
                          // simply gets clipped there.
                          style:
                              (_isCompact
                                      ? Theme.of(context).textTheme.titleMedium
                                      : Theme.of(context).textTheme.titleLarge)
                                  ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: _isCompact ? 1 : 2,
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
