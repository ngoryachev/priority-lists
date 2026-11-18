import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/card_page_repository.dart';
import '../../domain/repositories/last_node_repository.dart';

/// The server-side position — the last opened node and the card pages — kept
/// in one `user_view_state` row per user (`007_view_state.sql`), so it follows
/// the user across devices.
///
/// Each write touches only its own column: an upsert updates just the columns
/// it is given, so the node pointer and the card pages never overwrite each
/// other. Without a signed-in user there is no row: reads answer "nothing
/// stored" and writes throw, which every caller swallows.
abstract class _SupabaseViewState {
  static const String table = 'user_view_state';

  final SupabaseClient _client;

  _SupabaseViewState(this._client);

  String? get _userId => _client.auth.currentUser?.id;

  String _requireUser() {
    final userId = _userId;
    if (userId == null) throw StateError('No signed-in user');
    return userId;
  }

  Future<Map<String, dynamic>?> _row(String userId, String column) {
    return _client
        .from(table)
        .select(column)
        .eq('user_id', userId)
        .maybeSingle();
  }

  Future<void> _write(String userId, Map<String, dynamic> values) async {
    await _client.from(table).upsert({
      'user_id': userId,
      ...values,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

/// Last opened node, shared by every device of the account.
class SupabaseLastNodeRepository extends _SupabaseViewState
    implements LastNodeRepository {
  SupabaseLastNodeRepository(super.client);

  @override
  Future<LastNodePointer?> load() async {
    final userId = _userId;
    if (userId == null) return null;
    final row = await _row(userId, 'last_node_id');
    if (row == null) return null;
    final nodeId = row['last_node_id'];
    return LastNodePointer(
      userId: userId,
      nodeId: nodeId is String && nodeId.isNotEmpty ? nodeId : null,
    );
  }

  @override
  Future<void> save(LastNodePointer pointer) async {
    final userId = _requireUser();
    // A pointer written for another account must not land in this one's row.
    if (pointer.userId != userId) return;
    await _write(userId, {'last_node_id': pointer.nodeId});
  }

  @override
  Future<void> clear() async {
    await _write(_requireUser(), {'last_node_id': null});
  }
}

/// Card pages, shared by every device of the account.
class SupabaseCardPageRepository extends _SupabaseViewState
    implements CardPageRepository {
  SupabaseCardPageRepository(super.client);

  @override
  Future<Map<String, String>?> load() async {
    final userId = _userId;
    if (userId == null) return null;
    final row = await _row(userId, 'card_pages');
    if (row == null) return null;
    final raw = row['card_pages'];
    if (raw is! Map) return null;
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  }

  @override
  Future<void> save(Map<String, String> pages) async {
    await _write(_requireUser(), {'card_pages': pages});
  }
}
