/// Remembers which horizontal page every list tile was left on.
///
/// A tile on [NodeScreen]'s list browses its own children sideways; the page
/// is stored by *child id*, not by index, because a priority write re-sorts
/// the children under the user's thumb and the card has to stay on the same
/// child while its position in the row changes.
///
/// Not a [ChangeNotifier], like `LastNodeViewModel`: nothing on screen is
/// driven by this value. It is a side record — the cards write to it as the
/// user swipes and read it back when they are rebuilt. There is no repository
/// behind it either: remembering a page for the lifetime of the process is
/// what the feature asks for, and a stored page could easily outlive the
/// child it points at.
class CardPageViewModel {
  /// Node id → the id of the child whose page that node's card sits on. A
  /// node missing from the map sits on page 0, its own face.
  final Map<String, String> _childByNode = {};

  /// The child [nodeId]'s card was left on, or null for page 0.
  String? childFor(String nodeId) => _childByNode[nodeId];

  /// Records that [nodeId]'s card now shows [childId]; null forgets it, which
  /// is what a swipe back to page 0 means.
  void remember(String nodeId, String? childId) {
    if (childId == null) {
      _childByNode.remove(nodeId);
    } else {
      _childByNode[nodeId] = childId;
    }
  }
}
