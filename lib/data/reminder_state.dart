import '../models/reminder_item.dart';

/// The full snapshot of reminder state that survives a restart.
///
/// `RemindersScreen` keys its runtime state by an integer id (an index into a
/// grow-only list), but those ids are an in-memory artifact: deletions never
/// reclaim them, so they would drift further from the visible list on every
/// edit. The persisted form is therefore *compacted in display order* — the
/// list index doubles as the order — and the runtime ids are reassigned
/// `0..n-1` on load.
///
/// Everything except [items] is a list parallel to [items] (same length, same
/// order):
///  * [enabled] — whether each reminder's notification is on;
///  * [timerFiresAt] — a running timer's absolute fire moment (non-null only
///    for an armed timer; always null for alarms and disabled timers);
///  * [notificationIds] — each reminder's stable OS notification id, which must
///    outlive the runtime-id reassignment so a disable/delete cancels the right
///    scheduled notification even after a restart.
///
/// [nextNotificationId] is the monotonic counter the screen draws new
/// notification ids from, persisted so ids are never reused across launches.
class ReminderState {
  const ReminderState({
    required this.items,
    required this.enabled,
    required this.timerFiresAt,
    required this.notificationIds,
    required this.nextNotificationId,
    required this.hasCreatedReminder,
  });

  /// The reminders, already in display order.
  final List<ReminderItem> items;

  /// Whether each reminder's notification is on. Parallel to [items].
  final List<bool> enabled;

  /// Each armed timer's absolute fire time, else null. Parallel to [items].
  final List<DateTime?> timerFiresAt;

  /// Each reminder's stable OS notification id. Parallel to [items].
  final List<int> notificationIds;

  /// The next OS notification id to hand out; never reused.
  final int nextNotificationId;

  /// Whether the user has ever created a reminder. Stays true once set, even
  /// after every reminder is deleted, so the empty state can greet a genuine
  /// first launch ("Welcome") differently from a returning, cleared list
  /// ("All clear").
  final bool hasCreatedReminder;

  /// The state for a fresh install: no reminders, and nothing ever created.
  factory ReminderState.empty() => const ReminderState(
    items: <ReminderItem>[],
    enabled: <bool>[],
    timerFiresAt: <DateTime?>[],
    notificationIds: <int>[],
    nextNotificationId: 0,
    hasCreatedReminder: false,
  );

  /// The hardcoded demo set, every reminder enabled. Used as a test/demo
  /// fixture only — production starts from [empty]. Enabled timers are armed
  /// (anchored to `now + length`) so the fixture is self-consistent with the
  /// wall-clock timer model.
  factory ReminderState.fromKReminders() {
    final DateTime now = DateTime.now();
    return ReminderState(
      items: List<ReminderItem>.of(kReminders),
      enabled: List<bool>.filled(kReminders.length, true),
      timerFiresAt: <DateTime?>[
        for (final ReminderItem item in kReminders)
          item.type == ReminderType.timer ? now.add(item.time!) : null,
      ],
      notificationIds: <int>[for (int i = 0; i < kReminders.length; i++) i],
      nextNotificationId: kReminders.length,
      hasCreatedReminder: true,
    );
  }

  /// Encodes the snapshot as a JSON-compatible map, tagged with a schema
  /// [version] so a future format change can be detected on load.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'items': items.map((ReminderItem item) => item.toJson()).toList(),
    'enabled': enabled,
    'timerFiresAt': timerFiresAt
        .map((DateTime? d) => d?.toIso8601String())
        .toList(),
    'notificationIds': notificationIds,
    'nextNotificationId': nextNotificationId,
    'hasCreatedReminder': hasCreatedReminder,
  };

  /// Rebuilds a snapshot from [json]. Returns [empty] for an unknown schema
  /// version, and realigns every parallel list to [items] so a corrupt or
  /// partially written blob (whose lists are the wrong length) can't make the
  /// screen index past the end. A structurally broken payload — e.g. `items` is
  /// not a list — still throws; the repository catches that and falls back to
  /// [empty], so a bad blob shows the empty state rather than crashing.
  factory ReminderState.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) return ReminderState.empty();
    final List<ReminderItem> items = (json['items'] as List<dynamic>)
        .map(
          (dynamic e) =>
              ReminderItem.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList();
    final int count = items.length;
    final (List<int> ids, int next) = _alignNotificationIds(
      json['notificationIds'] as List<dynamic>?,
      count,
      json['nextNotificationId'] as int? ?? 0,
    );
    return ReminderState(
      items: items,
      enabled: _aligned<bool>(
        json['enabled'] as List<dynamic>?,
        count,
        (Object? e) => e is bool ? e : false,
        false,
      ),
      timerFiresAt: _aligned<DateTime?>(
        json['timerFiresAt'] as List<dynamic>?,
        count,
        (Object? e) => e is String ? DateTime.tryParse(e) : null,
        null,
      ),
      notificationIds: ids,
      nextNotificationId: next,
      // Older blobs predate this flag; treat any list that already holds
      // reminders as "has created" so an existing user never sees "Welcome".
      hasCreatedReminder:
          (json['hasCreatedReminder'] as bool?) ?? items.isNotEmpty,
    );
  }
}

/// Resizes [source] to exactly [length] entries so a persisted parallel list
/// stays in lock-step with `items`: each present element is converted with
/// [convert], any shortfall (or a null/absent source) is filled with [fill],
/// and extras are dropped. Guards against an externally corrupted blob whose
/// lists don't match the item count.
List<T> _aligned<T>(
  List<dynamic>? source,
  int length,
  T Function(Object? element) convert,
  T fill,
) {
  return <T>[
    for (int i = 0; i < length; i++)
      if (source != null && i < source.length) convert(source[i]) else fill,
  ];
}

/// Aligns the stored notification ids to [length] entries, minting a fresh id
/// for any gap or non-integer entry, and returns them with a [next] counter
/// that leads every id in use. Minting starts above all stored ids, so a short
/// or corrupt blob can't leave the screen indexing past the end or hand out a
/// colliding id.
(List<int>, int) _alignNotificationIds(
  List<dynamic>? stored,
  int length,
  int next,
) {
  if (stored != null) {
    for (final Object? value in stored) {
      if (value is int && value >= next) next = value + 1;
    }
  }
  final List<int> ids = <int>[];
  for (int i = 0; i < length; i++) {
    final Object? value = (stored != null && i < stored.length)
        ? stored[i]
        : null;
    if (value is int) {
      ids.add(value);
    } else {
      ids.add(next);
      next++;
    }
  }
  return (ids, next);
}
