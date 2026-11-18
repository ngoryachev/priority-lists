/// Stores the page every card was swiped to: node id → id of the child its
/// card shows. A node missing from the map sits on page 0, its own face.
///
/// A side record, like `LastNodeRepository`: losing it must never break the
/// screen, and callers treat every failure as "nothing stored".
abstract class CardPageRepository {
  /// The stored pages, or null when nothing was ever written.
  Future<Map<String, String>?> load();

  /// Overwrites the stored pages with [pages].
  Future<void> save(Map<String, String> pages);
}
