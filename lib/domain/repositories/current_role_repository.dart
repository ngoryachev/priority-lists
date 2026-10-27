import '../models/role.dart';

/// Stores which role the user last picked, one value per user.
///
/// Like `ActivityLogRepository` this is a side record: the tree never reads it,
/// and losing it must never break the screen — callers treat every failure as
/// "no role stored".
abstract class CurrentRoleRepository {
  /// The stored role, or null when nothing was ever picked.
  Future<Role?> load();

  /// Overwrites the stored role. Callers do not await this on the UI path.
  Future<void> save(Role role);
}
