/// A node's working state, orthogonal to its 1-4 priority.
///
/// Priority says how much something matters; a mark says what is happening to
/// it right now. The two never interact: setting or clearing a mark leaves the
/// priority, the manual position and the creation time exactly as they were.
enum NodeMark {
  flame('flame', '🔥', 'In progress'),
  ice('ice', '🧊', 'Blocked');

  const NodeMark(this.value, this.emoji, this.label);

  /// What gets stored — in the JSON file and in the `nodes.mark` column. Spelt
  /// out rather than taken from [name] so renaming the enum cannot silently
  /// orphan every stored mark.
  final String value;

  final String emoji;
  final String label;

  /// Null instead of throwing, for marks read back from storage: a value this
  /// build does not know (written by a newer one, or absent altogether)
  /// degrades to "unmarked" rather than breaking the whole tree load — the
  /// same tolerance as `ColorPreset.tryFromColorValue`.
  static NodeMark? tryFromValue(String? value) {
    if (value == null) return null;
    for (final mark in NodeMark.values) {
      if (mark.value == value) return mark;
    }
    return null;
  }
}
