import 'package:flutter/material.dart';

/// Clamps content width on wide (desktop/web) screens.
/// On phones the constraint never kicks in, so mobile layout is unchanged.
class CenteredBody extends StatelessWidget {
  static const double maxContentWidth = 640;

  final Widget child;

  const CenteredBody({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: child,
      ),
    );
  }
}
