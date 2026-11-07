import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/last_node_repository.dart';

/// Device-local last opened node, kept in `shared_preferences` so it survives
/// a restart on every platform the app ships to — including the web build,
/// where it lands in local storage.
///
/// One JSON string under a single key, overwritten in place: the pointer is
/// where the user is, not where they have been.
class SharedPreferencesLastNodeRepository implements LastNodeRepository {
  static const String key = 'last_node';

  final Future<SharedPreferences> Function() _prefs;

  SharedPreferencesLastNodeRepository({
    Future<SharedPreferences> Function()? prefs,
  }) : _prefs = prefs ?? SharedPreferences.getInstance;

  @override
  Future<LastNodePointer?> load() async {
    final raw = (await _prefs()).getString(key);
    if (raw == null) return null;
    // Anything we cannot read back is treated as nothing stored: a value left
    // by an older or broken write must not keep the app from opening.
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final userId = decoded['userId'];
    final nodeId = decoded['nodeId'];
    if (userId is! String || userId.isEmpty) return null;
    if (nodeId != null && nodeId is! String) return null;
    return LastNodePointer(userId: userId, nodeId: nodeId as String?);
  }

  @override
  Future<void> save(LastNodePointer pointer) async {
    await (await _prefs()).setString(
      key,
      // The key is absent rather than null for the root, which reads back the
      // same way and keeps the stored value minimal.
      jsonEncode({
        'userId': pointer.userId,
        if (pointer.nodeId != null) 'nodeId': pointer.nodeId,
      }),
    );
  }

  @override
  Future<void> clear() async => (await _prefs()).remove(key);
}
