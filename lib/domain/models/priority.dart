enum Priority {
  critical(1, 0.20, 0.50, 'Critical'),
  high(2, 0.20, 0.30, 'High'),
  medium(3, 0.20, 0.20, 'Medium'),
  low(4, 0.10, 0.10, 'Low');

  const Priority(
    this.value,
    this.cardHeightFraction,
    this.bubbleWeight,
    this.label,
  );

  final int value;

  /// Share of the screen height a list tile takes. Critical, high and medium
  /// deliberately share one height: colour and the badge already carry the
  /// priority, and oversized tiles pushed everything else off the screen —
  /// which defeats the point of a tree you scan level by level. Low stays
  /// half-height so noise stays visually cheap.
  final double cardHeightFraction;

  /// Relative size of a bubble on the canvas, where size *is* the encoding —
  /// unlike tiles, bubbles have room to differ.
  final double bubbleWeight;

  final String label;

  /// Returns the next higher priority, or null if already critical.
  Priority? get higher => value > 1 ? fromValue(value - 1) : null;

  /// Returns the next lower priority, or null if already low.
  Priority? get lower => value < 4 ? fromValue(value + 1) : null;

  static Priority fromValue(int value) =>
      Priority.values.firstWhere(
        (p) => p.value == value,
        orElse: () => throw ArgumentError('Invalid priority value: $value'),
      );
}
