// Covers the platform-free parts of the notification layer: the repeat-rule
// mapping and the no-op service used off Android/iOS and in tests.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/models/reminder_item.dart';
import 'package:memento/notifications/local_notification_service.dart';
import 'package:memento/notifications/noop_notification_service.dart';

void main() {
  group('notificationMatchComponents', () {
    test('a recurring alarm repeats weekly', () {
      final ReminderItem alarm = ReminderItem(
        title: 'Call Mom',
        subtitle: '',
        type: ReminderType.alarm,
        date: DateTime(2026, 6, 18, 19),
        recurring: true,
      );
      expect(
        notificationMatchComponents(alarm),
        DateTimeComponents.dayOfWeekAndTime,
      );
    });

    test('a one-off alarm fires once', () {
      final ReminderItem alarm = ReminderItem(
        title: 'Groceries',
        subtitle: '',
        type: ReminderType.alarm,
        date: DateTime(2026, 6, 18, 17),
      );
      expect(notificationMatchComponents(alarm), isNull);
    });

    test('a timer fires once, even if flagged recurring', () {
      const ReminderItem timer = ReminderItem(
        title: 'Tea',
        subtitle: '',
        type: ReminderType.timer,
        time: Duration(minutes: 3),
        recurring: true,
      );
      expect(notificationMatchComponents(timer), isNull);
    });
  });

  group('NoopNotificationService', () {
    test('grants permission and never throws', () async {
      const NoopNotificationService service = NoopNotificationService();
      await service.init();
      expect(await service.requestPermissions(), isTrue);
      await service.scheduleReminder(
        notificationId: 1,
        item: const ReminderItem(
          title: 'x',
          subtitle: '',
          type: ReminderType.timer,
          time: Duration(seconds: 1),
        ),
        firesAt: DateTime(2026, 6, 18),
      );
      await service.cancel(1);
      await service.cancelAll();
    });
  });
}
