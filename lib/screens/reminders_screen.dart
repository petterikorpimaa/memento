import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../constants/app_durations.dart';
import '../data/reminder_repository.dart';
import '../l10n/app_strings.dart';
import '../l10n/locale_scope.dart';
import '../models/reminder_item.dart';
import '../notifications/notification_service.dart';
import '../widgets/disintegration_overlay.dart';
import '../widgets/empty_state_layer.dart';
import '../widgets/reminder_modal.dart';
import '../widgets/reminder_modal_geometry.dart';
import '../widgets/reminders_header.dart';
import '../widgets/reorderable_reminder_list.dart';
import 'reminders_controller.dart';

/// The "Reminders" tab content: a header whose subtitle reflects how many
/// reminders are active, followed by the scrollable list of reminders.
///
/// Owns the interaction state: which notifications are on, which single tile is
/// brought "closer", and — once that finishes — the floating modal it expands
/// into.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    super.key,
    required this.onOpenSettings,
    required this.compactView,
    required this.repository,
    required this.notificationService,
  });

  /// Opens the settings page; wired to the header's settings button.
  final VoidCallback onOpenSettings;

  /// Whether the list renders in its compact layout. Owned by [HomeShell] and
  /// flipped from the settings page; read here to drive the tiles (and the
  /// modal a tile hands off into).
  final ValueListenable<bool> compactView;

  /// Loads the reminders on start and is rewritten the whole snapshot on every
  /// edit (add, toggle, reorder, delete, modal edit).
  final ReminderRepository repository;

  /// Schedules / cancels the OS notifications that back enabled reminders.
  final NotificationService notificationService;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // List layout, kept as named constants so the modal target can be derived
  // from the exact same values.
  static const double _hPadding = 20;
  static const double _topPadding = 6;
  static const double _bottomPadding = 80;
  static const double _tileGap = 10;

  /// How far the modal's bottom edge sits above the body bottom — matched to
  /// Flutter's default `kFloatingActionButtonMargin` so it clears the home
  /// indicator with a comfortable inset.
  static const double _modalBottomMargin = 16;

  /// The view-model: the single owner of the reminder list, what's enabled, the
  /// order, running timers, persistence and OS-notification scheduling. The
  /// screen is a thin view over it, so these getters delegate to keep the build
  /// and animation code reading one source of truth; user intent routes to its
  /// methods (see [_toggle], [_addReminder], the modal-edit handlers, …).
  late final RemindersController _controller = RemindersController(
    repository: widget.repository,
    notificationService: widget.notificationService,
  );

  List<ReminderItem> get _items => _controller.items;
  Set<int> get _enabled => _controller.enabled;
  List<int> get _order => _controller.order;
  bool get _loaded => _controller.loaded;
  bool get _hasCreatedReminder => _controller.hasCreatedReminder;
  bool get _editing => _controller.editing;
  Set<int> get _markedForDeletion => _controller.markedForDeletion;
  Set<int> get _dissolvingIds => _controller.dissolvingIds;
  Map<int, ValueNotifier<Duration>> get _timerRemaining =>
      _controller.timerRemaining;

  /// The single reminder brought "closer", or null. Owning this here keeps the
  /// expansion to one tile at a time.
  int? _expandedIndex;

  /// Local mirror of [RemindersScreen.compactView], kept in sync by a listener
  /// so the whole build (list and the modal hand-off) reads one value.
  late bool _compact = widget.compactView.value;

  /// The reminder currently promoted into the floating modal, or null.
  int? _modalIndex;

  /// The tile slot the modal grows from, in viewport coordinates.
  Rect? _modalSourceRect;

  /// A header action (Edit or Settings) tapped while a modal is open. Rather
  /// than acting at once — which would clear the expansion and reverse the
  /// hidden tile's "closer" scale while it's still invisible, swallowing its
  /// rest animation (Edit), or slide a new route in over a lingering modal
  /// (Settings) — we let the modal play its full close and run this from
  /// [_onModalStatus] once it has dismissed.
  VoidCallback? _afterModalClose;

  /// Morphs the modal card from the tile slot to the full modal area.
  late final AnimationController _modalController;
  late final CurvedAnimation _modalExpand;

  /// Grows the divider out from its centre once the modal has expanded.
  late final AnimationController _dividerController;

  /// Fades and scales the edit fields in, started only once the modal has
  /// finished expanding, so they arrive after the card has settled.
  late final AnimationController _fieldsController;

  /// Hosts the modal in the app's root overlay so the card paints above the
  /// Scaffold's floating "+" button instead of behind it.
  final OverlayPortalController _modalPortalController =
      OverlayPortalController();

  /// The single reminder being added, or null. Its tile renders the morphing
  /// "+"-into-tile while [_addController] runs, after which it is handed off to
  /// the modal like a tapped tile.
  int? _addingId;

  /// When non-null, the id of a reminder being added from the empty state's
  /// "New reminder" button. Its morph and its "closer" lean are hosted on that
  /// button (not the list), so the new reminder appears right where you tapped
  /// and animates exactly as a list add does; the list hides it until the modal
  /// opens (see [_onTileExpandComplete]).
  int? _emptyAddId;

  /// Drives the add morph: the "+" button growing into a tile and the new
  /// reminder's content fading in. On completion the tile floats up as a modal.
  late final AnimationController _addController;

  /// Identifies the add tile while it morphs and leans on the empty state's
  /// "New reminder" button, so the modal can grow from that exact spot.
  final GlobalKey _addOriginKey = GlobalKey();

  /// Approximate resting row heights used to size the add-from-empty morph; the
  /// real tile re-measures once it joins the list, so these need only be close.
  static const double _rowHeight = 78;
  static const double _compactRowHeight = 60;

  /// Lets us measure the list viewport and each tile's slot. Grows alongside
  /// [_items] so every reminder — including freshly added ones — has a key.
  final GlobalKey _viewportKey = GlobalKey();
  final List<GlobalKey> _tileKeys = <GlobalKey>[];

  @override
  void initState() {
    super.initState();
    _modalController = AnimationController(
      vsync: this,
      duration: AppDurations.normal,
    );
    _modalExpand = CurvedAnimation(
      parent: _modalController,
      curve: Curves.easeOutCubic,
    );
    _dividerController = AnimationController(
      vsync: this,
      duration: AppDurations.normal,
    );
    _fieldsController = AnimationController(
      vsync: this,
      duration: AppDurations.normal,
    );
    _addController = AnimationController(
      vsync: this,
      duration: AppDurations.slow,
    );
    _modalController.addStatusListener(_onModalStatus);
    _addController.addStatusListener(_onAddStatus);
    _controller.addListener(_onControllerChanged);
    widget.compactView.addListener(_onCompactChanged);
    WidgetsBinding.instance.addObserver(this);
    _controller.init();
  }

  /// Rebuilds the view on any controller change, and grows one measurement key
  /// per reminder — ids are append-only within a session, so the key list only
  /// ever grows to match.
  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      while (_tileKeys.length < _items.length) {
        _tileKeys.add(GlobalKey());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.compactView.removeListener(_onCompactChanged);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    // Dispose the CurvedAnimation before its parent controller so it drops the
    // status listener it attached to it.
    _modalExpand.dispose();
    _modalController.dispose();
    _dividerController.dispose();
    _fieldsController.dispose();
    _addController.dispose();
    super.dispose();
  }

  /// Re-anchors armed timers and refreshes alarm chips when the app returns to
  /// the foreground; the work lives in the controller.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _controller.onResume();
  }

  void _onCompactChanged() {
    if (!mounted || _compact == widget.compactView.value) return;
    setState(() => _compact = widget.compactView.value);
  }

  void _onModalStatus(AnimationStatus status) {
    if (status == AnimationStatus.forward) {
      // Modal expanding -> grow the divider alongside it.
      _dividerController.forward();
    } else if (status == AnimationStatus.completed) {
      // Modal fully open -> reveal the edit fields on top of the settled card.
      _fieldsController.forward();
    } else if (status == AnimationStatus.dismissed) {
      // Modal fully closed -> drop it and let the tile play its collapse.
      final int? closingId = _modalIndex;
      _modalPortalController.hide();
      _controller.setPausedTimer(null);
      setState(() {
        _modalIndex = null;
        _modalSourceRect = null;
        _expandedIndex = null;
      });
      // Finalize the edited reminder: its title / subtitle commit on close (not
      // per keystroke), and its notification is (re)synced to the final timing.
      if (closingId != null) _controller.finalize(closingId);
      // A header action (Edit / Settings) tapped while the modal was open
      // waited for it to finish closing; run it now.
      final VoidCallback? pending = _afterModalClose;
      _afterModalClose = null;
      pending?.call();
    }
  }

  /// Flips one reminder's bell (delegated to the controller, which arms the
  /// timer, syncs the notification and persists).
  void _toggle(int index) => _controller.toggle(index);

  /// Adopts the enabled set computed by the bell's paint-to-toggle sweep.
  void _setEnabled(Set<int> enabled) => _controller.setEnabledSweep(enabled);

  /// Tapped the trailing dashed "add" row. Appends a fresh reminder and starts
  /// its entrance: the "+" button morphs into the new tile (the icon fades out,
  /// a glass tile grows in, then the reminder's content fades in), and once that
  /// completes the tile floats up into the modal — see [_onAddStatus].
  void _addReminder() {
    // One add at a time, and not while a tile is already opening / in the modal
    // or while editing (the delete buttons own the tiles then).
    if (_addingId != null ||
        _expandedIndex != null ||
        _modalIndex != null ||
        _editing) {
      return;
    }
    // Read "from empty" before the append makes the order non-empty.
    final bool fromEmpty = _order.isEmpty;
    // The controller appends the draft (and grows the tile keys via the change
    // listener); the view drives its entrance morph.
    final int newId = _controller.addDraft();
    setState(() {
      _addingId = newId;
      _emptyAddId = fromEmpty ? newId : null;
    });
    _addController.forward(from: 0);
  }

  /// The add morph finished: the new tile is fully formed and pixel-identical to
  /// a resting tile. Drop the "adding" state so it becomes an ordinary tile,
  /// then — on the next frame, so the freshly-mounted tile sees a real
  /// not-expanded -> expanded flip — play the same "closer" -> modal hand-off a
  /// tap would, finishing the add by floating it up as the open modal.
  void _onAddStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final int? id = _addingId;
    if (id == null) return;
    setState(() => _addingId = null);
    // Bailed into edit mode mid-morph: leave the tile in place — and, if it was
    // an empty-state add, hand it back to the list as a resting row.
    if (_editing) {
      if (_emptyAddId != null) setState(() => _emptyAddId = null);
      return;
    }
    // The morph is done; on the next frame flip the (now real) tile to expanded
    // so it plays its "closer" lean and then hands off into the modal — the same
    // path a tap takes, whether the tile sits in the list or, for an empty-state
    // add, on the "New reminder" button (see the add-origin tile in [build]).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _editing ||
          _expandedIndex != null ||
          _modalIndex != null) {
        return;
      }
      setState(() => _expandedIndex = id);
    });
  }

  /// Moves the tile at display position [from] to [to].
  void _onReorder(int from, int to) => _controller.reorder(from, to);

  /// The header's edit / cancel button. Out of edit mode it enters it (letting
  /// an open modal close first); in edit mode it cancels — leaving edit mode
  /// and discarding the marked set, so nothing is deleted (see [_cancelEditing]
  /// vs the confirm button's [_commitEditing]).
  void _onEditPressed() {
    if (_editing) {
      _cancelEditing();
    } else if (_modalIndex != null) {
      // A modal is open: let it close fully first — so its collapse and the
      // tile's rest animation play all the way out — then enter edit mode once
      // it has dismissed (see [_onModalStatus]). Clearing the expansion now
      // would reverse the hidden tile early, so its rest animation never shows.
      _afterModalClose = _enterEditMode;
      _dismissModal();
    } else {
      _enterEditMode();
    }
  }

  /// Leaves edit mode without deleting anything (the marked set is dropped).
  void _cancelEditing() => _controller.cancelEditing();

  /// Commits the pending deletions and leaves edit mode (the confirm check):
  /// each marked tile is snapshotted into a "Thanos" disintegration that plays
  /// in place while the tile keeps its slot; the controller then drops them from
  /// the list (dissolving ones later, via [_reclaimSlot]) and cancels their
  /// notifications.
  void _commitEditing() {
    final Set<int> dissolving = <int>{};
    final Set<int> removeNow = <int>{};
    // Capture each marked tile while it's still visible: a captured tile keeps
    // its slot until its dust nears the end (then [_reclaimSlot]); one that
    // can't be captured is dropped at once.
    for (final int id in _markedForDeletion) {
      final bool started = playDisintegration(
        context,
        _tileKeys[id],
        onReclaim: () => _reclaimSlot(id),
        // Cap the combined particle count: a batch of N tiles dissolves into
        // no more dust than three tiles would alone.
        simultaneous: _markedForDeletion.length,
      );
      (started ? dissolving : removeNow).add(id);
    }
    _controller.commitDeletions(dissolving: dissolving, removeNow: removeNow);
  }

  /// Enters edit mode: leave any in-progress expansion (the delete buttons own
  /// the tiles now); the controller clears the marked set and flips the flag.
  void _enterEditMode() {
    setState(() => _expandedIndex = null);
    _controller.enterEditMode();
  }

  /// Opens the settings page. With a modal open it is closed first — playing
  /// its full close, like Edit — so settings never slides in over a lingering
  /// modal and returning lands on the plain list.
  void _openSettings() {
    if (_modalIndex != null) {
      _afterModalClose = widget.onOpenSettings;
      _dismissModal();
    } else {
      widget.onOpenSettings();
    }
  }

  /// A dissolving tile hands its slot back (a little before its dust fully
  /// settles): the controller drops it so the gap closes and the tiles below
  /// slide up, overlapping the dissolve's final fade. Guarded by [mounted] —
  /// the overlay can fire this after the screen is gone.
  void _reclaimSlot(int id) {
    if (mounted) _controller.reclaimSlot(id);
  }

  /// Toggles one tile's marked-for-deletion state (a tap on its delete button).
  void _toggleMarked(int id) => _controller.toggleMarked(id);

  /// Adopts the marked set computed by the list's paint-to-delete sweep.
  void _setMarked(Set<int> marked) => _controller.setMarked(marked);

  void _toggleExpanded(int index) {
    if (_editing || _addingId != null) return; // Busy editing / adding.
    if (_modalIndex != null) {
      // While a modal is open any tap closes it.
      _dismissModal();
      return;
    }
    setState(() {
      _expandedIndex = _expandedIndex == index ? null : index;
    });
  }

  /// Hand-off from the tile's "closer" animation into the floating modal.
  void _onTileExpandComplete(int index) {
    if (_expandedIndex != index || _modalIndex != null) return;
    // An empty-state add leans on the "New reminder" button, so measure there;
    // an ordinary tile is measured in the list.
    final Rect? rect = index == _emptyAddId
        ? ModalGeometry.rectInViewport(_addOriginKey, _viewportKey)
        : _tileRectInViewport(index);
    if (rect == null) {
      // Couldn't measure the slot to grow the modal from. Don't strand the tile
      // expanded (and stuck on the real-glass shader) with no modal — collapse
      // it back to resting.
      setState(() {
        _expandedIndex = null;
        _emptyAddId = null;
      });
      return;
    }
    _controller.setPausedTimer(null); // A fresh modal starts its preview live.
    setState(() {
      _modalIndex = index;
      _modalSourceRect = rect;
      // The add has landed: hand the slot back to the list (hidden under the
      // modal) and retire the empty state.
      _emptyAddId = null;
    });
    _modalPortalController.show();
    _modalController.forward(from: 0);
  }

  void _dismissModal() {
    if (_modalController.status == AnimationStatus.dismissed) return;
    // Re-aim the collapse at the tile's current resting slot. A modal opened
    // from the empty state's add button must fold back into the list, not back
    // to that (now-gone) button spot; for an ordinary modal this re-measures
    // the same slot, so it's a no-op.
    final int? id = _modalIndex;
    if (id != null) {
      final Rect? rect = _tileRectInViewport(id);
      if (rect != null && rect != _modalSourceRect) {
        setState(() => _modalSourceRect = rect);
      }
    }
    // Drop the keyboard if a field was being edited, then fold the fields,
    // divider and card back away together.
    FocusManager.instance.primaryFocus?.unfocus();
    _fieldsController.reverse();
    _dividerController.reverse();
    _modalController.reverse();
  }

  /// Commits a live title / description edit to the modal's reminder. The
  /// controller commits it on close (via [RemindersController.finalize]), not
  /// per keystroke.
  void _editModalReminder({String? title, String? subtitle}) {
    final int? id = _modalIndex;
    if (id != null) {
      _controller.editTitleSubtitle(id, title: title, subtitle: subtitle);
    }
  }

  /// Commits a date picked in the modal's alarm picker to the reminder.
  void _setModalReminderDate(DateTime date) {
    final int? id = _modalIndex;
    if (id != null) _controller.setDate(id, date);
  }

  /// Commits a duration picked in the modal's timer picker. The controller
  /// freezes the preview and re-anchors an armed timer from the new length.
  void _setModalReminderDuration(Duration duration) {
    final int? id = _modalIndex;
    if (id != null) _controller.setDuration(id, duration);
  }

  /// Switches the modal reminder between alarm and timer. The controller keeps
  /// the one-of payload invariant and freezes the preview.
  void _setModalReminderType(ReminderType type) {
    final int? id = _modalIndex;
    if (id != null) _controller.setType(id, type);
  }

  /// The tapped tile's slot rectangle expressed in the viewport's coordinates
  /// (see [ModalGeometry.rectInViewport]).
  Rect? _tileRectInViewport(int index) =>
      ModalGeometry.rectInViewport(_tileKeys[index], _viewportKey);

  /// The modal card hosted in the app's root overlay, or an empty box when no
  /// modal is open. The source / target rects are in viewport coordinates, so
  /// they're shifted by the viewport origin to land in the full-screen overlay.
  Widget _buildModalOverlay(
    BuildContext context,
    BoxConstraints constraints,
    Rect targetRect,
  ) {
    if (_modalIndex == null || _modalSourceRect == null) {
      return const SizedBox.shrink();
    }
    final Offset origin = ModalGeometry.viewportOrigin(_viewportKey);
    return ReminderModalOverlay(
      item: _items[_modalIndex!],
      enabled: _enabled.contains(_modalIndex!),
      sourceRect: _modalSourceRect!.shift(origin),
      targetRect: targetRect.shift(origin),
      // Cover only the list body (the viewport, sized by the LayoutBuilder), so
      // the header above it stays tappable.
      barrierRect: origin & Size(constraints.maxWidth, constraints.maxHeight),
      expandAnimation: _modalExpand,
      dividerAnimation: _dividerController,
      fieldsAnimation: _fieldsController,
      onDismiss: _dismissModal,
      onToggle: () => _toggle(_modalIndex!),
      onTitleChanged: (String value) => _editModalReminder(title: value),
      onSubtitleChanged: (String value) => _editModalReminder(subtitle: value),
      onTypeChanged: _setModalReminderType,
      onDateChanged: _setModalReminderDate,
      onDurationChanged: _setModalReminderDuration,
      remaining: _timerRemaining[_modalIndex!],
      compact: _compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Withhold the list until the first load resolves. The repository load is
    // near-instant (one read), so this is a single frame in practice; an empty
    // box keeps the page's gradient and never builds a (blurred) glass surface.
    if (!_loaded) return const SizedBox.expand();
    final AppStrings strings = LocaleScope.stringsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        RemindersHeader(
          title: strings.remindersTitle,
          subtitle: strings.activeReminders(_enabled.length),
          settingsTooltip: strings.settingsTitle,
          editing: _editing,
          hasChanges: _markedForDeletion.isNotEmpty,
          onEditPressed: _onEditPressed,
          onConfirm: _commitEditing,
          onOpenSettings: _openSettings,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              // The list runs to the physical screen bottom; subtract the home
              // indicator inset so the modal ends above it, not behind it.
              final double bottomInset = MediaQuery.paddingOf(context).bottom;
              // The rect the modal expands into — keeping the tile's scaled-out
              // "closer" width and lifting its top to the scaled tile's top (see
              // [ModalGeometry.targetRect]). Because the modal's own scale eases
              // to 1.0 by the end, this widened target is what actually shows.
              final Rect targetRect = ModalGeometry.targetRect(
                constraints: constraints,
                sourceHeight: _modalSourceRect?.height ?? 0,
                hPadding: _hPadding,
                topPadding: _topPadding,
                bottomMargin: _modalBottomMargin,
                bottomInset: bottomInset,
              );
              // Once every reminder is cleared, the list hands the screen over
              // to the "all clear" empty state (which carries its own add
              // affordance, so the list drops its trailing "+" row).
              //
              // A reminder added from the empty state is hosted on its "New
              // reminder" button (not the list) all the way through its morph
              // and "closer" lean, so it animates exactly as a list add does but
              // right where it was tapped. It's hidden from the list until the
              // modal opens, then the populated list reappears beneath it.
              final int? hostId = _emptyAddId;
              final List<int> visibleOrder = hostId == null
                  ? _order
                  : _order.where((int id) => id != hostId).toList();
              final bool isEmpty = visibleOrder.isEmpty;
              // Match a real reminder row's footprint so the morph and the
              // modal it grows into line up exactly with the list.
              final double addTileWidth = constraints.maxWidth - 2 * _hPadding;
              final double addTileHeight = _compact
                  ? _compactRowHeight
                  : _rowHeight;
              return Stack(
                key: _viewportKey,
                fit: StackFit.expand,
                children: <Widget>[
                  SingleChildScrollView(
                    // The reorderable list paints its own padding into the slot
                    // positions, so the scroll view adds none of its own.
                    // Clamping physics in both modes: a sweep that starts on a
                    // bell/delete button paints (the button's vertical-drag
                    // recogniser wins the arena over the scrollable — see
                    // [_PaintToggleButton]), and a drag anywhere else scrolls.
                    // Edit mode scrolls too, so long lists stay reachable while
                    // marking. Clamping (rather than bouncing) physics also feeds
                    // the platform stretch overscroll (see AppScrollBehavior) for
                    // the native Samsung-style rubber band at the ends.
                    physics: const ClampingScrollPhysics(),
                    child: ReorderableReminderList(
                      order: visibleOrder,
                      items: _items,
                      tileKeys: _tileKeys,
                      enabledIds: _enabled,
                      expandedId: _expandedIndex,
                      hiddenId: _modalIndex,
                      // Don't start a reorder drag while a tile is opening into /
                      // sitting in the modal, while editing (the delete button
                      // owns the drag then), or while tiles are dissolving (their
                      // reserved slots would shift under the dust overlays).
                      dragEnabled:
                          _modalIndex == null &&
                          _expandedIndex == null &&
                          _addingId == null &&
                          !_editing &&
                          _dissolvingIds.isEmpty,
                      horizontalPadding: _hPadding,
                      topPadding: _topPadding,
                      bottomPadding: _bottomPadding,
                      itemGap: _tileGap,
                      onToggle: _toggle,
                      onExpandTap: _toggleExpanded,
                      onExpandComplete: _onTileExpandComplete,
                      onReorder: _onReorder,
                      editing: _editing,
                      markedIds: _markedForDeletion,
                      dissolvingIds: _dissolvingIds,
                      onToggleMarked: _toggleMarked,
                      onMarkedChanged: _setMarked,
                      onEnabledChanged: _setEnabled,
                      onAdd: _addReminder,
                      // Kept while editing — the list fades/scales it out in
                      // place — and dropped only when empty (the empty state
                      // owns the add affordance then).
                      showAddRow: !isEmpty,
                      // The list never renders the add-from-empty tile — the
                      // empty state hosts it on its button instead.
                      addingId: hostId != null ? null : _addingId,
                      addAnimation: _addController,
                      compact: _compact,
                      timerRemaining: _timerRemaining,
                    ),
                  ),
                  // The "all clear" empty state crossfades in over the (now
                  // contentless) list whenever every reminder has been removed,
                  // and out again the moment one is added (see [EmptyStateLayer]).
                  EmptyStateLayer(
                    isEmpty: isEmpty,
                    hostId: hostId,
                    addingId: _addingId,
                    addAnimation: _addController,
                    hostItem: hostId == null ? null : _items[hostId],
                    hostEnabled: hostId != null && _enabled.contains(hostId),
                    hostExpanded: _expandedIndex == hostId,
                    hostChipRemaining: hostId == null
                        ? null
                        : _timerRemaining[hostId],
                    addOriginKey: _addOriginKey,
                    addTileWidth: addTileWidth,
                    addTileHeight: addTileHeight,
                    firstLaunch: !_hasCreatedReminder,
                    compact: _compact,
                    onAdd: _addReminder,
                    onToggleHost: () {
                      if (hostId != null) _toggle(hostId);
                    },
                    onExpandHost: () {
                      if (hostId != null) _toggleExpanded(hostId);
                    },
                    onExpandHostComplete: () {
                      if (hostId != null) _onTileExpandComplete(hostId);
                    },
                  ),
                  // Host the modal in the app's root overlay so it paints above
                  // everything in this page. Its rects are in viewport
                  // coordinates, so shift them to global to match the
                  // full-screen overlay.
                  OverlayPortal(
                    controller: _modalPortalController,
                    overlayChildBuilder: (BuildContext context) =>
                        _buildModalOverlay(context, constraints, targetRect),
                    child: const SizedBox.shrink(),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
