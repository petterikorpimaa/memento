// Round-trips ReminderItem through JSON and checks the fail-soft repair the
// decoder applies at the storage boundary.

import 'package:flutter_test/flutter_test.dart';

import 'package:memento/models/reminder_item.dart';

void main() {
  test('alarm round-trips its date, type and recurring flag', () {
    final ReminderItem alarm = ReminderItem(
      title: 'Call Mom',
      subtitle: 'Weekly catch-up',
      type: ReminderType.alarm,
      date: DateTime(2026, 6, 18, 19, 30),
      recurring: true,
    );

    final ReminderItem decoded = ReminderItem.fromJson(alarm.toJson());

    expect(decoded.title, alarm.title);
    expect(decoded.subtitle, alarm.subtitle);
    expect(decoded.type, ReminderType.alarm);
    expect(decoded.date, alarm.date);
    expect(decoded.time, isNull);
    expect(decoded.recurring, isTrue);
  });

  test('timer round-trips its duration and leaves date null', () {
    const ReminderItem timer = ReminderItem(
      title: 'Water the plants',
      subtitle: 'Monstera & herbs',
      type: ReminderType.timer,
      time: Duration(minutes: 25),
    );

    final ReminderItem decoded = ReminderItem.fromJson(timer.toJson());

    expect(decoded.type, ReminderType.timer);
    expect(decoded.time, const Duration(minutes: 25));
    expect(decoded.date, isNull);
    expect(decoded.recurring, isFalse);
  });

  test('the type is encoded by name', () {
    const ReminderItem timer = ReminderItem(
      title: '',
      subtitle: '',
      type: ReminderType.timer,
      time: Duration(seconds: 1),
    );
    expect(timer.toJson()['type'], 'timer');
  });

  test('a timer missing its duration is repaired, not thrown', () {
    final ReminderItem decoded = ReminderItem.fromJson(<String, dynamic>{
      'title': 'Broken',
      'subtitle': '',
      'type': 'timer',
      'time': null,
      'recurring': false,
    });

    expect(decoded.type, ReminderType.timer);
    expect(decoded.time, isNotNull);
    expect(decoded.date, isNull);
  });

  test('an alarm missing its date is repaired, not thrown', () {
    final ReminderItem decoded = ReminderItem.fromJson(<String, dynamic>{
      'title': 'Broken',
      'subtitle': '',
      'type': 'alarm',
      'date': null,
      'recurring': false,
    });

    expect(decoded.type, ReminderType.alarm);
    expect(decoded.date, isNotNull);
    expect(decoded.time, isNull);
  });

  test('an unknown type decodes as a repaired alarm', () {
    final ReminderItem decoded = ReminderItem.fromJson(<String, dynamic>{
      'title': 'Mystery',
      'subtitle': '',
      'type': 'wormhole',
      'recurring': false,
    });

    expect(decoded.type, ReminderType.alarm);
    expect(decoded.date, isNotNull);
  });
}
