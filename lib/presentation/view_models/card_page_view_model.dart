import 'package:flutter/foundation.dart';

import '../../domain/repositories/card_page_repository.dart';

/// Remembers which horizontal page every list tile was left on.
///
/// A tile on [NodeScreen]'s list browses its own children sideways; the page
/// is stored by *child id*, not by index, because a priority write re-sorts
/// the children under the user's thumb and the card has to stay on the same
/// child while its position in the row changes.
///
/// Not a [ChangeNotifier], like `LastNodeViewModel`: a swipe is already on
/// screen when it is recorded, so nothing is rebuilt for it. The one change
/// the screens do have to pick up is pages arriving from another device —
/// [reload] — and that is announced through [revision].
///
/// With a [CardPageRepository] the pages follow the user across launches and
/// devices; persistence is best-effort, and a store that fails only means the
/// pages are remembered for the lifetime of the process.
class CardPageViewModel {
  final CardPageRepository? _repository;

  /// Node id → the id of the child whose page that node's card sits on. A
  /// node missing from the map sits on page 0, its own face.
  final Map<String, String> _childByNode = {};

  /// Writes are chained so an older map can never land after a newer one.
  Future<void> _queue = Future.value();

  /// Bumped whenever [reload] replaces the pages, so the screens rebuild their
  /// cards onto the pages another device left.
  final ValueNotifier<int> revision = ValueNotifier(0);

  CardPageViewModel({CardPageRepository? repository})
    : _repository = repository;

  /// Completes once every page recorded so far has been written (or failed).
  Future<void> get idle => _queue;

  /// The child [nodeId]'s card was left on, or null for page 0.
  String? childFor(String nodeId) => _childByNode[nodeId];

  /// Records that [nodeId]'s card now shows [childId]; null forgets it, which
  /// is what a swipe back to page 0 means.
  void remember(String nodeId, String? childId) {
    if (childFor(nodeId) == childId) return;
    if (childId == null) {
      _childByNode.remove(nodeId);
    } else {
      _childByNode[nodeId] = childId;
    }
    final repository = _repository;
    if (repository == null) return;
    final snapshot = Map<String, String>.of(_childByNode);
    _queue = _queue.then((_) => repository.save(snapshot)).catchError((_) {});
  }

  /// Replaces the pages with the stored ones — the last device to swipe wins.
  /// Keeps the current pages when the store cannot be read or holds nothing.
  Future<void> reload() async {
    final repository = _repository;
    if (repository == null) return;
    // Our own pending write first: reading across it would bring back the
    // page the user has just left.
    await _queue;
    final Map<String, String>? stored;
    try {
      stored = await repository.load();
    } catch (_) {
      return;
    }
    if (stored == null || mapEquals(stored, _childByNode)) return;
    _childByNode
      ..clear()
      ..addAll(stored);
    revision.value++;
  }
}
