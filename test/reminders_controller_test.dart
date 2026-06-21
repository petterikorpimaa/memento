// Pure-Dart unit tests for RemindersController — the domain logic exercised
// without pumping a widget, using the in-memory repository + recording
// notification service as seams. This is the payoff of pulling the logic out of
// the screen's State: persistence, notification scheduling and the timer model
// are now testable directly.

import 'package:flutter_test/flutter_test.dart';

import 'package:memento/data/in_memory_reminder_repository.dart';
import 'package:memento/data/reminder_repository.dart';
import 'package:memento/data/reminder_state.dart';
import 'package:memento/models/reminder_item.dart';
import 'package:memento/screens/reminders_controller.dart';

import 'support/recording_notification_service.dart';

ReminderItem alarm(String title) => ReminderItem(
  title: title,
  subtitle: '',
  type: ReminderType.alarm,
  date: DateTime(2030, 1, 1, 9),
);

ReminderItem timer(String title, Duration length) => ReminderItem(
  title: title,
  subtitle: '',
  type: ReminderType.timer,
  time: length,
);

ReminderState seedAlarm({required bool enabled, required int notificationId}) =>
    ReminderState(
      items: <ReminderItem>[alarm('A')],
      enabled: <bool>[enabled],
      timerFiresAt: <DateTime?>[null],
      notificationIds: <int>[notificationId],
      nextNotificationId: notificationId + 1,
      hasCreatedReminder: true,
    );

ReminderState seedAlarms(int count, {required List<int> ids}) => ReminderState(
  items: <ReminderItem>[
    for (int i = 0; i < count; i++) alarm(String.fromCharCode(65 + i)),
  ],
  enabled: <bool>[for (int i = 0; i < count; i++) true],
  timerFiresAt: <DateTime?>[for (int i = 0; i < count; i++) null],
  notificationIds: ids,
  nextNotificationId: ids.fold<int>(0, (int a, int b) => a > b ? a : b) + 1,
  hasCreatedReminder: true,
);

/// Builds an initialised controller and registers its disposal (which cancels
/// the 1s countdown timer). Caller awaits [settle] to let the async load run.
RemindersController controllerFor({
  ReminderState? initial,
  ReminderRepository? repository,
  RecordingNotificationService? notifications,
}) {
  final RemindersController controller = RemindersController(
    repository:
        repository ??
        InMemoryReminderRepository(initial ?? ReminderState.empty()),
    notificationService: notifications ?? RecordingNotificationService(),
  );
  addTearDown(controller.dispose);
  controller.init();
  return controller;
}

/// Lets pending microtasks (the async load) drain.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('loads items, enabled and timers from the repository', () async {
    final RemindersController c = controllerFor(
      initial: ReminderState(
        items: <ReminderItem>[
          alarm('A'),
          timer('T', const Duration(minutes: 5)),
        ],
        enabled: <bool>[true, true],
        timerFiresAt: <DateTime?>[
          null,
          DateTime.now().add(const Duration(minutes: 5)),
        ],
        notificationIds: <int>[0, 1],
        nextNotificationId: 2,
        hasCreatedReminder: true,
      ),
    );
    await settle();

    expect(c.loaded, isTrue);
    expect(c.items, hasLength(2));
    expect(c.enabled, containsAll(<int>[0, 1]));
    expect(c.timerRemaining[1], isNotNull);
  });

  test('toggle schedules then cancels by the stable notification id', () async {
    final RecordingNotificationService notifications =
        RecordingNotificationService();
    final RemindersController c = controllerFor(
      initial: seedAlarm(enabled: false, notificationId: 7),
      notifications: notifications,
    );
    await settle();

    c.toggle(0); // enable -> schedule under stable id 7
    expect(c.enabled, contains(0));
    expect(notifications.scheduled.single.id, 7);

    c.toggle(0); // disable -> cancel id 7
    expect(c.enabled, isNot(contains(0)));
    expect(notifications.cancelled, contains(7));
  });

  test('addDraft appends an enabled draft and persists it', () async {
    final InMemoryReminderRepository repo = InMemoryReminderRepository(
      ReminderState.empty(),
    );
    final RemindersController c = controllerFor(repository: repo);
    await settle();

    final int id = c.addDraft();
    expect(id, 0);
    expect(c.items, hasLength(1));
    expect(c.enabled, contains(0));
    expect(c.hasCreatedReminder, isTrue);

    // A fresh controller over the same repo sees the saved reminder.
    final RemindersController reloaded = controllerFor(repository: repo);
    await settle();
    expect(reloaded.items, hasLength(1));
  });

  test('reorder permutes display order and persists it', () async {
    final InMemoryReminderRepository repo = InMemoryReminderRepository(
      seedAlarms(3, ids: <int>[0, 1, 2]),
    );
    final RemindersController c = controllerFor(repository: repo);
    await settle();

    c.reorder(0, 2); // A,B,C -> B,C,A

    final RemindersController reloaded = controllerFor(repository: repo);
    await settle();
    expect(reloaded.items.map((ReminderItem e) => e.title).toList(), <String>[
      'B',
      'C',
      'A',
    ]);
  });

  test('commitDeletions removes tiles and cancels by stable id', () async {
    final RecordingNotificationService notifications =
        RecordingNotificationService();
    final RemindersController c = controllerFor(
      initial: seedAlarms(2, ids: <int>[5, 9]),
      notifications: notifications,
    );
    await settle();

    c.enterEditMode();
    c.toggleMarked(0);
    expect(c.markedForDeletion, contains(0));

    c.commitDeletions(dissolving: <int>{}, removeNow: <int>{0});
    expect(c.editing, isFalse);
    expect(c.order, isNot(contains(0)));
    expect(c.enabled, isNot(contains(0)));
    expect(notifications.cancelled, contains(5));
  });

  test('a dissolving tile holds its slot until reclaimSlot', () async {
    final RemindersController c = controllerFor(
      initial: seedAlarms(2, ids: <int>[5, 9]),
    );
    await settle();

    c.commitDeletions(dissolving: <int>{1}, removeNow: <int>{});
    expect(c.dissolvingIds, contains(1));
    expect(c.order, contains(1)); // still reserved while the dust settles

    c.reclaimSlot(1);
    expect(c.dissolvingIds, isEmpty);
    expect(c.order, isNot(contains(1)));
  });

  test('setType switches alarm<->timer keeping the one-of invariant', () async {
    final RemindersController c = controllerFor(
      initial: seedAlarm(enabled: true, notificationId: 0),
    );
    await settle();

    c.setType(0, ReminderType.timer);
    expect(c.items[0].type, ReminderType.timer);
    expect(c.items[0].time, isNotNull);
    expect(c.items[0].date, isNull);
    expect(c.timerRemaining[0], isNotNull);

    c.setType(0, ReminderType.alarm);
    expect(c.items[0].type, ReminderType.alarm);
    expect(c.items[0].date, isNotNull);
    expect(c.items[0].time, isNull);
  });

  test('title edits commit on close (finalize), not immediately', () async {
    final InMemoryReminderRepository repo = InMemoryReminderRepository(
      seedAlarm(enabled: true, notificationId: 0),
    );
    final RemindersController c = controllerFor(repository: repo);
    await settle();

    c.editTitleSubtitle(0, title: 'Renamed');
    expect(c.items[0].title, 'Renamed');

    // Not persisted until the modal closes.
    final RemindersController mid = controllerFor(repository: repo);
    await settle();
    expect(mid.items[0].title, isNot('Renamed'));

    c.finalize(0); // modal close
    final RemindersController after = controllerFor(repository: repo);
    await settle();
    expect(after.items[0].title, 'Renamed');
  });
}
