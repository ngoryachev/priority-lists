import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import '../../domain/models/role.dart';
import '../view_models/role_view_model.dart';

/// One chip per [Role], exactly one of them active, driving
/// [RoleViewModel.selected]. Designed to sit directly under an [AppBar].
///
/// The row scrolls horizontally rather than wrapping: on a phone that keeps the
/// bar one line tall, so the list below it does not jump between one and two
/// rows of chrome as roles are picked. Six chips do not fit a phone's width, so
/// the active one is scrolled into view — a marker nobody can see is no marker.
class RoleSelectorBar extends StatefulWidget {
  const RoleSelectorBar({super.key});

  @override
  State<RoleSelectorBar> createState() => _RoleSelectorBarState();
}

class _RoleSelectorBarState extends State<RoleSelectorBar> {
  final Map<Role, GlobalKey> _chipKeys = {
    for (final role in Role.values) role: GlobalKey(),
  };

  /// The role the row was last scrolled to, so a rebuild that changes nothing
  /// does not fight the user's own scrolling.
  Role? _revealed;

  @override
  Widget build(BuildContext context) {
    // Nullable lookup: the selector is an optional extra, and screens built
    // without it (tests, older entry points) simply render nothing.
    final roles = context.watch<RoleViewModel?>();
    if (roles == null) return const SizedBox.shrink();

    _revealAfterFrame(roles.selected);

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            for (final role in Role.values)
              _RoleChip(
                key: _chipKeys[role],
                role: role,
                isActive: roles.isSelected(role),
                onTap: () => roles.select(role),
              ),
          ],
        ),
      ),
    );
  }

  /// Brings [selected] into view once the frame that paints it is laid out —
  /// which is how a role restored from storage (or picked on the level above)
  /// becomes visible when it sits in the trailing, off-screen part of the row.
  void _revealAfterFrame(Role? selected) {
    if (selected == _revealed) return;
    _revealed = selected;
    if (selected == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _chipKeys[selected]?.currentContext;
      if (!mounted || chipContext == null) return;
      if (_isFullyVisible(chipContext)) return;
      Scrollable.ensureVisible(
        chipContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// Whether the chip is already wholly inside the viewport. Without this the
  /// row would re-centre on every tap, including taps on chips in plain sight.
  bool _isFullyVisible(BuildContext chipContext) {
    final box = chipContext.findRenderObject();
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    final position = Scrollable.maybeOf(chipContext)?.position;
    if (box == null || viewport == null || position == null) return true;
    // The scroll offsets at which the chip's leading / trailing edge touches
    // the matching edge of the viewport; between them it is fully in view.
    final leading = viewport.getOffsetToReveal(box, 0).offset;
    final trailing = viewport.getOffsetToReveal(box, 1).offset;
    return position.pixels >= math.min(leading, trailing) &&
        position.pixels <= math.max(leading, trailing);
  }
}

class _RoleChip extends StatelessWidget {
  final Role role;
  final bool isActive;
  final VoidCallback onTap;

  const _RoleChip({
    super.key,
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
