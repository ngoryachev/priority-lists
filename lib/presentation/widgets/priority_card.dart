import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/models/priority.dart';
import '../utils/priority_colors.dart';
import 'item_chips.dart';

/// One child page of a [PriorityCard]: the face of a node's direct child,
/// shown when the card is swiped sideways.
///
/// Deliberately action-light. A child page carries the child's own look (its
/// colour, title, chips) and the 1-4 priority row, but none of the owner-only
/// actions and no drag index — edit, delete, move and reorder belong to the
/// level that child lives on, which is one tap away.
@immutable
class PriorityCardPage {
  /// Id of the node this page shows. The enclosing card remembers its page by
  /// this id, so a re-sort moves the page index without moving the card.
  final String id;

  final String title;
  final String badgeLabel;
  final Color color;

  /// Tint for the page, painted over the owner's own card colour so the
  /// child's colour reads as the child's.
  final Color? backgroundColor;

  final int? childCount;
  final String? subtitle;
  final List<String>? chipLabels;
  final Priority? currentPriority;
  final VoidCallback? onTap;
  final ValueChanged<Priority>? onSetPriority;

  const PriorityCardPage({
    required this.id,
    required this.title,
    required this.badgeLabel,
    required this.color,
    this.backgroundColor,
    this.childCount,
    this.subtitle,
    this.chipLabels,
    this.currentPriority,
    this.onTap,
    this.onSetPriority,
  });
}

class PriorityCard extends StatefulWidget {
  final String title;
  final String badgeLabel;
  final Color color;

  /// Number of nodes directly inside this one, shown next to the priority
  /// badge. Sits in the badge row rather than the subtitle so it survives on
  /// short tiles, where the column below is clipped away.
  final int? childCount;

  final String? subtitle;

  /// When non-empty, rendered as mini chips in place of [subtitle].
  final List<String>? chipLabels;
  final Color? backgroundColor;
  final double? fixedHeight;
  final Priority? currentPriority;

  /// Position in the enclosing [ReorderableListView]. When set, the card shows
  /// a drag handle; null outside a reorderable list.
  final int? dragIndex;

  /// The node's direct children, as the pages the card can be swiped to.
  /// Empty means the card has a single page and does not swipe at all.
  final List<PriorityCardPage> childPages;

  /// Child page to open on, by [PriorityCardPage.id]; null (or an id that is
  /// not in [childPages]) starts on page 0, the node itself.
  final String? initialChildId;

  /// Fired when the user settles on another page — the child's id, or null for
  /// page 0. Never fired for a page change the card made by itself, so a
  /// child that went away cannot erase the remembered page.
  final ValueChanged<String?>? onChildPageChanged;

  /// Previous / next arrows on mouse hover instead of the swipe dots. On by
  /// default in the browser, where a mouse cannot drag the pages and a wheel
  /// only turns them with Shift held. The arrows wrap around: past the last
  /// child comes the node itself again.
  final bool pageArrows;

  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<Priority>? onSetPriority;

  /// Lifts the node one level up, next to its current parent.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveInto;

  const PriorityCard({
    super.key,
    required this.title,
    required this.badgeLabel,
    required this.color,
    this.childCount,
    this.subtitle,
    this.chipLabels,
    this.backgroundColor,
    this.fixedHeight,
    this.currentPriority,
    this.dragIndex,
    this.childPages = const [],
    this.initialChildId,
    this.onChildPageChanged,
    this.pageArrows = kIsWeb,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onSetPriority,
    this.onMoveUp,
    this.onMoveInto,
  });

  /// Width kept clear on the right of every face for the swipe dots.
  static const double _dotsGutter = 24;

  /// Strip on the card's left edge where the horizontal page drag is given up,
  /// so the system back gesture (iOS' edge swipe, Android's predictive back)
  /// still reaches the route instead of only turning a page.
  static const double _backGestureGutter = 24;

  /// Touch target of the bottom drag grip. The grip is the only way to start a
  /// reorder, so it stays finger-sized; it overlaps the bottom of the content
  /// transparently rather than reserving all 44dp, which short tiles cannot
  /// spare.
  static const double _gripTouchSize = 44;

  @override
  State<PriorityCard> createState() => _PriorityCardState();
}

class _PriorityCardState extends State<PriorityCard> {
  /// The child page the card wants to be on; null means page 0. Seeded from
  /// [PriorityCard.initialChildId], and the only thing the card steers by
  /// afterwards.
  ///
  /// Kept even while it cannot be shown — a child filtered out, or every page
  /// dropped because a "move into" is running — so the page comes back when
  /// the child does. [_shownChildId] is the one actually on screen.
  String? _childId;

  PageController? _controller;

  /// Set around the card's own [PageController.jumpToPage] so the resulting
  /// page change is not reported as the user's choice.
  bool _programmatic = false;

  /// A mouse is over the card, which is when [PriorityCard.pageArrows] show.
  bool _hovering = false;

  @override
  void initState() {
    super.initState();
    _childId = widget.initialChildId;
    _createControllerIfNeeded();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// A card only swipes when it has children *and* a tile height to give
  /// them: a [PageView] needs a bounded cross-axis size, and a card built
  /// without [PriorityCard.fixedHeight] sizes itself to its content instead.
  /// Every tile in the list is given a height, so this only ever rules out
  /// the card's content-sized use.
  bool get _swipeable =>
      widget.childPages.isNotEmpty && widget.fixedHeight != null;

  /// The page that can actually be shown right now: [_childId] when that child
  /// is still among the pages, page 0 otherwise.
  ///
  /// Deliberately not falling back to [PriorityCard.initialChildId]: that one
  /// is only read when the state is created, and a swipe does not rebuild the
  /// level — so a page the user has just left would still be sitting in it and
  /// would drag the card back.
  String? get _shownChildId => _has(_childId) ? _childId : null;

  bool _has(String? id) =>
      id != null && widget.childPages.any((page) => page.id == id);

  int _indexOf(String? childId) {
    if (childId == null) return 0;
    final index = widget.childPages.indexWhere((page) => page.id == childId);
    return index < 0 ? 0 : index + 1;
  }

  void _createControllerIfNeeded() {
    if (!_swipeable || _controller != null) return;
    // The initial page is baked into the controller rather than jumped to, so
    // a card that mounts on a remembered child never flashes page 0 — which
    // includes the copy `ReorderableListView` builds in its drag overlay.
    _controller = PageController(initialPage: _indexOf(_shownChildId));
  }

  @override
  void didUpdateWidget(PriorityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new page from outside — another device's, after a reload. A swipe of
    // this card's own lands here too once the level rebuilds, already equal
    // to [_childId].
    if (widget.initialChildId != oldWidget.initialChildId) {
      _childId = widget.initialChildId;
    }
    if (!_swipeable) {
      final gone = _controller;
      _controller = null;
      if (gone != null) {
        // Disposed after the frame: the PageView is still attached to it until
        // this build has replaced it with the bare face.
        WidgetsBinding.instance.addPostFrameCallback((_) => gone.dispose());
      }
      return;
    }
    _createControllerIfNeeded();
    _syncController();
  }

  /// Puts the view on [_shownChildId] without animating: the children re-sort
  /// themselves after a priority write, and a visible slide there would read
  /// as the card changing child.
  void _syncController() {
    final target = _indexOf(_shownChildId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _controller;
      if (controller == null || !controller.hasClients) return;
      if (controller.page?.round() == target) return;
      // The user's thumb is newer than whatever caused this rebuild; let the
      // swipe settle and report itself instead of yanking it.
      if (controller.position.isScrollingNotifier.value) return;
      _programmatic = true;
      controller.jumpToPage(target);
      _programmatic = false;
    });
  }

  /// Turns the page by [delta] from an arrow, wrapping around at both ends.
  /// Reported like a swipe, since it is the user's choice.
  void _step(int delta) {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    final count = widget.childPages.length + 1;
    final current = controller.page?.round() ?? _indexOf(_shownChildId);
    final raw = current + delta;
    final target = raw % count;
    if (raw != target) {
      // Wrapping: a slide across every page in between would read as a
      // scroll through them.
      controller.jumpToPage(target);
    } else {
      controller.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  void _onPageChanged(int index) {
    if (_programmatic) return;
    final id = index == 0 ? null : widget.childPages[index - 1].id;
    if (id == _childId) return;
    setState(() => _childId = id);
    widget.onChildPageChanged?.call(id);
  }

  /// Height of the overlaid 1-4 priority row, reserved at the bottom of the
  /// column so chips never slide underneath it.
  static const double _levelRowHeight = 32;

  /// Below this height the card only has room for the badge row and the
  /// title, so chips and the subtitle are dropped. The threshold sits just
  /// under a medium tile on a phone (20% of an 800dp screen) so medium lists
  /// show their items too.
  bool get _isCompact =>
      widget.fixedHeight != null && widget.fixedHeight! < 155;

  /// Medium tiles clear [_isCompact] by only a few pixels, so they trade some
  /// padding for the row of chips that would otherwise be clipped.
  bool get _isShort => widget.fixedHeight != null && widget.fixedHeight! < 190;

  @override
  Widget build(BuildContext context) {
    final shownChildId = _shownChildId;
    final shownIndex = _indexOf(shownChildId);
    final hasGrip = widget.dragIndex != null;

    final controller = _controller;
    final swiping = _swipeable && controller != null;
    final showArrows = swiping && widget.pageArrows && _hovering;
    // Positioned.fill while swiping (the pages take the whole tile), a plain
    // child otherwise — a Stack with nothing but positioned children takes
    // all the room it is offered, and a card without a fixed height has to
    // keep sizing itself to its content.
    final Widget pages = swiping
        ? Positioned.fill(
            child: PageView.builder(
              controller: controller,
              onPageChanged: _onPageChanged,
              // No wrap-around: page 0 is the node, then one page per child.
              itemCount: widget.childPages.length + 1,
              itemBuilder: (context, index) => index == 0
                  ? _ownerFace()
                  : _childFace(widget.childPages[index - 1]),
            ),
          )
        : _ownerFace();

    final shownPage = shownIndex == 0
        ? null
        : widget.childPages[shownIndex - 1];
    // Not `shownPage?.onTap ?? widget.onTap`: a child page with no tap of its
    // own must not borrow the owner's.
    final activeTap = shownPage == null ? widget.onTap : shownPage.onTap;
    // The band the grip is centred in has to clear the 1-4 row of the face
    // actually on screen: a child page carries its own row even where the
    // owner has none, and the grip is hit-test-first.
    final shownHasLevelRow = shownPage == null
        ? widget.onSetPriority != null
        : shownPage.onSetPriority != null;

    Widget card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: widget.backgroundColor,
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          pages,
          if (swiping)
            // The page drag is dropped in this strip (opaque hit testing keeps
            // the PageView out of the gesture arena here) so the platform's
            // back swipe still works. The enclosing list's scroll and the
            // route's back gesture are *ancestors* of this card, so they stay
            // in the arena — only the page turn is given up.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: PriorityCard._backGestureGutter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: activeTap,
              ),
            ),
          if (showArrows) ...[
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: _PageArrow(
                  icon: Icons.chevron_left,
                  label: 'Previous page',
                  color: widget.color,
                  onTap: () => _step(-1),
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: _PageArrow(
                  icon: Icons.chevron_right,
                  label: 'Next page',
                  color: widget.color,
                  onTap: () => _step(1),
                ),
              ),
            ),
          ],
          if (swiping && !showArrows)
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              // IgnorePointer: the hint must not cost the card a strip of
              // swipeable width.
              child: IgnorePointer(
                child: Center(
                  child: _SwipeDots(
                    color: widget.color,
                    // Children only: page 0 is the node itself and shows no
                    // counter, child pages count 1/N … N/N.
                    label: shownIndex == 0
                        ? null
                        : '$shownIndex/${widget.childPages.length}',
                  ),
                ),
              ),
            ),
          if (hasGrip)
            Positioned(
              left: 0,
              // Clear of the 1-4 row: at 360dp the row is pinned bottom-right
              // and exact centring would cost either the grip's touch target
              // or the buttons' hittability.
              right: shownHasLevelRow ? _levelRowReserve : 0,
              bottom: 0,
              height: PriorityCard._gripTouchSize,
              child: Center(child: _dragGrip()),
            ),
        ],
      ),
    );

    if (swiping && widget.pageArrows) {
      card = MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: card,
      );
    }

    if (widget.fixedHeight != null) {
      return SizedBox(height: widget.fixedHeight, child: card);
    }
    return card;
  }

  /// Width the bottom-right 1-4 row takes, as seen from the card: the four
  /// 32dp buttons with their gaps, plus the face's own padding.
  static const double _levelRowReserve = 160;

  /// Band kept clear for the grip glyph on a card that has no 1-4 row. With
  /// the row there its 32dp already covers the glyph, so the grip costs a
  /// short tile nothing.
  static const double _gripBandHeight = 20;

  Widget _dragGrip() {
    return ReorderableDragStartListener(
      index: widget.dragIndex!,
      // Tooltip doubles as the handle's accessible name; a bare Icon would
      // reach a screen reader as nothing.
      child: Tooltip(
        message: 'Drag to reorder',
        child: SizedBox(
          width: PriorityCard._gripTouchSize,
          height: PriorityCard._gripTouchSize,
          // Bottom-aligned: the glyph sits on the card's edge while the rest
          // of the target reaches up over the content.
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Icon(
                Icons.drag_handle,
                size: 20,
                color: widget.color.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ownerFace() {
    return _CardFace(
      title: widget.title,
      badgeLabel: widget.badgeLabel,
      color: widget.color,
      childCount: widget.childCount,
      subtitle: widget.subtitle,
      chipLabels: widget.chipLabels,
      currentPriority: widget.currentPriority,
      isCompact: _isCompact,
      isShort: _isShort,
      bottomReserve: _bottomReserve(hasLevelRow: widget.onSetPriority != null),
      rightReserve: _swipeable ? PriorityCard._dotsGutter : 0,
      onTap: widget.onTap,
      onEdit: widget.onEdit,
      onDelete: widget.onDelete,
      onMoveUp: widget.onMoveUp,
      onMoveInto: widget.onMoveInto,
      onSetPriority: widget.onSetPriority,
    );
  }

  Widget _childFace(PriorityCardPage page) {
    return _CardFace(
      title: page.title,
      badgeLabel: page.badgeLabel,
      color: page.color,
      background: page.backgroundColor,
      childCount: page.childCount,
      subtitle: page.subtitle,
      chipLabels: page.chipLabels,
      currentPriority: page.currentPriority,
      isCompact: _isCompact,
      isShort: _isShort,
      bottomReserve: _bottomReserve(hasLevelRow: page.onSetPriority != null),
      rightReserve: PriorityCard._dotsGutter,
      // Whose card this is: the page belongs to the owner's tile, not to the
      // child's own level.
      ownerLabel: '${widget.title} ›',
      onTap: page.onTap,
      onSetPriority: page.onSetPriority,
    );
  }

  /// Space kept below the column. The grip's 44dp touch target deliberately
  /// reaches past this band — reserving all of it would cost the shortest
  /// tiles their title, and the part that overlaps is transparent.
  double _bottomReserve({required bool hasLevelRow}) {
    return math.max(
      hasLevelRow ? _levelRowHeight : 0,
      widget.dragIndex != null ? _gripBandHeight : 0,
    );
  }
}

/// One page of a [PriorityCard]: everything inside the card's rounded shape.
class _CardFace extends StatelessWidget {
  final String title;
  final String badgeLabel;
  final Color color;

  /// Tint painted for this page. Null leaves the enclosing [Card]'s own colour
  /// showing, which is what page 0 wants.
  final Color? background;

  final int? childCount;
  final String? subtitle;
  final List<String>? chipLabels;
  final Priority? currentPriority;

  /// Small line above the badge row naming the tile this page hangs off —
  /// only set on child pages.
  final String? ownerLabel;

  final bool isCompact;
  final bool isShort;
  final double bottomReserve;
  final double rightReserve;

  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveInto;
  final ValueChanged<Priority>? onSetPriority;

  const _CardFace({
    required this.title,
    required this.badgeLabel,
    required this.color,
    this.background,
    this.childCount,
    this.subtitle,
    this.chipLabels,
    this.currentPriority,
    this.ownerLabel,
    required this.isCompact,
    required this.isShort,
    required this.bottomReserve,
    required this.rightReserve,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onMoveUp,
    this.onMoveInto,
    this.onSetPriority,
  });

  /// How far the owner label's own line may be scaled up before a tile with
  /// little vertical slack stops having room for it. The floor of what the
  /// two tight tiles measured: the 132dp floor tile (every tile on a small
  /// phone) overflows at 1.8x — 4dp, 10dp at 2x — and the 160dp tile at 2.5x.
  static const double _maxTightLabelScale = 1.7;

  /// A short tile is down to the badge row, one line of title and the 1-4
  /// row; the owner label is a line on top of that, and past
  /// [_maxTightLabelScale] it no longer fits. Dropping it there keeps the
  /// title, which is the line worth reading — the dots and the counter still
  /// say the card is showing a child rather than itself. A tall tile has the
  /// room at any scale and always keeps it.
  bool _showsOwnerLabel(BuildContext context, TextStyle? style) {
    if (ownerLabel == null) return false;
    if (!isCompact && !isShort) return true;
    final fontSize = style?.fontSize ?? 11;
    return MediaQuery.textScalerOf(context).scale(fontSize) <=
        fontSize * _maxTightLabelScale;
  }

  @override
  Widget build(BuildContext context) {
    final padding = isCompact
        ? 10.0
        : isShort
        ? 12.0
        : 16.0;
    final ownerLabelStyle = Theme.of(context).textTheme.labelSmall;

    final face = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 5)),
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          // The priority-level row is overlaid via Stack so it doesn't eat
          // vertical space inside the Column — important for compact cards
          // (low/medium) where the Column is already tight.
          child: Stack(
            children: [
              Padding(
                // Keep the column clear of the overlaid 1-4 row. This holds
                // on compact tiles too: skipping it there let the buttons sit
                // on top of the title, so tapping a short card's name set a
                // priority instead of opening the node.
                padding: EdgeInsets.only(bottom: bottomReserve),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_showsOwnerLabel(context, ownerLabelStyle))
                      Text(
                        ownerLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ownerLabelStyle?.copyWith(
                          color: color.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (childCount != null && childCount! > 0)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.subdirectory_arrow_right,
                                    size: 12,
                                    color: color,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${childCount!}',
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Expanded (not Spacer + Flexible, which would split
                        // the free space) hands the actions everything left of
                        // the badge; reverse keeps them right-aligned and lets
                        // them scroll instead of overflowing when a large text
                        // scale leaves the row too narrow.
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (onMoveUp != null)
                                  _CardAction(
                                    icon: Icons.arrow_upward,
                                    onPressed: onMoveUp,
                                    tooltip: 'Move up one level',
                                  ),
                                if (onMoveInto != null)
                                  _CardAction(
                                    icon: Icons.move_to_inbox,
                                    onPressed: onMoveInto,
                                    tooltip: 'Move into another node',
                                  ),
                                if (onEdit != null)
                                  _CardAction(
                                    icon: Icons.edit_outlined,
                                    onPressed: onEdit,
                                    tooltip: 'Edit',
                                  ),
                                if (onDelete != null)
                                  _CardAction(
                                    icon: Icons.delete_outline,
                                    onPressed: onDelete,
                                    tooltip: 'Delete',
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isShort ? 4 : 8),
                    Flexible(
                      // Only the middle of the face is kept clear of the dots:
                      // they sit vertically centred on the right edge, well
                      // away from the action row above and the 1-4 row below,
                      // and taking the gutter off the whole face cost the
                      // leftmost action its room on a 360dp phone.
                      child: Padding(
                        padding: EdgeInsets.only(right: rightReserve),
                        child: Text(
                          title,
                          // A compact tile has room for the badge row, one
                          // line of title and the 1-4 row — the large style
                          // simply gets clipped there.
                          style:
                              (isCompact
                                      ? Theme.of(context).textTheme.titleMedium
                                      : Theme.of(context).textTheme.titleLarge)
                                  ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: isCompact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (!isCompact &&
                        chipLabels != null &&
                        chipLabels!.isNotEmpty) ...[
                      SizedBox(height: isShort ? 3 : 6),
                      Flexible(
                        child: Padding(
                          padding: EdgeInsets.only(right: rightReserve),
                          child: ItemChips(labels: chipLabels!, color: color),
                        ),
                      ),
                    ] else if (!isCompact &&
                        subtitle != null &&
                        subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Flexible(
                        child: Padding(
                          padding: EdgeInsets.only(right: rightReserve),
                          child: Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey.shade600),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onSetPriority != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _PriorityLevelRow(
                    current: currentPriority,
                    onSelect: onSetPriority!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (background == null) return face;
    // A child page sits on top of the owner's own tinted card, so its
    // translucent tint is blended onto the theme's card colour first —
    // otherwise the owner's colour would show through the child's.
    return Material(
      color: Color.alphaBlend(background!, Theme.of(context).cardColor),
      child: face,
    );
  }
}

/// Fixed three-dot grip with the page counter, hinting that the card browses
/// its children sideways. Fixed by design: one dot per child does not fit a
/// tile once a node has a dozen of them, so the count is spelled out instead.
class _SwipeDots extends StatelessWidget {
  final Color color;

  /// "2/5" on a child page; null on page 0, which is the node itself.
  final String? label;

  const _SwipeDots({required this.color, this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label == null
          ? 'Swipe to browse children'
          : 'Child $label, swipe to browse children',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.more_vert, size: 18, color: color.withValues(alpha: 0.7)),
          if (label != null)
            Text(
              label!,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }
}

/// One of the hover arrows that turn a card's pages with a mouse.
class _PageArrow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PageArrow({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        shape: const CircleBorder(),
        elevation: 1,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}

/// Compact icon button used for the card's action row.
class _CardAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  const _CardAction({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Row of four square buttons "1" / "2" / "3" / "4" that directly assign a
/// [Priority] without going through up/down increments.
class _PriorityLevelRow extends StatelessWidget {
  final Priority? current;
  final ValueChanged<Priority> onSelect;

  const _PriorityLevelRow({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in Priority.values)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _PriorityLevelButton(
              priority: p,
              isActive: current == p,
              onTap: () => onSelect(p),
            ),
          ),
      ],
    );
  }
}

class _PriorityLevelButton extends StatelessWidget {
  final Priority priority;
  final bool isActive;
  final VoidCallback onTap;

  const _PriorityLevelButton({
    required this.priority,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(priority);
    return Material(
      color: isActive ? color : color.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: color, width: isActive ? 0 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: Text(
              '${priority.value}',
              style: TextStyle(
                color: isActive ? Colors.white : color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
