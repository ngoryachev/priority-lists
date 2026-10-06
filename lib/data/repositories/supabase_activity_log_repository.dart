import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/activity_event.dart';
import '../../domain/repositories/activity_log_repository.dart';

/// Durable, cross-device log. Requires `004_activity_log.sql`; when that
/// migration has not been applied the table is missing and every call throws —
/// which the logger swallows, so the tree keeps working without a log.
class SupabaseActivityLogRepository implements ActivityLogRepository {
  static const String table = 'activity_log';

  final SupabaseClient _client;

  SupabaseActivityLogRepository(this._client);

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<void> append(ActivityEvent event) async {
    await _client.from(table).insert({
      'id': event.id,
      'user_id': _userId,
      'happened_at': event.at.toUtc().toIso8601String(),
      'action': event.action.name,
      'node_id': event.nodeId,
      'node_title': event.nodeTitle,
      'path': event.path,
      'details': event.details,
    });
  }

  @override
  Future<List<ActivityEvent>> recent({int limit = 500, DateTime? since}) async {
    var query = _client.from(table).select().eq('user_id', _userId);
    if (since != null) {
      query = query.gte('happened_at', since.toUtc().toIso8601String());
    }
    final rows = await query.order('happened_at', ascending: false).limit(limit);
    return rows.map(_toEntity).toList();
  }

  ActivityEvent _toEntity(Map<String, dynamic> json) => ActivityEvent(
        id: json['id'] as String,
        at: DateTime.parse(json['happened_at'] as String).toLocal(),
        action: ActivityAction.fromName(json['action'] as String),
        nodeId: json['node_id'] as String?,
        nodeTitle: json['node_title'] as String? ?? '',
        path: [
          for (final part in (json['path'] as List<dynamic>? ?? const []))
            part as String,
        ],
        details: json['details'] as String? ?? '',
      );
}
