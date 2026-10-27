import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/role.dart';
import '../../domain/repositories/current_role_repository.dart';

/// Durable, cross-device current role. Requires `005_current_role.sql`; when
/// that migration has not been applied the table is missing and every call
/// throws — which the view model swallows, so the selector keeps working for
/// the session without persisting.
class SupabaseCurrentRoleRepository implements CurrentRoleRepository {
  static const String table = 'user_role';

  final SupabaseClient _client;

  SupabaseCurrentRoleRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<Role?> load() async {
    final row = await _client
        .from(table)
        .select('role')
        .eq('user_id', _userId)
        .maybeSingle();
    return Role.fromId(row?['role'] as String?);
  }

  @override
  Future<void> save(Role role) async {
    // One row per user, overwritten in place — the previous role is not history.
    await _client.from(table).upsert({
      'user_id': _userId,
      'role': role.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }
}
