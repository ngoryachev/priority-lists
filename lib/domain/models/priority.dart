enum Priority {
  critical(1, 0.50, 'Critical'),
  high(2, 0.30, 'High'),
  medium(3, 0.20, 'Medium'),
  low(4, 0.10, 'Low');

  const Priority(this.value, this.screenHeightFraction, this.label);

  final int value;
  final double screenHeightFraction;
  final String label;

  static Priority fromValue(int value) =>
      Priority.values.firstWhere(
        (p) => p.value == value,
        orElse: () => throw ArgumentError('Invalid priority value: $value'),
      );
}
