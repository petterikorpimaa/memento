// Verifies the screen schedules and cancels OS notifications by each reminder's
// *stable* notification id — the id persisted with ReminderState, not the
// runtime list index. This is what lets a disable/delete cancel the right
// scheduled notification after a restart, once the persisted list has been
// compacted and the runtime ids reassigned.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/data/in_memory_reminder_repository.dart';
import 'package:memento/data/reminder_state.dart';
import 'package:memento/main.dart';
import 'package:memento/models/reminder_item.dart';
import 'package:memento/widgets/reminder_tile.dart';

import 'support/recording_notification_service.dart';

/// A single enabled/disabled alarm whose stable notification id is deliberately
/// not its list index (0), so a test can tell the two apart.
ReminderState seedOneAlarm({
  required bool enabled,
  required int notificationId,
}) => ReminderState(
  items: <ReminderItem>[
    ReminderItem(
      title: 'Dentist',
      subtitle: 'Cleaning',
      type: ReminderType.alarm,
      date: DateTime(2030, 1, 1, 9),
    ),
  ],
  enabled: <bool>[enabled],
  timerFiresAt: <DateTime?>[null],
  notificationIds: <int>[notificationId],
  nextNotificationId: notificationId + 1,
  hasCreatedReminder: true,
);

/// Resolves the async repository load and settles the populated list.
Future<void> pumpLoaded(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}

/// The (single) reminder's bell toggle.
final Finder bell = find.byIcon(Icons.notifications_none_rounded);

void main() {
  testWidgets(
    'disabling a reminder cancels its stable notification id, not its index',
    (WidgetTester tester) async {
      final RecordingNotificationService notifications =
          RecordingNotificationService();
      await tester.pumpWidget(
        MyApp(
          repository: InMemoryReminderRepository(
            // Stable id 7, while the runtime id is the list index 0.
            seedOneAlarm(enabled: true, notificationId: 7),
          ),
          notificationService: notifications,
        ),
      );
      await pumpLoaded(tester);
      expect(find.byType(ReminderTile), findsOneWidget);

      await tester.tap(bell);
      await tester.pump();

      // Cancelled by the stable id (7), never the runtime index (0).
      expect(notifications.cancelled, <int>[7]);
      expect(notifications.scheduled, isEmpty);
    },
  );

  testWidgets('the stable notification id survives a reload', (
    WidgetTester tester,
  ) async {
    final InMemoryReminderRepository repository = InMemoryReminderRepository(
      seedOneAlarm(enabled: false, notificationId: 7),
    );

    // First launch: enabling the bell schedules under the stable id, and the
    // enabled state persists to the repository.
    final RecordingNotificationService first = RecordingNotificationService();
    await tester.pumpWidget(
      MyApp(repository: repository, notificationService: first),
    );
    await pumpLoaded(tester);
    await tester.tap(bell);
    await tester.pump();
    expect(first.scheduled.single.id, 7);

    // Reload over the same repository with a fresh recorder — the runtime ids
    // are reassigned on load, but the persisted stable id is unchanged.
    await tester.pumpWidget(const SizedBox());
    final RecordingNotificationService second = RecordingNotificationService();
    await tester.pumpWidget(
      MyApp(repository: repository, notificationService: second),
    );
    await pumpLoaded(tester);
    expect(find.byType(ReminderTile), findsOneWidget);

    // Disabling now cancels that same stable id, proving it bridged the reload.
    await tester.tap(bell);
    await tester.pump();
    expect(second.cancelled, contains(7));
  });
}
