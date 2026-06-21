import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../data/reminder_repository.dart';
import '../data/reminder_state.dart';
import '../models/reminder_item.dart';
import '../notifications/notification_service.dart';
import '../utils/timer_math.dart';

/// The reminders screen's view-model: the single owner of the *domain* state
/// (the list, what's enabled, the order, running timers, the persisted
/// notification ids) and the business logic that mutates it — loading,
/// persistence, OS-notification scheduling and the wall-clock timer model.
///
/// It deliberately knows nothing about widgets or animation. `RemindersScreen`
/// is a thin view that listens to this controller, renders from its getters,
/// and routes user intent to its methods; the screen keeps only the ephemeral
/// UI state (animation controllers, the modal/expansion choreography, the
/// measurement keys). Keeping the logic here makes it unit-testable in plain
/// Dart — no widget pumping — and lets a future second screen reuse it.
///
/// State is keyed by an integer id = an index into [items], a grow-only list:
/// deletions never reclaim ids within a session, so all id-keyed state stays
/// stable. The persisted form is compacted in display order, so ids are
/// reassigned `0..n-1` on the next [_load]; the separate, persisted stable
/// [_platformIds] bridges that reassignment so a disable/delete cancels the
/// right OS notification after a restart.
class RemindersController extends ChangeNotifier {
  RemindersController({
    required this.repository,
    required this.notificationService,
  });

  /// Loads the snapshot on start and is rewritten the whole snapshot on every
  /// edit (add, toggle, reorder, delete, modal edit).
  final ReminderRepository repository;

  /// Schedules / cancels the OS notifications that back enabled reminders.
  final NotificationService notificationService;

  List<ReminderItem> _items = <ReminderItem>[];
  Set<int> _enabled = <int>{};
  List<int> _order = <int>[];
  bool _loaded = false;
  final Map<int, DateTime> _firesAt = <int, DateTime>{};
  Map<int, int> _platformIds = <int, int>{};
  int _nextNotificationId = 0;
  bool _hasCreatedReminder = false;
  bool _permissionsAsked = false;
  bool _editing = false;
  Set<int> _markedForDeletion = <int>{};
  Set<int> _dissolvingIds = <int>{};
  final Map<int, ValueNotifier<Duration>> _timerRemaining =
      <int, ValueNotifier<Duration>>{};
  Timer? _countdownTimer;

  /// The timer whose live countdown is frozen because its timing is being
  /// edited in the open modal, or null. Set by the timing edits; cleared by the
  /// view when the modal opens/closes.
  int? _pausedTimerId;

  bool _disposed = false;

  /// The reminders, in id order (display order is [order]).
  List<ReminderItem> get items => _items;

  /// Ids of reminders whose notification is currently on.
  Set<int> get enabled => _enabled;

  /// Display order as reminder ids.
  List<int> get order => _order;

  /// Whether the first load from the repository has completed.
  bool get loaded => _loaded;

  /// Whether the user has ever created a reminder (drives the empty-state copy).
  bool get hasCreatedReminder => _hasCreatedReminder;

  /// Whether the list is in edit mode (bells become delete toggles).
  bool get editing => _editing;

  /// Ids marked for deletion while editing.
  Set<int> get markedForDeletion => _markedForDeletion;

  /// Ids mid-dissolve; still holding their slot until the dust settles.
  Set<int> get dissolvingIds => _dissolvingIds;

  /// How many reminders are enabled (the header subtitle count).
  int get enabledCount => _enabled.length;

  /// The per-id live-countdown notifiers, shared so a tick repaints only the
  /// listening chip — the list tile and the modal read the same notifier.
  Map<int, ValueNotifier<Duration>> get timerRemaining => _timerRemaining;

  /// Starts the 1s countdown tick and kicks off the (async) load. Call once,
  /// from the view's `initState`.
  void init() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), _tick);
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _countdownTimer?.cancel();
    for (final ValueNotifier<Duration> notifier in _timerRemaining.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  /// Notifies listeners unless we've been disposed — async completions (load)
  /// and the overlay's reclaim callback can land after the screen is gone.
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  // --- loading & persistence ---------------------------------------------

  Future<void> _load() async {
    final ReminderState state = await _loadState();
    if (_disposed) return;
    try {
      _hydrateFrom(state);
    } catch (error, stackTrace) {
      developer.log(
        'Stored reminders were inconsistent; starting empty.',
        name: 'memento.persistence',
        error: error,
        stackTrace: stackTrace,
      );
      _hydrateFrom(ReminderState.empty());
    }
    _loaded = true;
    _safeNotify();
  }

  /// Reads the persisted snapshot, degrading to [ReminderState.empty] if the
  /// repository itself throws (e.g. the platform store is unavailable).
  Future<ReminderState> _loadState() async {
    try {
      return await repository.load();
    } catch (error, stackTrace) {
      developer.log(
        'Could not load stored reminders; starting empty.',
        name: 'memento.persistence',
        error: error,
        stackTrace: stackTrace,
      );
      return ReminderState.empty();
    }
  }

  /// Rebuilds id-keyed state from a persisted [state]: the stored list is
  /// already in display order, so ids are its indices and the order is the
  /// identity permutation.
  void _hydrateFrom(ReminderState state) {
    final int count = state.items.length;
    final DateTime now = DateTime.now();
    _items = List<ReminderItem>.of(state.items);
    _order = <int>[for (int id = 0; id < count; id++) id];
    _enabled = <int>{
      for (int id = 0; id < count; id++)
        if (state.enabled[id]) id,
    };
    _platformIds = <int, int>{
      for (int id = 0; id < count; id++) id: state.notificationIds[id],
    };
    _nextNotificationId = state.nextNotificationId;
    _hasCreatedReminder = state.hasCreatedReminder;
    _firesAt.clear();
    for (int id = 0; id < count; id++) {
      if (_items[id].type != ReminderType.timer) continue;
      final DateTime? firesAt = state.timerFiresAt[id];
      if (_enabled.contains(id) && firesAt != null) {
        _firesAt[id] = firesAt;
        _timerRemaining[id] = ValueNotifier<Duration>(
          TimerMath.remaining(firesAt, now),
        );
      } else {
        _timerRemaining[id] = ValueNotifier<Duration>(_items[id].time!);
      }
    }
  }

  /// Snapshots the current state into a persistable [ReminderState], compacted
  /// in display order. Reminders mid-dissolve are already gone from the save.
  ReminderState _snapshotState() {
    final List<int> ids = _order
        .where((int id) => !_dissolvingIds.contains(id))
        .toList();
    return ReminderState(
      items: <ReminderItem>[for (final int id in ids) _items[id]],
      enabled: <bool>[for (final int id in ids) _enabled.contains(id)],
      timerFiresAt: <DateTime?>[for (final int id in ids) _firesAt[id]],
      notificationIds: <int>[for (final int id in ids) _platformIds[id] ?? id],
      nextNotificationId: _nextNotificationId,
      hasCreatedReminder: _hasCreatedReminder,
    );
  }

  void _persist() => unawaited(repository.save(_snapshotState()));

  // --- notifications ------------------------------------------------------

  void _maybeRequestPermissions() {
    if (_permissionsAsked) return;
    _permissionsAsked = true;
    unawaited(notificationService.requestPermissions());
  }

  /// Schedules or cancels the OS notification for [id] to match its current
  /// enabled state and timing, using its stable notification id.
  void _syncNotificationFor(int id) {
    final int platformId = _platformIds[id] ?? id;
    final ReminderItem item = _items[id];
    final DateTime? firesAt = item.type == ReminderType.timer
        ? _firesAt[id]
        : item.date;
    if (!_enabled.contains(id) || firesAt == null) {
      unawaited(notificationService.cancel(platformId));
      return;
    }
    _maybeRequestPermissions();
    unawaited(
      notificationService.scheduleReminder(
        notificationId: platformId,
        item: item,
        firesAt: firesAt,
      ),
    );
  }

  /// Schedules/cancels and persists [id] after a modal closes — its title /
  /// timing have settled, so commit them once here (not per keystroke).
  void finalize(int id) {
    _syncNotificationFor(id);
    _persist();
  }

  // --- the wall-clock timer model ----------------------------------------

  /// Arms or disarms [id]'s timer to match its enabled state: enabling anchors
  /// it to `now + length`; disabling drops the anchor and resets to full.
  void _applyArming(int id) {
    if (_items[id].type != ReminderType.timer) return;
    if (_enabled.contains(id)) {
      final DateTime now = DateTime.now();
      final DateTime firesAt = now.add(_items[id].time!);
      _firesAt[id] = firesAt;
      _timerRemaining[id]?.value = TimerMath.remaining(firesAt, now);
    } else {
      _firesAt.remove(id);
      _timerRemaining[id]?.value = _items[id].time!;
    }
  }

  /// Advances every timer's countdown one second by writing each notifier — so
  /// only the listening chips repaint. Off timers show full length; the
  /// modal-edited one holds; the rest tick down. Writing an unchanged value is
  /// a no-op, so an idle frame costs nothing.
  void _tick(Timer _) {
    for (final MapEntry<int, ValueNotifier<Duration>> entry
        in _timerRemaining.entries) {
      final int id = entry.key;
      if (_items[id].type != ReminderType.timer) continue;
      final ValueNotifier<Duration> notifier = entry.value;
      if (!_enabled.contains(id) || _firesAt[id] == null) {
        notifier.value = _items[id].time!;
      } else if (id == _pausedTimerId) {
        // Being edited -> hold in place.
      } else if (notifier.value != Duration.zero) {
        final Duration decremented =
            notifier.value - const Duration(seconds: 1);
        notifier.value = decremented.isNegative ? Duration.zero : decremented;
      }
    }
  }

  /// Reverts every switched-off timer to its full length at once, so a bell
  /// toggle reads as an instant reset rather than waiting for the next tick.
  void _revertDisabledTimers() {
    for (final MapEntry<int, ValueNotifier<Duration>> entry
        in _timerRemaining.entries) {
      final int id = entry.key;
      if (_items[id].type == ReminderType.timer && !_enabled.contains(id)) {
        entry.value.value = _items[id].time!;
      }
    }
  }

  /// Re-anchors armed timers and refreshes alarm chips when the app returns to
  /// the foreground (time has passed while backgrounded).
  void onResume() {
    if (!_loaded) return;
    final DateTime now = DateTime.now();
    for (final MapEntry<int, ValueNotifier<Duration>> entry
        in _timerRemaining.entries) {
      final int id = entry.key;
      final DateTime? firesAt = _firesAt[id];
      if (_items[id].type == ReminderType.timer &&
          _enabled.contains(id) &&
          firesAt != null) {
        entry.value.value = TimerMath.remaining(firesAt, now);
      }
    }
    _safeNotify();
  }

  /// Freezes (or, with null, unfreezes) the live countdown of the timer whose
  /// timing is being edited in the modal. Cleared by the view on open/close.
  void setPausedTimer(int? id) => _pausedTimerId = id;

  // --- intents ------------------------------------------------------------

  /// Flips [id]'s notification on/off, arming/disarming its timer to match.
  void toggle(int id) {
    final Set<int> next = Set<int>.from(_enabled);
    if (!next.add(id)) next.remove(id);
    _enabled = next;
    _applyArming(id);
    _revertDisabledTimers();
    _syncNotificationFor(id);
    _persist();
    _safeNotify();
  }

  /// Adopts the enabled set computed by the bell's paint-to-toggle sweep, then
  /// arms / cancels and persists every reminder the sweep flipped.
  void setEnabledSweep(Set<int> enabled) {
    final Set<int> changed = <int>{
      ..._enabled.difference(enabled),
      ...enabled.difference(_enabled),
    };
    _enabled = enabled;
    for (final int id in changed) {
      _applyArming(id);
    }
    _revertDisabledTimers();
    for (final int id in changed) {
      _syncNotificationFor(id);
    }
    _persist();
    _safeNotify();
  }

  /// Appends a fresh draft reminder (enabled, with a stable notification id)
  /// and returns its id. The view drives the add morph; the notification is
  /// scheduled when the modal closes via [finalize].
  int addDraft() {
    final int newId = _items.length;
    _items = <ReminderItem>[..._items, newReminderDraft()];
    _order = <int>[..._order, newId];
    _enabled = <int>{..._enabled, newId};
    _platformIds = <int, int>{..._platformIds, newId: _nextNotificationId};
    _nextNotificationId++;
    _hasCreatedReminder = true;
    _persist();
    _safeNotify();
    return newId;
  }

  /// Moves the tile at display position [from] to [to].
  void reorder(int from, int to) {
    if (from == to) return;
    final List<int> next = List<int>.from(_order);
    final int moved = next.removeAt(from);
    next.insert(to, moved);
    _order = next;
    _persist();
    _safeNotify();
  }

  /// Enters edit mode from a clear marked set.
  void enterEditMode() {
    _markedForDeletion = <int>{};
    _editing = true;
    _safeNotify();
  }

  /// Leaves edit mode without deleting anything (the marked set is dropped).
  void cancelEditing() {
    _markedForDeletion = <int>{};
    _editing = false;
    _safeNotify();
  }

  /// Toggles one tile's marked-for-deletion state.
  void toggleMarked(int id) {
    final Set<int> next = Set<int>.from(_markedForDeletion);
    if (!next.add(id)) next.remove(id);
    _markedForDeletion = next;
    _safeNotify();
  }

  /// Adopts the marked set computed by the list's paint-to-delete sweep.
  void setMarked(Set<int> marked) {
    _markedForDeletion = marked;
    _safeNotify();
  }

  /// Commits the pending deletions and leaves edit mode. The view has already
  /// captured each tile's snapshot and split them into [dissolving] (playing
  /// their dust) and [removeNow] (could not be captured): the former keep their
  /// slot until [reclaimSlot]; the latter drop immediately. Every deleted
  /// reminder's notification is cancelled by its stable id.
  void commitDeletions({
    required Set<int> dissolving,
    required Set<int> removeNow,
  }) {
    if (removeNow.isNotEmpty) {
      _order = _order.where((int id) => !removeNow.contains(id)).toList();
      _enabled = _enabled.where((int id) => !removeNow.contains(id)).toSet();
    }
    _dissolvingIds = <int>{..._dissolvingIds, ...dissolving};
    _markedForDeletion = <int>{};
    _editing = false;
    for (final int id in <int>{...removeNow, ...dissolving}) {
      unawaited(notificationService.cancel(_platformIds[id] ?? id));
    }
    _persist();
    _safeNotify();
  }

  /// A dissolving tile hands its slot back: drop it so the list closes the gap.
  void reclaimSlot(int id) {
    if (_disposed) return;
    _order = _order.where((int e) => e != id).toList();
    _enabled = _enabled.where((int e) => e != id).toSet();
    _dissolvingIds = _dissolvingIds.where((int e) => e != id).toSet();
    _persist();
    _safeNotify();
  }

  // --- modal edits --------------------------------------------------------

  /// Commits a live title / description edit. Persists on modal close (via
  /// [finalize]), not per keystroke.
  void editTitleSubtitle(int id, {String? title, String? subtitle}) {
    final List<ReminderItem> next = List<ReminderItem>.from(_items);
    next[id] = next[id].copyWith(title: title, subtitle: subtitle);
    _items = next;
    _safeNotify();
  }

  /// Commits a date picked in the alarm picker. The reminder is always an alarm
  /// here, so this keeps the timer field null and the invariant intact.
  void setDate(int id, DateTime date) {
    final List<ReminderItem> next = List<ReminderItem>.from(_items);
    next[id] = next[id].copyWith(date: date);
    _items = next;
    _persist();
    _safeNotify();
  }

  /// Commits a duration picked in the timer picker, holding the live preview at
  /// the new length and re-anchoring an armed timer from it. Editing the length
  /// counts as editing the timing, so it freezes the preview.
  void setDuration(int id, Duration duration) {
    _pausedTimerId = id;
    final List<ReminderItem> next = List<ReminderItem>.from(_items);
    next[id] = next[id].copyWith(time: duration);
    _items = next;
    _timerRemaining[id]?.value = duration;
    if (_enabled.contains(id)) {
      _firesAt[id] = DateTime.now().add(duration);
    }
    _persist();
    _safeNotify();
  }

  /// Switches [id] between alarm and timer, keeping the payload the new type
  /// needs (reusing the existing value or a sensible default) and clearing the
  /// other. Touching the control freezes the preview, even if the type is
  /// unchanged.
  void setType(int id, ReminderType type) {
    _pausedTimerId = id;
    final ReminderItem current = _items[id];
    if (current.type == type) {
      _safeNotify();
      return;
    }
    final List<ReminderItem> next = List<ReminderItem>.from(_items);
    next[id] = ReminderItem(
      title: current.title,
      subtitle: current.subtitle,
      type: type,
      date: type == ReminderType.alarm
          ? (current.date ?? DateTime.now().add(const Duration(hours: 1)))
          : null,
      time: type == ReminderType.timer
          ? (current.time ?? const Duration(minutes: 5))
          : null,
      recurring: current.recurring,
    );
    _items = next;
    if (type == ReminderType.timer) {
      final Duration full = next[id].time!;
      final ValueNotifier<Duration>? existing = _timerRemaining[id];
      if (existing == null) {
        _timerRemaining[id] = ValueNotifier<Duration>(full);
      } else {
        existing.value = full;
      }
      if (_enabled.contains(id)) {
        _firesAt[id] = DateTime.now().add(full);
      }
    } else {
      _firesAt.remove(id);
    }
    _persist();
    _safeNotify();
  }
}
