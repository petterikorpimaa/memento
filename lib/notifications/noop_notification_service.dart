import '../models/reminder_item.dart';
import 'notification_service.dart';

/// A [NotificationService] that does nothing.
///
/// Used on platforms `flutter_local_notifications` doesn't support (macOS,
/// Linux, Windows, web) and as the default in tests, so notification calls are
/// always safe to make from the screen without platform checks there.
class NoopNotificationService implements NotificationService {
  const NoopNotificationService();

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<void> scheduleReminder({
    required int notificationId,
    required ReminderItem item,
    required DateTime firesAt,
  }) async {}

  @override
  Future<void> cancel(int notificationId) async {}

  @override
  Future<void> cancelAll() async {}
}
