import 'package:flutter/foundation.dart';

import '../../domain/models/role.dart';
import '../../domain/repositories/current_role_repository.dart';

/// The single role the user is currently in, shared across screens.
///
/// Exclusive by construction: there is one slot, so picking a role replaces
/// whatever was there. Nothing is selected until the user picks something — a
/// preset would be a claim about the user the app cannot make.
///
/// Persistence is best-effort. The role is a marker, so a failing repository
/// (missing migration, offline) must never surface an error over the tree; it
/// only means the pick does not outlive the session.
class RoleViewModel extends ChangeNotifier {
  final CurrentRoleRepository? _repository;

  Role? _selected;

  /// Counts picks, so a slow [load] can tell whether the user chose a role
  /// while the read was in flight.
  int _picks = 0;

  RoleViewModel({CurrentRoleRepository? repository})
      : _repository = repository;

  Role? get selected => _selected;

  bool isSelected(Role role) => _selected == role;

  /// Picks [role]. Re-tapping the active chip is a no-op: with one slot there
  /// is nothing to deselect into.
  void select(Role role) {
    if (_selected == role) return;
    _selected = role;
    _picks++;
    notifyListeners();
    // Fire and forget: the UI is already showing the new role.
    _repository?.save(role).catchError((_) {});
  }

  /// Restores the stored role. Called once the user is signed in, since that is
  /// when the remote read can succeed.
  Future<void> load() async {
    final repository = _repository;
    if (repository == null) return;
    final picksBefore = _picks;
    final Role? stored;
    try {
      stored = await repository.load();
    } catch (_) {
      return;
    }
    // The user picked while the read was in flight: their tap is newer than
    // the stored row — and already on its way to it — so it wins. Without
    // this the screen would silently revert a tap the user just made.
    if (_picks != picksBefore) return;
    if (stored == null || stored == _selected) return;
    _selected = stored;
    notifyListeners();
  }
}
