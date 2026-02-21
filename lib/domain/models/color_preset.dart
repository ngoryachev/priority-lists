enum ColorPreset {
  red(0xFFE57373, 'Red'),
  blue(0xFF64B5F6, 'Blue'),
  green(0xFF81C784, 'Green'),
  orange(0xFFFFB74D, 'Orange'),
  purple(0xFFBA68C8, 'Purple'),
  teal(0xFF4DB6AC, 'Teal'),
  pink(0xFFF06292, 'Pink'),
  indigo(0xFF7986CB, 'Indigo');

  const ColorPreset(this.colorValue, this.label);

  final int colorValue;
  final String label;

  static ColorPreset fromColorValue(int value) =>
      ColorPreset.values.firstWhere(
        (c) => c.colorValue == value,
        orElse: () => throw ArgumentError('Invalid color value: $value'),
      );
}
