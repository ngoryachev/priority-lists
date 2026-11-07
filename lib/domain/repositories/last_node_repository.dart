/// Where the user left off: the id of the node whose level was last on screen.
///
/// Null [nodeId] means the top level, which is a real answer and not "nothing
/// stored" — the user walked back to the root and the next launch must open
/// there. [userId] is the Supabase id of whoever was signed in when the
/// pointer was written, so a pointer left behind by another account can be
/// recognised and ignored.
class LastNodePointer {
  final String userId;

  /// The node whose children were on screen; null for the top level.
  final String? nodeId;

  const LastNodePointer({required this.userId, this.nodeId});

  @override
  bool operator ==(Object other) =>
      other is LastNodePointer &&
      other.userId == userId &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(userId, nodeId);

  @override
  String toString() => 'LastNodePointer($userId, ${nodeId ?? 'root'})';
}

/// Stores the last opened node, one value per device.
///
/// Like `CurrentRoleRepository` this is a side record: the tree never reads it,
/// and losing it must never break the screen — callers treat every failure as
/// "nothing stored", which simply means the app opens at the root.
abstract class LastNodeRepository {
  /// The stored pointer, or null when nothing was ever written (or the stored
  /// value cannot be made sense of).
  Future<LastNodePointer?> load();

  /// Overwrites the stored pointer. Callers do not await this on the UI path.
  Future<void> save(LastNodePointer pointer);

  /// Forgets the pointer, so the next launch opens at the root.
  Future<void> clear();
}
