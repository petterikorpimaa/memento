/// Shared transition / animation durations, so motion feels consistent across
/// the whole app. Prefer these over hand-written `Duration`s.
class AppDurations {
  const AppDurations._();

  /// Quick micro-interactions: toggles, colour changes, the bell and time chip.
  static const Duration fast = Duration(milliseconds: 200);

  /// Standard transitions: the bottom-nav indicator, the modal expand and the
  /// divider reveal.
  static const Duration normal = Duration(milliseconds: 300);

  /// Deliberate, large motions: the 3D "closer" expand and tilt.
  static const Duration slow = Duration(milliseconds: 450);
}
