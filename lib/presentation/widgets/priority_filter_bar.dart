import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/priority.dart';
import '../utils/priority_colors.dart';
import '../view_models/filter_view_model.dart';

/// Four toggle-buttons "1" / "2" / "3" / "4" that drive the global
/// [FilterViewModel.level]. Designed to sit inside an [AppBar.actions].
class PriorityFilterBar extends StatelessWidget {
  const PriorityFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final filter = context.watch<FilterViewModel>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var level = FilterViewModel.minLevel;
              level <= FilterViewModel.maxLevel;
              level++)
            _FilterButton(
              level: level,
              isActive: filter.level == level,
              onTap: () => filter.setLevel(level),
            ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final int level;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterButton({
    required this.level,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // The button colour matches the priority at this level: level 1 → critical,
    // level 4 → low. That way the active button is also a hint of which
    // priorities are still visible.
    final color = priorityColor(Priority.fromValue(level));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: _tooltipFor(level),
        child: Material(
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
                  '$level',
                  style: TextStyle(
                    color: isActive ? Colors.white : color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _tooltipFor(int level) {
    switch (level) {
      case 1:
        return 'Only Critical';
      case 2:
        return 'Critical + High';
      case 3:
        return 'Critical + High + Medium';
      case 4:
      default:
        return 'Show All';
    }
  }
}
