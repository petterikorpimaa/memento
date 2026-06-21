import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../constants/app_durations.dart';
import '../models/reminder_item.dart';

/// The pill shown on the right of each reminder row. What it shows — and the
/// colour it shows it in — depends on the reminder's [ReminderItem.type] and
/// [ReminderItem.date]:
///
///  * alarm due today  — teal clock icon + the time in 24h, e.g. "18:30";
///  * alarm on any other day — blue calendar icon + the date, e.g. "24.06.";
///  * timer — pink hourglass icon + the live countdown driven by [remaining].
///
/// The chip is a pure display: a timer's countdown is *not* ticked here. The
/// screen owns the running value and exposes it as a [ValueListenable], which
/// the chip subscribes to — so a tick repaints only this pill, not the whole
/// row. Sharing one listenable also means the value survives the tile -> modal
/// hand-off (no reset) and can be frozen centrally while the modal edits the
/// timing. [remaining] is null for alarms (and falls back to the full length if
/// a timer is somehow not supplied one).
///
/// Each mode has its own colour (see [reminderModeColor]), shared with the row's
/// bell so the whole row reads in one colour. The chip is greyed out when the
/// reminder is off so it stays visible without competing with active reminders.
class ReminderChip extends StatelessWidget {
  const ReminderChip({
    super.key,
    required this.item,
    required this.enabled,
    this.remaining,
  });

  final ReminderItem item;
  final bool enabled;

  /// Live countdown value for a timer reminder, owned by the screen. Null for
  /// alarms; falls back to [ReminderItem.time] (the full length) if unset.
  final ValueListenable<Duration>? remaining;

  @override
  Widget build(BuildContext context) {
    final Color color = reminderModeColor(item);
    final Widget chip = _chip(color);
    // A recurring reminder badges the chip's top-right corner with a small
    // repeat glyph, so the list reads "this one repeats" at a glance.
    if (!item.recurring) return chip;
    return _RepeatBadge(enabled: enabled, child: chip);
  }

  /// The chip body (without any recurring badge), picked by the reminder's type.
  Widget _chip(Color color) {
    switch (item.type) {
      case ReminderType.timer:
        final ValueListenable<Duration>? remaining = this.remaining;
        if (remaining == null) {
          return _countdownChip(item.time!, color);
        }
        // Only this builder repaints each tick; the rest of the row stays put.
        return ValueListenableBuilder<Duration>(
          valueListenable: remaining,
          builder: (BuildContext context, Duration value, _) =>
              _countdownChip(value, color),
        );
      case ReminderType.alarm:
        final DateTime date = item.date!;
        final bool today = _isSameDate(date, DateTime.now());
        return _ChipShell(
          icon: today
              ? Icons.access_time_rounded
              : Icons.calendar_today_rounded,
          label: today ? _formatTime(date) : _formatDate(date),
          color: color,
          enabled: enabled,
        );
    }
  }

  Widget _countdownChip(Duration value, Color color) => _ChipShell(
    icon: Icons.hourglass_bottom_rounded,
    label: _formatCountdown(value),
    color: color,
    enabled: enabled,
  );
}

/// The colour that identifies a reminder's mode, shared by its bell and chip:
/// teal for a time due today, blue for a date on another day, pink for a timer.
Color reminderModeColor(ReminderItem item) {
  switch (item.type) {
    case ReminderType.timer:
      return ReminderColors.pink;
    case ReminderType.alarm:
      return _isSameDate(item.date!, DateTime.now())
          ? ReminderColors.teal
          : ReminderColors.blue;
  }
}

/// The shared pill: an icon and a label inside a rounded, tinted container in
/// the mode's [color]. Coloured while [enabled]; greyed out otherwise.
class _ChipShell extends StatelessWidget {
  const _ChipShell({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;

  /// Muted colour used for the icon and label when the reminder is off.
  static const Color _mutedContent = Color(0xFF8A93A0);

  @override
  Widget build(BuildContext context) {
    final Color contentColor = enabled ? color : _mutedContent;
    final Color backgroundColor = enabled
        ? color.withValues(alpha: 0.14)
        : _mutedContent.withValues(alpha: 0.10);

    return AnimatedContainer(
      duration: AppDurations.fast,
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: contentColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: contentColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Overlays a small repeat glyph on the top-right corner of [child] (the status
/// chip) to flag a recurring reminder. The glyph is white while [enabled] and
/// muted grey when off, so it dims along with the rest of the chip.
class _RepeatBadge extends StatelessWidget {
  const _RepeatBadge({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  /// Muted colour used for the glyph when the reminder is off (matches the
  /// chip's own muted content).
  static const Color _mutedContent = Color(0xFF8A93A0);

  @override
  Widget build(BuildContext context) {
    final Color glyphColor = enabled ? ReminderColors.white : _mutedContent;
    return Stack(
      // Let the glyph sit just outside the chip's top-right corner without being
      // clipped to the chip's bounds.
      clipBehavior: Clip.none,
      children: <Widget>[
        child,
        Positioned(
          top: -2.5,
          right: -2.5,
          child: Icon(Icons.repeat_rounded, size: 13, color: glyphColor),
        ),
      ],
    );
  }
}

/// True when [a] and [b] fall on the same calendar day.
bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 24-hour clock time, zero-padded, e.g. "18:30" or "09:00".
String _formatTime(DateTime date) {
  final String hours = date.hour.toString().padLeft(2, '0');
  final String minutes = date.minute.toString().padLeft(2, '0');
  return '$hours:$minutes';
}

/// Day and month with a trailing dot, e.g. "24.06.".
String _formatDate(DateTime date) {
  final String day = date.day.toString().padLeft(2, '0');
  final String month = date.month.toString().padLeft(2, '0');
  return '$day.$month.';
}

/// Remaining time as a countdown: "M:SS" under an hour, "H:MM:SS" beyond it.
String _formatCountdown(Duration remaining) {
  final int hours = remaining.inHours;
  final int minutes = remaining.inMinutes.remainder(60);
  final String seconds = remaining.inSeconds
      .remainder(60)
      .toString()
      .padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}
