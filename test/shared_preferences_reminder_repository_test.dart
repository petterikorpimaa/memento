// Exercises the shared_preferences-backed repository against a mocked prefs
// store: empty load, save/load round-trip, and corrupt-blob fallback.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memento/data/reminder_state.dart';
import 'package:memento/data/shared_preferences_reminder_repository.dart';
import 'package:memento/models/reminder_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferencesReminderRepository> repo() =>
      SharedPreferencesReminderRepository.create();

  test('an empty store loads as empty state', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ReminderState loaded = await (await repo()).load();
    expect(loaded.items, isEmpty);
  });

  test('save then load round-trips the snapshot', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferencesReminderRepository repository = await repo();

    final ReminderState state = ReminderState(
      items: const <ReminderItem>[
        ReminderItem(
          title: 'Timer',
          subtitle: '',
          type: ReminderType.timer,
          time: Duration(minutes: 5),
        ),
      ],
      enabled: const <bool>[true],
      timerFiresAt: <DateTime?>[DateTime(2026, 6, 18, 12)],
      notificationIds: const <int>[42],
      nextNotificationId: 43,
      hasCreatedReminder: true,
    );
    await repository.save(state);

    // A fresh repository over the same (persisted) store sees the saved data.
    final ReminderState loaded = await (await repo()).load();
    expect(loaded.items.single.title, 'Timer');
    expect(loaded.enabled, <bool>[true]);
    expect(loaded.notificationIds, <int>[42]);
    expect(loaded.nextNotificationId, 43);
  });

  test('a corrupt stored blob falls back to empty without throwing', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reminders_state_v1': 'not valid json {{{',
    });
    final ReminderState loaded = await (await repo()).load();
    expect(loaded.items, isEmpty);
  });
}
