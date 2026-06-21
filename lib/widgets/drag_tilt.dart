import 'dart:math' show exp;
import 'dart:ui' show Offset;

/// Pure maths for the 3D tilt of a tile being dragged, split out so the
/// velocity → angle mapping and its smoothing can be unit-tested without
/// pumping a frame or running a ticker.
///
/// The tile dives in the drag direction: its leading edge tips away the way the
/// card is thrown. Direction comes from the unit velocity; intensity grows with
/// drag speed (clamped). Each axis has its own peak angle because the tile is
/// short and wide — equal angles would barely foreshorten the short top/bottom
/// edges, so vertical drags would look untilted.
class DragTilt {
  const DragTilt._();

  /// Peak lean (radians) around the X axis — vertical drags. Larger than [maxTiltY]
  /// so the short top/bottom edges foreshorten as visibly as the wide sides.
  static const double maxTiltX = 0.45;

  /// Peak lean (radians) around the Y axis — horizontal drags.
  static const double maxTiltY = 0.13;

  /// Drag speed (px/s) at which the tilt reaches its peak; faster is clamped.
  /// Low, so even a gentle drag clearly tilts.
  static const double speedForMaxTilt = 450;

  /// Below this speed (px/s) the tile is treated as still and eases back flat.
  static const double minSpeedForTilt = 4;

  /// Exponential smoothing time-constant (s) for the tilt — small enough to
  /// feel responsive, large enough that it eases rather than snaps.
  static const double tiltTau = 0.05;

  /// Per-axis target tilt (radians) for a drag [velocity] in px/s. The leading
  /// edge dives in the drag direction; the lean clamps to each axis's peak.
  /// Below [minSpeedForTilt] the tile is treated as still and the target is
  /// flat — (0, 0).
  static (double x, double y) target(Offset velocity) {
    final double speed = velocity.distance;
    if (speed <= minSpeedForTilt) return (0, 0);
    final double intensity =
        speed.clamp(0.0, speedForMaxTilt) / speedForMaxTilt;
    final double x = (velocity.dy / speed) * intensity * maxTiltX;
    final double y = -(velocity.dx / speed) * intensity * maxTiltY;
    return (x, y);
  }

  /// One exponential-smoothing step from [current] toward [target] over [dt]
  /// seconds, easing rather than snapping.
  static double smooth(double current, double target, double dt) {
    final double k = 1 - exp(-dt / tiltTau);
    return current + (target - current) * k;
  }
}
