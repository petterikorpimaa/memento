/// Pure helpers for the wall-clock timer model.
///
/// A running timer is anchored to an absolute fire moment, so its on-screen
/// countdown is *derived* from the clock rather than decremented frame by
/// frame. That makes it correct across dropped ticks, app sleep and restarts:
/// reopening the app simply recomputes the gap to [now].
class TimerMath {
  const TimerMath._();

  /// Time left until [firesAt], measured from [now], never negative. Returns
  /// [Duration.zero] once the moment has passed (the timer has fired).
  static Duration remaining(DateTime firesAt, DateTime now) {
    final Duration left = firesAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}
