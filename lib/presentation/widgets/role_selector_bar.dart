import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/models/role.dart';
import '../view_models/role_view_model.dart';

/// One chip per [Role], exactly one of them active, driving
/// [RoleViewModel.selected]. Designed to sit directly under an [AppBar].
///
/// The row scrolls horizontally rather than wrapping: on a phone that keeps the
/// bar one line tall, so the list below it does not jump between one and two
/// rows of chrome as roles are picked.
class RoleSelectorBar extends StatelessWidget {
  const RoleSelectorBar({super.key});

  @override
  Widget build(BuildContext context) {
    // Nullable lookup: the selector is an optional extra, and screens built
    // without it (tests, older entry points) simply render nothing.
    final roles = context.watch<RoleViewModel?>();
    if (roles == null) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            for (final role in Role.values)
              _RoleChip(
                role: role,
                isActive: roles.isSelected(role),
                onTap: () => roles.select(role),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final Role role;
  final bool isActive;
  final VoidCallback onTap;

  const _RoleChip({
    required this.role,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Roles carry no colour of their own (unlike priorities), so the active
    // chip borrows the theme's accent.
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: role.description,
        child: ChoiceChip(
          label: Text(role.label),
          selected: isActive,
          onSelected: (_) => onTap(),
          selectedColor: scheme.primary,
          labelStyle: TextStyle(
            color: isActive ? scheme.onPrimary : scheme.onSurface,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
          showCheckmark: false,
          side: BorderSide(
            color: isActive ? scheme.primary : scheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}
