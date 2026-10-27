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

  /// Writes are chained, like `ActivityLogger`'s: two quick taps issue two
  /// upserts against the same row, and unordered they can leave the role the
  /// user moved away from stored while the bar shows the one they ended on.
  Future<void> _queue = Future.value();

  RoleViewModel({CurrentRoleRepository? repository})
      : _repository = repository;

  Role? get selected => _selected;

  /// Completes once every pick made so far has been written (or failed).
  /// For tests, and for [load] to avoid reading across its own pending write.
  Future<void> get idle => _queue;

  bool isSelected(Role role) => _selected == role;

  /// Picks [role]. Re-tapping the active chip is a no-op: with one slot there
  /// is nothing to deselect into.
  void select(Role role) {
    if (_selected == role) return;
    _selected = role;
    _picks++;
    notifyListeners();
    final repository = _repository;
    if (repository == null) return;
    // Fire and forget: the UI is already showing the new role, and a marker
    // that cannot be stored must never surface as an error over the tree.
    _queue = _queue.then((_) => repository.save(role)).catchError((_) {});
  }

  /// Adopts the stored role — including the absence of one. Called once the
  /// user is signed in, since that is when the remote read can succeed.
  ///
  /// This view model outlives a sign-out (it is registered above the
  /// `MaterialApp`), so a read that comes back empty means "whoever just
  /// signed in never picked a role" and has to clear the slot: otherwise the
  /// previous account's marker would stay painted, and nothing in the UI can
  /// take it off.
  Future<void> load() async {
    final repository = _repository;
    if (repository == null) return;
    // Snapshot before the first await, not after: a tap made while we wait
    // for the queue below is as new as one made during the read, and its own
    // write is not part of the future we are about to await.
    final picksBefore = _picks;
    // Let a pending pick land first: reading across our own in-flight write
    // hands back the pre-pick row, which would revert the user's choice.
    await _queue;
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
    if (stored == _selected) return;
    _selected = stored;
    notifyListeners();
  }
}
