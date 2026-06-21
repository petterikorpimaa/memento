// Pure tests for the wall-clock timer math used to seed and re-sync countdowns.

import 'package:flutter_test/flutter_test.dart';

import 'package:memento/utils/timer_math.dart';

void main() {
  test('remaining is the gap to the fire moment', () {
    final DateTime now = DateTime(2026, 6, 18, 12, 0, 0);
    final DateTime firesAt = DateTime(2026, 6, 18, 12, 10, 0);
    expect(TimerMath.remaining(firesAt, now), const Duration(minutes: 10));
  });

  test('remaining clamps to zero once the moment has passed', () {
    final DateTime now = DateTime(2026, 6, 18, 12, 5, 0);
    final DateTime firesAt = DateTime(2026, 6, 18, 12, 0, 0);
    expect(TimerMath.remaining(firesAt, now), Duration.zero);
  });

  test('remaining is zero exactly at the fire moment', () {
    final DateTime moment = DateTime(2026, 6, 18, 12);
    expect(TimerMath.remaining(moment, moment), Duration.zero);
  });
}
