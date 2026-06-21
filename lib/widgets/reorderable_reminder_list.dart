import 'dart:math' show max;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HapticFeedback;

import '../models/reminder_item.dart';
import 'add_reminder_row.dart';
import 'drag_tilt.dart';
import 'draggable_reminder_tile.dart';
import 'emerging_reminder_tile.dart';
import 'paint_sweep.dart';
import 'reminder_tile.dart';
import 'reorder_math.dart';

/// A vertical list of [ReminderTile]s that can be reordered by holding a tile
/// down and dragging it to a new position.
///
/// The interaction, in order:
///  * **hold** — a long press lifts the tile (it scales up and grows a drop
///    shadow), lifting it "off the page";
///  * **drag** — the lifted tile follows the finger and tilts in 3D toward it,
///    leaning further the faster it is dragged and easing back to flat when the
///    finger stops;
///  * **shuffle** — the tiles it is dragged between slide smoothly out of the
///    way to open a landing gap;
///  * **drop** — on release the tile animates from the finger down into its
///    chosen slot while the lift eases away.
///
/// Tiles are laid out as absolutely-positioned children of a [Stack] (all the
/// rows are the same height), so reordering is a matter of animating each
/// tile's top to a new slot. The parent still owns the per-tile state
/// (enabled/expanded), the [GlobalKey]s used to measure tiles for the modal,
/// and the order itself — this widget just reports moves via [onReorder].
class ReorderableReminderList extends StatefulWidget {
  const ReorderableReminderList({
    super.key,
    required this.order,
    required this.items,
    required this.tileKeys,
    required this.enabledIds,
    required this.expandedId,
    required this.hiddenId,
    required this.dragEnabled,
    required this.horizontalPadding,
    required this.topPadding,
    required this.bottomPadding,
    required this.itemGap,
    required this.onToggle,
    required this.onExpandTap,
    required this.onExpandComplete,
    required this.onReorder,
    required this.editing,
    required this.markedIds,
    required this.dissolvingIds,
    required this.onToggleMarked,
    required this.onMarkedChanged,
    required this.onEnabledChanged,
    required this.onAdd,
    this.showAddRow = true,
    this.addingId,
    this.addAnimation,
    this.compact = false,
    this.timerRemaining = const <int, ValueListenable<Duration>>{},
  });

  /// Display order as ids (indices into [items]). Position 0 is the top tile.
  final List<int> order;

  /// All reminders, indexed by id. Never reordered itself.
  final List<ReminderItem> items;

  /// One [GlobalKey] per id, owned by the parent so it can measure a tile's
  /// slot for the expand-into-modal hand-off.
  final List<GlobalKey> tileKeys;

  /// Ids whose notification is currently switched on.
  final Set<int> enabledIds;

  /// The id of the tile currently brought "closer", or null.
  final int? expandedId;

  /// The id of the tile currently promoted into the floating modal (hidden in
  /// the list so the overlay is the only copy), or null.
  final int? hiddenId;

  /// Whether a long press may start a drag. False while a modal is open or a
  /// tile is expanding, so the two interactions never fight.
  final bool dragEnabled;

  final double horizontalPadding;
  final double topPadding;
  final double bottomPadding;
  final double itemGap;

  /// Bell tapped on the tile with this id.
  final void Function(int id) onToggle;

  /// Tile body (not the bell) tapped.
  final void Function(int id) onExpandTap;

  /// The tile's "closer" expand animation finished — hand off to the modal.
  final void Function(int id) onExpandComplete;

  /// A tile moved from display position [from] to [to]. The parent updates the
  /// order; this widget animates the landing.
  final void Function(int from, int to) onReorder;

  /// Edit mode: the bells become trash-can delete toggles and reordering is
  /// suspended in favour of the paint-to-delete gesture.
  final bool editing;

  /// Ids currently marked for deletion (delete buttons shown red).
  final Set<int> markedIds;

  /// Ids mid-disintegration: hidden (the dust overlay is the only copy) but
  /// kept in [order] so their slot stays reserved until the effect finishes.
  final Set<int> dissolvingIds;

  /// A delete button was tapped — toggle that one id's marked state.
  final void Function(int id) onToggleMarked;

  /// The paint gesture computed a new marked set (swept range applied over the
  /// pre-gesture snapshot). The parent adopts it wholesale.
  final void Function(Set<int> marked) onMarkedChanged;

  /// As [onMarkedChanged], but for the enabled set — the bell's press-and-drag
  /// paints notifications on/off across the swept range.
  final void Function(Set<int> enabled) onEnabledChanged;

  /// The trailing dashed "add reminder" row was tapped.
  final VoidCallback onAdd;

  /// Whether to render the trailing dashed "add" row at all. Dropped only when
  /// the list is empty (the empty state owns the add affordance then); in edit
  /// mode the row stays but fades/scales out in place (see [editing]).
  final bool showAddRow;

  /// The id of the reminder currently being added, or null. Its slot renders an
  /// [EmergingReminderTile] morphing the "+" button into the new tile instead of
  /// an ordinary [ReminderTile].
  final int? addingId;

  /// Drives the add morph (0 -> 1). Non-null exactly while [addingId] is set.
  final Animation<double>? addAnimation;

  /// Whether tiles render in their compact layout (shorter rows). Changing it
  /// re-measures the shared row height.
  final bool compact;

  /// Live countdown per timer reminder id, owned by the screen. A tile's chip
  /// subscribes to its own id's listenable (so a tick repaints just that chip);
  /// absent ids fall back to the full length. Lifting it here keeps every chip
  /// in sync — and lets the value survive the tile -> modal hand-off without
  /// resetting.
  final Map<int, ValueListenable<Duration>> timerRemaining;

  @override
  State<ReorderableReminderList> createState() =>
      _ReorderableReminderListState();
}

class _ReorderableReminderListState extends State<ReorderableReminderList>
    with TickerProviderStateMixin {
  /// Fallback row height used until a real tile has been measured. The rows are
  /// a fixed-height single line, so this is normally already exact. The compact
  /// layout drops the subtitle and shrinks the bell, so it sits shorter.
  static const double _estimatedTileHeight = 78;
  static const double _compactTileHeight = 60;

  /// How far the dragged tile may stray horizontally / past the ends. Small,
  /// so the card stays in its column and clearly reads as a list reorder.
  static const double _horizontalSlack = 24;
  static const double _edgeSlack = 18;

  /// Shared timing for the neighbour shuffle and the drop-into-place settle.
  static const Duration _moveDuration = Duration(milliseconds: 240);
  static const Duration _liftDuration = Duration(milliseconds: 150);
  static const Curve _moveCurve = Curves.easeOutCubic;

  /// Measured (or estimated) row height. All rows share it.
  double _tileHeight = _estimatedTileHeight;
  bool _measured = false;

  /// The tile width the list was last laid out at. A measurement is only
  /// trusted once a tile has actually been laid out at this width, so the very
  /// first frame — which can run with a transient `maxWidth == 0` constraint,
  /// collapsing each tile's text into a tall sliver — never latches a bogus
  /// height.
  double _lastTileWidth = 0;

  /// Lifts the dragged tile up (forward) and eases it back down (reverse).
  late final AnimationController _lift;

  /// Drives the continuous tilt smoothing and finger-follow repaint while a
  /// drag is in progress.
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Offset _prevTickPointer = Offset.zero;

  /// The id being dragged, or null. [_settlingId] is the tile still easing into
  /// place after release (kept lifted + painted on top until it lands).
  int? _dragId;
  int? _settlingId;

  /// Display index the drag started from, and the slot it currently targets.
  int _dragFromIndex = 0;
  int _insertionIndex = 0;
  int _lastHapticIndex = 0;

  /// Pointer position in the list's local coordinates, and where in the tile it
  /// was grabbed, so the grab point stays under the finger.
  Offset _pointer = Offset.zero;
  Offset _grab = Offset.zero;

  /// Live tilt (radians) around the X and Y axes.
  double _tiltX = 0;
  double _tiltY = 0;

  /// Paint gesture state, shared by the bell (enabled) and delete (marked)
  /// toggles. [_painting] is true between a leading button's pan start and end;
  /// [_paintAdd] is the action the sweep applies (add or remove, decided by the
  /// start tile's state); [_preGestureSet] is the target set at gesture start,
  /// so tiles the finger retreats past are restored to it; [_paintReport] sends
  /// the recomputed set to the right parent callback (enabled vs marked).
  bool _painting = false;
  int _paintStartIndex = 0;
  int _paintLastIndex = -1;
  bool _paintAdd = true;
  Set<int> _preGestureSet = <int>{};
  void Function(Set<int>)? _paintReport;

  /// Measures the Stack so global pointer positions can be made list-local.
  final GlobalKey _stackKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tileHeight = widget.compact ? _compactTileHeight : _estimatedTileHeight;
    _lift = AnimationController(
      vsync: this,
      duration: _liftDuration,
      reverseDuration: _moveDuration,
    )..addStatusListener(_onLiftStatus);
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(ReorderableReminderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The compact layout changes the row height, which is otherwise measured
    // once and latched. Drop to the matching estimate and re-measure so the
    // slot spacing follows; AnimatedPositioned eases the tiles to their new
    // tops, so the relayout reads as a smooth settle rather than a jump.
    if (widget.compact != oldWidget.compact) {
      _measured = false;
      _tileHeight = widget.compact ? _compactTileHeight : _estimatedTileHeight;
    }
  }

  @override
  void dispose() {
    if (_ticker.isActive) _ticker.stop();
    _ticker.dispose();
    _lift.dispose();
    super.dispose();
  }

  void _onLiftStatus(AnimationStatus status) {
    // Fully eased back down: the settling tile has landed, so it can drop out
    // of the "on top" painting order and stop being treated as active.
    if (status == AnimationStatus.dismissed && _settlingId != null) {
      setState(() => _settlingId = null);
    }
  }

  double get _extent => _tileHeight + widget.itemGap;

  /// The dragged tile's top, following the finger, clamped near the list.
  double _draggedTop() {
    final int n = widget.order.length;
    final double minTop = widget.topPadding - _edgeSlack;
    final double maxTop =
        widget.topPadding + max(0, n - 1) * _extent + _edgeSlack;
    return (_pointer.dy - _grab.dy).clamp(minTop, maxTop);
  }

  /// The dragged tile's left, allowing a little horizontal sway.
  double _draggedLeft() {
    final double resting = widget.horizontalPadding;
    return (_pointer.dx - _grab.dx).clamp(
      resting - _horizontalSlack,
      resting + _horizontalSlack,
    );
  }

  RenderBox? _stackBox() {
    final RenderObject? box = _stackKey.currentContext?.findRenderObject();
    return box is RenderBox && box.attached ? box : null;
  }

  void _startDrag(int displayIndex, int id, LongPressStartDetails details) {
    if (!widget.dragEnabled) return;
    final RenderBox? box = _stackBox();
    if (box == null) return;
    setState(() {
      _dragId = id;
      _settlingId = null;
      _dragFromIndex = displayIndex;
      _insertionIndex = displayIndex;
      _lastHapticIndex = displayIndex;
      _grab = details.localPosition;
      _pointer = box.globalToLocal(details.globalPosition);
      _prevTickPointer = _pointer;
      _tiltX = 0;
      _tiltY = 0;
    });
    _lastTick = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
    _lift.forward();
    HapticFeedback.mediumImpact();
  }

  void _updateDrag(LongPressMoveUpdateDetails details) {
    if (_dragId == null) return;
    final RenderBox? box = _stackBox();
    if (box == null) return;
    // Stored only; the ticker turns this into smooth follow + tilt each frame.
    _pointer = box.globalToLocal(details.globalPosition);
  }

  void _endDrag() => _finishDrag(commit: true);

  /// The drag pointer was cancelled rather than lifted — the OS interrupting,
  /// the app backgrounding, or a parent scrollable winning the gesture arena.
  /// The long-press recogniser fires `onLongPressCancel` (never
  /// `onLongPressEnd`) in that case, so without handling it the dragged tile
  /// would stay lifted on the expensive real-glass shader forever and the
  /// finger-follow ticker would spin `setState` every frame. Settle the tile
  /// back into its original slot, committing no reorder (a cancel aborts).
  void _cancelDrag() => _finishDrag(commit: false);

  /// Ends the active drag: stops the follow ticker, hands the tile to the
  /// settle animation (kept lifted + on top until it lands), and eases the lift
  /// away. [commit] reorders to the hovered slot on a clean drop; a cancel
  /// passes false so the tile returns to where it started.
  void _finishDrag({required bool commit}) {
    final int? id = _dragId;
    if (id == null) return;
    final int from = _dragFromIndex;
    final int to = _insertionIndex;
    if (_ticker.isActive) _ticker.stop();
    setState(() {
      _dragId = null;
      _settlingId = id; // Keep it lifted + on top until it lands.
      _tiltX = 0;
      _tiltY = 0;
    });
    _lift.reverse();
    if (commit && to != from) widget.onReorder(from, to);
  }

  /// Display index of the tile the finger is over, from its list-local y.
  int _indexAtY(double localY) {
    final int n = widget.order.length;
    if (n == 0) return 0;
    final int i = ((localY - widget.topPadding) / _extent).floor();
    return i.clamp(0, n - 1);
  }

  /// A leading button's pan began. In edit mode it paints the marked set, else
  /// the enabled set. The sweep's action is the opposite of the start tile's
  /// current state (press an "off" tile -> turn on; press an "on" one -> turn
  /// off), and is applied to the start tile right away.
  void _startPaint(int displayIndex, int id, Offset globalPosition) {
    if (_stackBox() == null) return;
    final Set<int> currentSet = widget.editing
        ? widget.markedIds
        : widget.enabledIds;
    _paintReport = widget.editing
        ? widget.onMarkedChanged
        : widget.onEnabledChanged;
    _painting = true;
    _paintStartIndex = displayIndex;
    _paintLastIndex = displayIndex;
    _preGestureSet = Set<int>.from(currentSet);
    _paintAdd = !currentSet.contains(id);
    HapticFeedback.selectionClick();
    _applyPaint(globalPosition);
  }

  void _updatePaint(Offset globalPosition) {
    if (_painting) _applyPaint(globalPosition);
  }

  void _endPaint() => _painting = false;

  /// Applies [_paintAdd] to every tile between the start tile and the one under
  /// the finger, restoring all others to their pre-gesture state — so retreating
  /// toward the start reverts the tiles the finger leaves behind.
  void _applyPaint(Offset globalPosition) {
    final RenderBox? box = _stackBox();
    if (box == null) return;
    final int current = _indexAtY(box.globalToLocal(globalPosition).dy);
    if (current != _paintLastIndex) {
      _paintLastIndex = current;
      HapticFeedback.selectionClick();
    }
    final Set<int> next = PaintSweep(
      startIndex: _paintStartIndex,
      add: _paintAdd,
      preGestureSet: _preGestureSet,
    ).applied(currentIndex: current, order: widget.order);
    _paintReport?.call(next);
  }

  void _onTick(Duration elapsed) {
    if (!mounted || _dragId == null) return;
    final double dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;

    final Offset velocity = (_pointer - _prevTickPointer) / dt;
    _prevTickPointer = _pointer;

    final (double targetX, double targetY) = DragTilt.target(velocity);
    _tiltX = DragTilt.smooth(_tiltX, targetX, dt);
    _tiltY = DragTilt.smooth(_tiltY, targetY, dt);

    final int next = ReorderMath.insertionIndexForTop(
      _draggedTop(),
      topPadding: widget.topPadding,
      extent: _extent,
      count: widget.order.length,
    );
    if (next != _insertionIndex) {
      _insertionIndex = next;
      if (next != _lastHapticIndex) {
        _lastHapticIndex = next;
        HapticFeedback.selectionClick();
      }
    }
    setState(() {});
  }

  void _scheduleMeasure() {
    if (_measured) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _measured || widget.order.isEmpty) return;
      // Skip until a real width is available: a tile measured at width 0 wraps
      // its text into a tall sliver, and latching that would space every tile
      // hundreds of pixels apart.
      if (_lastTileWidth <= 0) return;
      final RenderObject? box = widget
          .tileKeys[widget.order.first]
          .currentContext
          ?.findRenderObject();
      // Only trust a measurement taken once the tile has actually been laid out
      // at the current list width.
      if (box is RenderBox &&
          box.hasSize &&
          box.size.height > 0 &&
          (box.size.width - _lastTileWidth).abs() < 0.5) {
        _measured = true;
        if ((box.size.height - _tileHeight).abs() > 0.5) {
          setState(() => _tileHeight = box.size.height);
        }
      }
    });
  }

  /// Resting/landing slot top for a tile at [displayIndex].
  double _slotTop(int displayIndex) {
    if (_dragId == null) {
      return widget.topPadding + displayIndex * _extent;
    }
    final int slot = ReorderMath.visualSlotFor(
      displayIndex: displayIndex,
      draggedIndex: _dragFromIndex,
      insertionIndex: _insertionIndex,
    );
    return widget.topPadding + slot * _extent;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleMeasure();
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double tileWidth = max(0, width - 2 * widget.horizontalPadding);
        // Remember the width tiles are laid out at so the post-frame measure can
        // reject readings taken before a real width arrives (see
        // [_scheduleMeasure]).
        _lastTileWidth = tileWidth;
        final int n = widget.order.length;
        // One extra row for the trailing dashed "add" tile (when shown), so it
        // sits below the reminders as the list's last item.
        final int rows = n + (widget.showAddRow ? 1 : 0);
        final double contentHeight = rows > 0
            ? rows * _tileHeight + (rows - 1) * widget.itemGap
            : 0;
        final double totalHeight =
            widget.topPadding + contentHeight + widget.bottomPadding;

        // Whichever tile should paint above the others (a lifted/landing tile,
        // else the expanding one), rendered last so it is on top.
        final int? activeId = _dragId ?? _settlingId ?? widget.expandedId;

        final List<Widget> children = <Widget>[];
        Widget? activeChild;
        for (int displayIndex = 0; displayIndex < n; displayIndex++) {
          final int id = widget.order[displayIndex];
          // The reminder being added renders as the morphing "+"-into-tile while
          // its add animation runs; it can't be dragged, the active child, or
          // hidden, so it shortcuts the regular tile build.
          if (id == widget.addingId && widget.addAnimation != null) {
            children.add(
              _buildEmergingTile(
                id: id,
                top: _slotTop(displayIndex),
                width: tileWidth,
              ),
            );
            continue;
          }
          final bool isDragged = id == _dragId;
          final double left = isDragged
              ? _draggedLeft()
              : widget.horizontalPadding;
          final double top = isDragged ? _draggedTop() : _slotTop(displayIndex);

          final Widget tile = _buildTile(
            displayIndex: displayIndex,
            id: id,
            left: left,
            top: top,
            width: tileWidth,
            animatePosition: !isDragged,
          );
          if (id == activeId) {
            activeChild = tile;
          } else {
            children.add(tile);
          }
        }

        // The "add" affordance is the list's last row (when shown). Skipped
        // entirely while the list is empty: the empty state owns the add
        // affordance then, so a stray dashed circle shouldn't peek out from
        // behind it. See [AddReminderRow] for the morph / edit fade-out
        // behaviour.
        if (widget.showAddRow) {
          children.add(
            AddReminderRow(
              key: const ValueKey<String>('add-tile'),
              onAdd: widget.onAdd,
              editing: widget.editing,
              addingId: widget.addingId,
              addAnimation: widget.addAnimation,
              left: widget.horizontalPadding,
              top: widget.topPadding + n * _extent,
              width: tileWidth,
              height: _tileHeight,
              duration: _moveDuration,
              curve: _moveCurve,
            ),
          );
        }

        // The lifted/landing or expanding tile paints above the rest, the add
        // row included.
        if (activeChild != null) children.add(activeChild);

        return SizedBox(
          key: _stackKey,
          width: width,
          height: totalHeight,
          // Resting tiles draw as cheap fake glass (tint + edge rim, no backdrop
          // blur), so the whole list scrolls smoothly without a per-row filter.
          // A tile that is actively expanding, lifted or dragged frosts what it
          // floats over (see [ReminderTile]); the modal does the same in its
          // overlay.
          child: Stack(clipBehavior: Clip.none, children: children),
        );
      },
    );
  }

  /// The reminder being added, rendered at its (fixed) slot as the morphing
  /// "+"-into-tile. It shares the per-id [AnimatedPositioned] key with the
  /// regular tile build, so when the parent swaps it for a real [ReminderTile]
  /// (to hand off into the modal) the slot stays put with no jump.
  Widget _buildEmergingTile({
    required int id,
    required double top,
    required double width,
  }) {
    return AnimatedPositioned(
      key: ValueKey<String>('reorder-tile-$id'),
      duration: _moveDuration,
      curve: _moveCurve,
      left: widget.horizontalPadding,
      top: top,
      width: width,
      child: EmergingReminderTile(
        animation: widget.addAnimation!,
        item: widget.items[id],
        enabled: widget.enabledIds.contains(id),
        height: _tileHeight,
        fullWidth: width,
        compact: widget.compact,
      ),
    );
  }

  Widget _buildTile({
    required int displayIndex,
    required int id,
    required double left,
    required double top,
    required double width,
    required bool animatePosition,
  }) {
    final bool active = id == _dragId || id == _settlingId;
    // The keyed [AnimatedPositioned] stays here (not inside
    // [DraggableReminderTile]) so the Stack-children reconciliation and the
    // emerging "+"-into-tile hand-off keep the exact same shape: both the
    // emerging tile and the real tile present an `AnimatedPositioned` with the
    // same `reorder-tile-$id` key, so the slot animation survives the swap.
    return AnimatedPositioned(
      key: ValueKey<String>('reorder-tile-$id'),
      duration: animatePosition ? _moveDuration : Duration.zero,
      curve: _moveCurve,
      left: left,
      top: top,
      width: width,
      child: DraggableReminderTile(
        item: widget.items[id],
        enabled: widget.enabledIds.contains(id),
        expanded: widget.expandedId == id,
        editing: widget.editing,
        marked: widget.markedIds.contains(id),
        // Hidden — but keeping its slot — while it owns the modal or is mid
        // dissolve; in both cases an overlay is the only visible copy.
        hidden: widget.hiddenId == id,
        dissolving: widget.dissolvingIds.contains(id),
        compact: widget.compact,
        chipRemaining: widget.timerRemaining[id],
        active: active,
        lift: _lift,
        tiltX: _tiltX,
        tiltY: _tiltY,
        tileKey: widget.tileKeys[id],
        dragEnabled: widget.dragEnabled,
        onToggle: () => widget.onToggle(id),
        onExpandTap: () => widget.onExpandTap(id),
        onExpandComplete: () => widget.onExpandComplete(id),
        onDeleteTap: () => widget.onToggleMarked(id),
        onDragStart: (LongPressStartDetails d) => _startDrag(displayIndex, id, d),
        onDragUpdate: _updateDrag,
        onDragEnd: _endDrag,
        onDragCancel: _cancelDrag,
        onPaintStart: (Offset pos) => _startPaint(displayIndex, id, pos),
        onPaintUpdate: _updatePaint,
        onPaintEnd: _endPaint,
      ),
    );
  }
}
