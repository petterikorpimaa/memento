import 'package:memento/models/reminder_item.dart';
import 'package:memento/notifications/notification_service.dart';

/// One recorded `scheduleReminder` call.
class ScheduledNotification {
  const ScheduledNotification(this.id, this.item, this.firesAt);

  final int id;
  final ReminderItem item;
  final DateTime firesAt;
}

/// A test [NotificationService] that records what the screen schedules and
/// cancels instead of touching any platform plugin.
class RecordingNotificationService implements NotificationService {
  final List<ScheduledNotification> scheduled = <ScheduledNotification>[];
  final List<int> cancelled = <int>[];
  int permissionRequests = 0;

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermissions() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> scheduleReminder({
    required int notificationId,
    required ReminderItem item,
    required DateTime firesAt,
  }) async {
    scheduled.add(ScheduledNotification(notificationId, item, firesAt));
  }

  @override
  Future<void> cancel(int notificationId) async =>
      cancelled.add(notificationId);

  @override
  Future<void> cancelAll() async {}
}
