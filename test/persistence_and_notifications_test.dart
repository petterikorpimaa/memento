// End-to-end tests for the injected persistence + notification seam: an empty
// store opens to the empty state, an added reminder survives a reload, and an
// enabled reminder schedules an OS notification.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/data/in_memory_reminder_repository.dart';
import 'package:memento/data/reminder_state.dart';
import 'package:memento/main.dart';
import 'package:memento/models/reminder_item.dart';
import 'package:memento/widgets/reminder_chip.dart';
import 'package:memento/widgets/reminder_modal.dart';
import 'package:memento/widgets/reminder_tile.dart';

import 'support/recording_notification_service.dart';

/// Pumps fixed 50ms steps until [finder] matches or [maxFrames] elapse — the
/// empty state animates forever, so `pumpAndSettle` never returns with it up.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 80,
}) async {
  for (int i = 0; i < maxFrames && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('a first launch greets the user with "Welcome"', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MyApp(
        repository: InMemoryReminderRepository(ReminderState.empty()),
        notificationService: RecordingNotificationService(),
      ),
    );
    await pumpUntilFound(tester, find.text('Welcome'));

    expect(find.byType(ReminderTile), findsNothing);
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('All clear'), findsNothing);
    expect(find.text('New reminder'), findsOneWidget);
  });

  testWidgets('a returning, fully-cleared list reads "All clear"', (
    WidgetTester tester,
  ) async {
    // Empty list, but the user has created a reminder before.
    final ReminderState cleared = ReminderState.empty();
    await tester.pumpWidget(
      MyApp(
        repository: InMemoryReminderRepository(
          ReminderState(
            items: cleared.items,
            enabled: cleared.enabled,
            timerFiresAt: cleared.timerFiresAt,
            notificationIds: cleared.notificationIds,
            nextNotificationId: cleared.nextNotificationId,
            hasCreatedReminder: true,
          ),
        ),
        notificationService: RecordingNotificationService(),
      ),
    );
    await pumpUntilFound(tester, find.text('All clear'));

    expect(find.text('All clear'), findsOneWidget);
    expect(find.text('Welcome'), findsNothing);
  });

  testWidgets('an added reminder survives a reload from the same repository', (
    WidgetTester tester,
  ) async {
    final InMemoryReminderRepository repository = InMemoryReminderRepository(
      ReminderState.empty(),
    );
    await tester.pumpWidget(
      MyApp(
        repository: repository,
        notificationService: RecordingNotificationService(),
      ),
    );
    await pumpUntilFound(tester, find.text('New reminder'));

    // Add a reminder from the empty state, name it, then close the modal.
    await tester.tap(find.text('New reminder'));
    await tester.pump(const Duration(milliseconds: 500)); // morph
    await pumpUntilFound(tester, find.byType(TextField));
    // The add retires the empty state, so the modal can now fully settle open
    // before we interact with it.
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Buy milk');
    await tester.pump();
    await tester.tap(
      find
          .descendant(
            of: find.byType(ReminderModalOverlay),
            matching: find.text('Buy milk'),
          )
          .first,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);

    // Re-mount a fresh app over the SAME repository: the reminder was saved.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MyApp(
        repository: repository,
        notificationService: RecordingNotificationService(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.byType(ReminderTile), findsOneWidget);
  });

  testWidgets('adding a reminder schedules its OS notification on close', (
    WidgetTester tester,
  ) async {
    final RecordingNotificationService notifications =
        RecordingNotificationService();
    await tester.pumpWidget(
      MyApp(
        repository: InMemoryReminderRepository(ReminderState.empty()),
        notificationService: notifications,
      ),
    );
    await pumpUntilFound(tester, find.text('New reminder'));

    await tester.tap(find.text('New reminder'));
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntilFound(tester, find.byType(TextField));
    // Dismiss via the modal's status chip (above the divider).
    await tester.tap(
      find.descendant(
        of: find.byType(ReminderModalOverlay),
        matching: find.byType(ReminderChip),
      ),
    );
    await tester.pumpAndSettle();

    // The new reminder lands enabled as an alarm, so closing it schedules one.
    expect(notifications.scheduled, isNotEmpty);
    expect(notifications.scheduled.last.item.type, ReminderType.alarm);
    expect(notifications.permissionRequests, greaterThan(0));
  });
}
