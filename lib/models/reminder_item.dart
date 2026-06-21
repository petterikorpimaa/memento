import 'package:flutter/material.dart';

/// What kind of reminder a row represents, which decides what its chip shows.
enum ReminderType {
  /// Fires at a fixed moment (carried by [ReminderItem.date]). The chip shows
  /// the time when it is due today, or the date when it is due on another day.
  alarm,

  /// Counts down over a fixed length (carried by [ReminderItem.time]). The chip
  /// shows a live, ticking countdown.
  timer,
}

/// Immutable description of a single reminder row.
///
/// Holds only display data — there is no enabled/notification state here.
/// Whether a reminder's notification is switched on is tracked separately by
/// the screen, so this model stays a pure, reusable value object. Its colour is
/// derived from [type] and [date] (see `reminderModeColor`), not stored here.
///
/// Exactly one of [date] / [time] is used, picked by [type]: alarms carry a
/// [date], timers carry a [time].
@immutable
class ReminderItem {
  const ReminderItem({
    required this.title,
    required this.subtitle,
    required this.type,
    this.date,
    this.time,
    this.recurring = false,
  }) : assert(
         type == ReminderType.alarm ? date != null : time != null,
         'An alarm needs a date; a timer needs a time.',
       );

  /// Primary label, e.g. "Morning workout".
  final String title;

  /// Secondary description, e.g. "Leg day at the gym".
  final String subtitle;

  /// Whether this is a fixed-time alarm or a counting-down timer.
  final ReminderType type;

  /// Whether the reminder repeats. A recurring alarm reschedules weekly and
  /// badges its chip with a repeat icon. There is currently no UI to toggle
  /// this (the modal's Repeat control was removed for now), but the flag is
  /// still honoured wherever it is set.
  final bool recurring;

  /// When an [ReminderType.alarm] fires. The chip shows the time if it's today,
  /// otherwise the date. Null for timers.
  final DateTime? date;

  /// A [ReminderType.timer]'s countdown length (hours, minutes, seconds). The
  /// chip counts down from this. Null for alarms.
  final Duration? time;

  /// Returns a copy with the given fields replaced — the immutable way to edit
  /// a reminder (e.g. from the modal's title/description fields).
  ///
  /// It can set [date] or [time] but, by design, cannot *clear* either: a null
  /// argument means "leave unchanged", not "remove". So this must not be used to
  /// switch [type] (an alarm carries a [date], a timer a [time]) — that would
  /// keep the old type's payload and break the one-of invariant. Construct a
  /// fresh [ReminderItem] for a type switch instead (see
  /// `RemindersScreen._setModalReminderType`).
  ReminderItem copyWith({
    String? title,
    String? subtitle,
    ReminderType? type,
    DateTime? date,
    Duration? time,
    bool? recurring,
  }) {
    return ReminderItem(
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      type: type ?? this.type,
      date: date ?? this.date,
      time: time ?? this.time,
      recurring: recurring ?? this.recurring,
    );
  }

  /// Encodes the reminder's display data as a JSON-compatible map.
  ///
  /// Enabled state, display order and a running timer's fire time live with the
  /// persisted `ReminderState` envelope, not here, so this stays pure display.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'subtitle': subtitle,
    'type': type.name,
    'date': date?.toIso8601String(),
    'time': time?.inMilliseconds,
    'recurring': recurring,
  };

  /// Rebuilds a reminder from [json], enforcing the alarm-needs-date /
  /// timer-needs-time invariant at this trust boundary.
  ///
  /// A missing or malformed payload is *repaired* to a safe default (an alarm
  /// an hour out, or a five-minute timer) rather than throwing, so a single bad
  /// entry can't break the whole stored list.
  factory ReminderItem.fromJson(Map<String, dynamic> json) {
    final ReminderType type = _reminderTypeFromName(json['type']);
    final Object? rawDate = json['date'];
    final Object? rawTime = json['time'];
    final DateTime? date = rawDate is String
        ? DateTime.tryParse(rawDate)
        : null;
    final Duration? time = rawTime is int
        ? Duration(milliseconds: rawTime)
        : null;
    return ReminderItem(
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      type: type,
      date: type == ReminderType.alarm
          ? (date ?? DateTime.now().add(const Duration(hours: 1)))
          : null,
      time: type == ReminderType.timer
          ? (time ?? const Duration(minutes: 5))
          : null,
      recurring: json['recurring'] as bool? ?? false,
    );
  }
}

/// Decodes a [ReminderType] from its [ReminderType.name], defaulting to
/// [ReminderType.alarm] for any unknown or missing value so decoding a corrupt
/// row never throws.
ReminderType _reminderTypeFromName(Object? name) =>
    ReminderType.values.firstWhere(
      (ReminderType t) => t.name == name,
      orElse: () => ReminderType.alarm,
    );

/// Accent colours used across the reminders list.
class ReminderColors {
  const ReminderColors._();

  /// Time mode — an alarm due today.
  static const Color teal = Color(0xFF5EEAD4);

  /// Timer mode — a counting-down reminder.
  static const Color pink = Color(0xFFF472B6);

  /// Date mode — an alarm due on another day.
  static const Color blue = Color(0xFF60A5FA);

  /// Brighter mint used for the floating action button.
  static const Color mint = Color(0xFF8AEAD0);

  /// Off white used for text and icons on the chips, and the chip borders.
  static const Color white = Color.fromARGB(255, 239, 242, 242);
}

/// Builds the demo reminders relative to "now", so the list exercises every
/// chip state: an alarm due today (shows the time), an alarm on a later day
/// (shows the date) and a timer (shows a live countdown). The alarm dates are
/// anchored to the current day, so this can't be a `const` list.
List<ReminderItem> _buildReminders() {
  final DateTime now = DateTime.now();

  // A time on the day `addDays` from today. DateTime normalises day overflow,
  // so `+7` rolls into the next month correctly.
  DateTime onDay(int addDays, int hour, int minute) =>
      DateTime(now.year, now.month, now.day + addDays, hour, minute);

  return <ReminderItem>[
    ReminderItem(
      title: 'Morning workout',
      subtitle: 'Leg day at the gym',
      type: ReminderType.alarm,
      date: onDay(0, 18, 30), // today -> teal clock + "18:30"
    ),
    ReminderItem(
      title: 'Call Mom',
      subtitle: 'Weekly catch-up call',
      type: ReminderType.alarm,
      date: onDay(7, 19, 0), // later -> blue calendar + "dd.MM."
      recurring: true, // weekly -> repeat badge on the chip
    ),
    ReminderItem(
      title: 'Water the plants',
      subtitle: 'Monstera & the herbs',
      type: ReminderType.timer,
      time: const Duration(minutes: 25), // pink hourglass countdown "25:00"
    ),
    ReminderItem(
      title: 'Pick up groceries',
      subtitle: 'Milk, eggs, coffee beans',
      type: ReminderType.alarm,
      date: onDay(0, 17, 30), // today -> teal clock + "17:30"
    ),
  ];
}

/// The set of reminders rendered by the list, anchored to the day the app
/// starts. See [_buildReminders] for why this isn't `const`.
final List<ReminderItem> kReminders = _buildReminders();

/// A fresh, blank reminder for the "add" flow.
///
/// The demo has no edit form, so a new reminder lands with placeholder copy and
/// a default alarm an hour out (a teal "time" chip while it stays today). It's
/// built per call — anchored to "now" — so it can't be a `const`.
ReminderItem newReminderDraft() => ReminderItem(
  title: '',
  subtitle: '',
  type: ReminderType.alarm,
  date: DateTime.now().add(const Duration(hours: 1)),
);
