// Round-trips the persisted ReminderState envelope and checks its factories and
// version handling.

import 'package:flutter_test/flutter_test.dart';

import 'package:memento/data/reminder_state.dart';
import 'package:memento/models/reminder_item.dart';

void main() {
  test('a populated state round-trips through JSON', () {
    final DateTime firesAt = DateTime(2026, 6, 18, 12);
    final ReminderState state = ReminderState(
      items: <ReminderItem>[
        ReminderItem(
          title: 'Alarm',
          subtitle: '',
          type: ReminderType.alarm,
          date: DateTime(2026, 6, 18, 9),
        ),
        const ReminderItem(
          title: 'Timer',
          subtitle: '',
          type: ReminderType.timer,
          time: Duration(minutes: 10),
        ),
      ],
      enabled: <bool>[true, false],
      timerFiresAt: <DateTime?>[null, firesAt],
      notificationIds: <int>[3, 7],
      nextNotificationId: 8,
      hasCreatedReminder: true,
    );

    final ReminderState decoded = ReminderState.fromJson(state.toJson());

    expect(decoded.items, hasLength(2));
    expect(decoded.items[0].title, 'Alarm');
    expect(decoded.items[1].type, ReminderType.timer);
    expect(decoded.enabled, <bool>[true, false]);
    expect(decoded.timerFiresAt, <DateTime?>[null, firesAt]);
    expect(decoded.notificationIds, <int>[3, 7]);
    expect(decoded.nextNotificationId, 8);
    expect(decoded.hasCreatedReminder, isTrue);
  });

  test('empty() is genuinely empty and has never created a reminder', () {
    final ReminderState empty = ReminderState.empty();
    expect(empty.items, isEmpty);
    expect(empty.enabled, isEmpty);
    expect(empty.notificationIds, isEmpty);
    expect(empty.nextNotificationId, 0);
    expect(empty.hasCreatedReminder, isFalse);
  });

  test('fromKReminders arms enabled timers and assigns sequential ids', () {
    final ReminderState seed = ReminderState.fromKReminders();

    expect(seed.items, hasLength(kReminders.length));
    expect(seed.enabled.every((bool e) => e), isTrue);
    expect(seed.hasCreatedReminder, isTrue);
    expect(seed.nextNotificationId, kReminders.length);
    expect(seed.notificationIds, <int>[
      for (int i = 0; i < kReminders.length; i++) i,
    ]);

    // Every enabled timer is anchored; every alarm is not.
    for (int i = 0; i < seed.items.length; i++) {
      final bool isTimer = seed.items[i].type == ReminderType.timer;
      expect(seed.timerFiresAt[i] != null, isTimer);
    }
  });

  test('an unknown schema version decodes as empty', () {
    final ReminderState decoded = ReminderState.fromJson(<String, dynamic>{
      'version': 999,
    });
    expect(decoded.items, isEmpty);
  });

  test('a pre-flag blob with items is treated as having created reminders', () {
    // Older saves predate hasCreatedReminder; a non-empty list implies the user
    // has created before, so they should never see "Welcome".
    final ReminderState decoded = ReminderState.fromJson(<String, dynamic>{
      'version': 1,
      'items': <dynamic>[
        <String, dynamic>{
          'title': 'Old',
          'subtitle': '',
          'type': 'alarm',
          'date': DateTime(2026, 6, 18, 9).toIso8601String(),
          'recurring': false,
        },
      ],
      'enabled': <dynamic>[true],
      'timerFiresAt': <dynamic>[null],
      'notificationIds': <dynamic>[0],
      'nextNotificationId': 1,
    });
    expect(decoded.hasCreatedReminder, isTrue);
  });

  group('realigns parallel lists to items on corrupt input', () {
    // Three alarm items; the parallel lists are deliberately the wrong length.
    Map<String, dynamic> blobWith({
      required List<dynamic> enabled,
      required List<dynamic> timerFiresAt,
      required List<dynamic> notificationIds,
      int nextNotificationId = 0,
    }) => <String, dynamic>{
      'version': 1,
      'items': <dynamic>[
        for (int i = 0; i < 3; i++)
          <String, dynamic>{
            'title': 'R$i',
            'subtitle': '',
            'type': 'alarm',
            'date': DateTime(2026, 6, 18, 9).toIso8601String(),
            'recurring': false,
          },
      ],
      'enabled': enabled,
      'timerFiresAt': timerFiresAt,
      'notificationIds': notificationIds,
      'nextNotificationId': nextNotificationId,
    };

    test('short lists are padded so every list matches items', () {
      // The previously-fatal case: lists shorter than items would have thrown a
      // RangeError when the screen indexed them by item position.
      final ReminderState decoded = ReminderState.fromJson(
        blobWith(
          enabled: <dynamic>[true], // 1 of 3
          timerFiresAt: <dynamic>[], // 0 of 3
          notificationIds: <dynamic>[5], // 1 of 3
          nextNotificationId: 6,
        ),
      );

      expect(decoded.items, hasLength(3));
      expect(decoded.enabled, hasLength(3));
      expect(decoded.timerFiresAt, hasLength(3));
      expect(decoded.notificationIds, hasLength(3));
      // Padding defaults: missing enabled -> off, missing fire time -> null.
      expect(decoded.enabled, <bool>[true, false, false]);
      expect(decoded.timerFiresAt, <DateTime?>[null, null, null]);
    });

    test('long lists are truncated to the item count', () {
      final ReminderState decoded = ReminderState.fromJson(
        blobWith(
          enabled: <dynamic>[true, true, false, true, false],
          timerFiresAt: <dynamic>[null, null, null, null],
          notificationIds: <dynamic>[0, 1, 2, 3, 4],
          nextNotificationId: 5,
        ),
      );

      expect(decoded.enabled, <bool>[true, true, false]);
      expect(decoded.notificationIds, <int>[0, 1, 2]);
    });

    test('minted notification ids are unique and below nextNotificationId', () {
      // Only one stored id (5); the other two must be freshly minted without
      // colliding with it, and the counter must lead every id in use.
      final ReminderState decoded = ReminderState.fromJson(
        blobWith(
          enabled: <dynamic>[true, true, true],
          timerFiresAt: <dynamic>[null, null, null],
          notificationIds: <dynamic>[5],
          nextNotificationId: 0,
        ),
      );

      expect(decoded.notificationIds.toSet(), hasLength(3));
      expect(decoded.notificationIds, contains(5));
      for (final int id in decoded.notificationIds) {
        expect(id, lessThan(decoded.nextNotificationId));
      }
    });
  });
}
