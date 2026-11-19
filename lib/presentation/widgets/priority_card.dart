import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/models/node_mark.dart';
import '../../domain/models/priority.dart';
import '../utils/priority_colors.dart';

/// One child page of a [PriorityCard]: the face of a node's direct child,
/// shown when the card is swiped sideways.
///
/// Deliberately action-light. A child page carries the child's own look (its
/// colour, title, child count) and the 1-4 priority row, but none of the
/// owner-only actions and no drag index — edit, delete, move and reorder
/// belong to the level that child lives on, which is one tap away.
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
  /// badge — the whole of what the tile says about its children, now that the
  /// column below is one line of title and nothing else.
  final int? childCount;

  final Color? backgroundColor;
  final double? fixedHeight;
  final Priority? currentPriority;

  /// The node's 🔥 / 🧊 mark, or null when it has none. Only read when
  /// [onSetMark] is set, which is what puts the mark entries in the menu.
  final NodeMark? currentMark;

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

  /// Sets the node's mark, or clears it with null.
  ///
  /// Offered from the badge row's overflow menu rather than as buttons of its
  /// own. The row has four cells and no width to spare — a fifth and sixth
  /// would push the actions that were there off its scrollable end, and the
  /// bottom of the card is spoken for by the drag grip, the 1-4 row and the
  /// strip kept clear for the platform back swipe. The menu holds what is
  /// rarely tapped twice in a row: the marks, and Delete.
  final ValueChanged<NodeMark?>? onSetMark;

  /// Lifts the node one level up, next to its current parent.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveInto;

  const PriorityCard({
    super.key,
    required this.title,
    required this.badgeLabel,
    required this.color,
    this.childCount,
    this.backgroundColor,
    this.fixedHeight,
    this.currentPriority,
    this.currentMark,
    this.dragIndex,
    this.childPages = const [],
    this.initialChildId,
    this.onChildPageChanged,
    this.pageArrows = kIsWeb,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onSetPriority,
    this.onSetMark,
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
  /// transparently rather than reserving all 44dp, which a tile sized to its
  /// content cannot spare.
  static const double _gripTouchSize = 44;

  /// The card's own margin inside the tile height it is given. Part of
  /// [compactHeight] because that height is the tile's, not the face's — left
  /// out, it came straight off the title's line.
  static const EdgeInsets _cardMargin = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );

  /// Padding around a face's content. The tightest of the three widths the
  /// card used to choose between: with the badge row and the 1-4 row both
  /// sized by their touch targets, this is the only band left to spend on air.
  static const double _facePadding = 8;

  /// Gap between the badge row and the title.
  static const double _titleGap = 4;

  /// The badge chips: their type, the line it is pinned to and their own
  /// insets. The line height is set explicitly on the [Text] rather than
  /// inherited — left to the ambient [DefaultTextStyle] it picks up
  /// `bodyMedium`'s 1.43, which is taller than this measures and so comes out
  /// of the title's line.
  static const double _badgeFontSize = 12;
  static const double _badgeLineHeight = 1.2;
  static const double _badgeVerticalPadding = 4;

  /// Height of the overlaid 1-4 priority row, reserved at the bottom of the
  /// column so the title never slides underneath it.
  static const double _levelRowHeight = 32;

  /// Height a [_CardAction] claims in the badge row: `IconButton`'s 48dp
  /// minimum less the 8dp [VisualDensity.compact] takes off it. Their touch
  /// target is what sets the row's height until the text is scaled past it.
  static const double _actionRowHeight = 40;

  /// The height every list tile gets: exactly what a minimal face needs and
  /// nothing more — the card's margin, badge row, one whole line of title,
  /// the 1-4 row and the paddings between them. Priority plays no part;
  /// colour and the badge carry it.
  ///
  /// Scaled with the text scaler rather than fixed, so a card grows with the
  /// user's font size instead of squeezing its title. Every line is measured
  /// from the very style [_CardFace] renders it in — a band this is short of
  /// does not overflow, because the title sits in a [Flexible]: it is handed
  /// less than its line and paints the remainder under the 1-4 row.
  static double compactHeight(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final textTheme = Theme.of(context).textTheme;
    // Read off the theme rather than restated, so a type change cannot leave
    // the tile a few dp short of the line it is supposed to pay for.
    double line(TextStyle? style) =>
        scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.5);

    final badgeRow =
        scaler.scale(_badgeFontSize) * _badgeLineHeight +
        2 * _badgeVerticalPadding;
    final titleLine = line(textTheme.titleMedium);
    final ownerLabelLine = line(textTheme.labelSmall);
    // The owner face pays for the action buttons, a child page for the owner
    // label instead — whichever of the two needs more is what the tile gets,
    // since one card shows both.
    final ownerFace =
        math.max(badgeRow, _actionRowHeight) + _titleGap + titleLine;
    final childFace = ownerLabelLine + badgeRow + _titleGap + titleLine;
    return _cardMargin.vertical +
        2 * _facePadding +
        _levelRowHeight +
        math.max(ownerFace, childFace);
  }

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
      margin: PriorityCard._cardMargin,
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
  /// the row there its 32dp already covers the glyph, so the grip costs the
  /// tile nothing.
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
      currentPriority: widget.currentPriority,
      currentMark: widget.currentMark,
      bottomReserve: _bottomReserve(hasLevelRow: widget.onSetPriority != null),
      rightReserve: _swipeable ? PriorityCard._dotsGutter : 0,
      onTap: widget.onTap,
      onEdit: widget.onEdit,
      onDelete: widget.onDelete,
      onMoveUp: widget.onMoveUp,
      onMoveInto: widget.onMoveInto,
      onSetPriority: widget.onSetPriority,
      // Marks belong to the level the node lives on, like edit and delete; a
      // child page carries none.
      onSetMark: widget.onSetMark,
    );
  }

  Widget _childFace(PriorityCardPage page) {
    return _CardFace(
      title: page.title,
      badgeLabel: page.badgeLabel,
      color: page.color,
      background: page.backgroundColor,
      childCount: page.childCount,
      currentPriority: page.currentPriority,
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
  /// reaches past this band — reserving all of it would cost the tile its
  /// title, and the part that overlaps is transparent.
  double _bottomReserve({required bool hasLevelRow}) {
    return math.max(
      hasLevelRow ? PriorityCard._levelRowHeight : 0,
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
  final Priority? currentPriority;

  /// The node's mark, and the callback that sets it. Null [onSetMark] leaves
  /// the mark entries out of the overflow menu, which is every face but a
  /// level's own card.
  final NodeMark? currentMark;
  final ValueChanged<NodeMark?>? onSetMark;

  /// Small line above the badge row naming the tile this page hangs off —
  /// only set on child pages.
  final String? ownerLabel;

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
    this.currentPriority,
    this.currentMark,
    this.onSetMark,
    this.ownerLabel,
    required this.bottomReserve,
    required this.rightReserve,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onMoveUp,
    this.onMoveInto,
    this.onSetPriority,
  });

  @override
  Widget build(BuildContext context) {
    final ownerLabelStyle = Theme.of(context).textTheme.labelSmall;

    final face = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(PriorityCard._facePadding),
          // The priority-level row is overlaid via Stack so it doesn't eat
          // vertical space inside the Column — the card is sized to its
          // content, so the Column has nothing to spare.
          child: Stack(
            children: [
              Padding(
                // Keep the column clear of the overlaid 1-4 row: skipping it
                // let the buttons sit on top of the title, so tapping a
                // card's name set a priority instead of opening the node.
                padding: EdgeInsets.only(bottom: bottomReserve),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Shown at every text scale: the tile's own height is
                    // measured with this line in it.
                    if (ownerLabel != null)
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
                            vertical: PriorityCard._badgeVerticalPadding,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              color: color,
                              fontSize: PriorityCard._badgeFontSize,
                              // Pinned, not inherited: see
                              // [PriorityCard._badgeLineHeight].
                              height: PriorityCard._badgeLineHeight,
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
                                vertical: PriorityCard._badgeVerticalPadding,
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
                                      fontSize: PriorityCard._badgeFontSize,
                                      height: PriorityCard._badgeLineHeight,
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
                                // Delete and the marks share one cell. The
                                // row keeps the four it has always had, so
                                // nothing that was one tap away stops being
                                // one, and the row's width is unchanged.
                                if (onDelete != null || onSetMark != null)
                                  _CardOverflowAction(
                                    currentMark: currentMark,
                                    onSetMark: onSetMark,
                                    onDelete: onDelete,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: PriorityCard._titleGap),
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
                          // One line, always: a tile is as short as the badge
                          // row, this line and the 1-4 row allow, and the
                          // full name is one tap away.
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
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

/// What the node's 🔥 / 🧊 mark and Delete share: the last cell of the badge
/// row, as a menu.
///
/// Sized from the same [IconButton] settings as [_CardAction] so the row has
/// exactly the four cells it had before marks existed — a fifth and a sixth
/// would be clipped off the row's scrollable end, taking the actions that were
/// already there with them, and a scroller that can actually scroll claims the
/// horizontal drags the card needs for its child pages.
///
/// Both marks are always offered, so swapping 🔥 for 🧊 is one tap; "Remove
/// mark" only appears when there is one to remove.
class _CardOverflowAction extends StatelessWidget {
  final NodeMark? currentMark;
  final ValueChanged<NodeMark?>? onSetMark;
  final VoidCallback? onDelete;

  const _CardOverflowAction({
    required this.currentMark,
    required this.onSetMark,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_CardMenuItem>(
      // Deliberately not `more_vert`: that is the swipe-dots hint's glyph on
      // the other edge of this same card.
      icon: const Icon(Icons.more_horiz, size: 20),
      tooltip: 'More actions',
      // The same cell a [_CardAction] occupies — same icon size, same padding,
      // same compact density — so this row has exactly the four it had when
      // Delete was a button of its own, and costs the card no extra width.
      iconSize: 20,
      style: IconButton.styleFrom(visualDensity: VisualDensity.compact),
      onSelected: (item) => switch (item) {
        _CardMenuItem.flame => onSetMark?.call(NodeMark.flame),
        _CardMenuItem.ice => onSetMark?.call(NodeMark.ice),
        _CardMenuItem.clearMark => onSetMark?.call(null),
        _CardMenuItem.delete => onDelete?.call(),
      },
      itemBuilder: (context) => [
        if (onSetMark != null) ...[
          for (final mark in NodeMark.values)
            PopupMenuItem<_CardMenuItem>(
              value: mark == NodeMark.flame
                  ? _CardMenuItem.flame
                  : _CardMenuItem.ice,
              // The one that is already set reads as set rather than being
              // hidden, so the menu always has both and never moves.
              enabled: currentMark != mark,
              child: Text('${mark.emoji} ${mark.label}'),
            ),
          if (currentMark != null)
            const PopupMenuItem<_CardMenuItem>(
              value: _CardMenuItem.clearMark,
              child: Text('Remove mark'),
            ),
        ],
        if (onDelete != null) ...[
          if (onSetMark != null) const PopupMenuDivider(),
          const PopupMenuItem<_CardMenuItem>(
            value: _CardMenuItem.delete,
            child: Text('Delete'),
          ),
        ],
      ],
    );
  }
}

enum _CardMenuItem { flame, ice, clearMark, delete }

/// A marked node as it appears pinned above its level's card list: one compact
/// line of emoji and title, and nothing else.
///
/// Deliberately not a [PriorityCard]: no badge, no 1-4 row, no chips, no
/// description, no actions and no child pages. A pinned row says only "this
/// one is on fire / on ice" and takes a single line to say it. The level the
/// node lives on is one tap away, where all of that is.
class PinnedMarkRow extends StatelessWidget {
  final NodeMark mark;
  final String title;

  /// Opens the node, exactly like a card tap — or, while a node is being
  /// moved, puts it inside this one.
  final VoidCallback? onTap;

  /// Takes the mark off, after which the node reappears in the card list at
  /// its unchanged priority and position.
  final VoidCallback? onClearMark;

  const PinnedMarkRow({
    super.key,
    required this.mark,
    required this.title,
    this.onTap,
    this.onClearMark,
  });

  /// What one row is worth at the default text scale. A floor rather than a
  /// fixed height: the title's line grows with the text scaler, and a row
  /// pinned to 36dp would paint it outside its own box.
  static const double minHeight = 36;

  @override
  Widget build(BuildContext context) {
    final color = markColor(mark);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Row(
        children: [
          Tooltip(
            message: 'Remove the mark',
            child: InkWell(
              onTap: onClearMark,
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Text(mark.emoji, style: const TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
