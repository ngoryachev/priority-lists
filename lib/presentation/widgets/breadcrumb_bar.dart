import 'package:flutter/material.dart';

import '../../domain/models/priority_node.dart';
import '../utils/priority_colors.dart';

/// Root-to-current trail shown under the app bar once you are inside the tree.
///
/// Tapping a crumb jumps straight back to that level. Because every level is a
/// pushed route named `node/<id>`, that is a `popUntil` rather than a new push —
/// so the stack never grows while walking back up.
class BreadcrumbBar extends StatelessWidget {
  /// Ancestors of the current level, root first, excluding the current node.
  final List<PriorityNode> ancestors;

  /// Label for the top level, used by the leading crumb.
  final String rootLabel;

  const BreadcrumbBar({
    super.key,
    required this.ancestors,
    this.rootLabel = 'All',
  });

  static const double height = 36;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      height: height,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _crumb(
              context,
              label: rootLabel,
              color: onSurface,
              onTap: () => _jumpTo(context, null),
            ),
            for (final node in ancestors) ...[
              Icon(Icons.chevron_right, size: 16, color: onSurface),
              _crumb(
                context,
                label: node.title,
                color: priorityColor(node.priority),
                onTap: () => _jumpTo(context, node.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _crumb(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  static String routeName(String? nodeId) => 'node/${nodeId ?? 'root'}';

  void _jumpTo(BuildContext context, String? nodeId) {
    Navigator.of(context).popUntil(
      (route) => route.settings.name == routeName(nodeId) || route.isFirst,
    );
  }
}
