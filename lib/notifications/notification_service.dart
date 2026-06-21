import '../models/reminder_item.dart';

/// Schedules and cancels the OS notifications that back reminders.
///
/// [scheduleReminder] takes the reminder's *stable* notification id (persisted
/// with `ReminderState`, not the screen's runtime id), so a notification can be
/// cancelled across an app restart. Implementations: `LocalNotificationService`
/// on Android/iOS, `NoopNotificationService` everywhere else (and in tests).
abstract interface class NotificationService {
  /// Prepares the platform plugin (timezone data, channels). Safe to call once
  /// at startup.
  Future<void> init();

  /// Asks the user for notification permission, returning whether it's granted.
  Future<bool> requestPermissions();

  /// Schedules a single notification for [item] to fire at [firesAt]. A
  /// recurring alarm repeats weekly; a timer or one-off alarm fires once.
  Future<void> scheduleReminder({
    required int notificationId,
    required ReminderItem item,
    required DateTime firesAt,
  });

  /// Cancels the notification with [notificationId], if any is scheduled.
  Future<void> cancel(int notificationId);

  /// Cancels every scheduled notification.
  Future<void> cancelAll();
}
