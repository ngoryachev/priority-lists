import 'package:flutter/material.dart';

import '../../domain/models/priority.dart';
import '../../domain/models/priority_item.dart';

class PriorityItemCard extends StatelessWidget {
  final PriorityItem item;
  final double height;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const PriorityItemCard({
    super.key,
    required this.item,
    required this.height,
    required this.onEdit,
    required this.onDelete,
  });

  Color _priorityColor() {
    return switch (item.priority) {
      Priority.critical => Colors.red.shade400,
      Priority.high => Colors.orange.shade400,
      Priority.medium => Colors.blue.shade400,
      Priority.low => Colors.grey.shade400,
    };
  }

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor();

    return SizedBox(
      height: height,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
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
                        item.priority.label,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: onEdit,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: onDelete,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      item.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
