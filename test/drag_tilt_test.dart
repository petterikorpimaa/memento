// Unit tests for the pure drag-tilt maths. The visual lean lives in the widget,
// but the velocity → angle mapping and its exponential smoothing are split out
// here so the direction signs, clamping and easing are pinned down without
// pumping a frame.

import 'package:flutter_test/flutter_test.dart';

import 'package:memento/widgets/drag_tilt.dart';

void main() {
  group('DragTilt.target', () {
    test('a still (sub-threshold) drag stays flat', () {
      expect(DragTilt.target(Offset.zero), (0.0, 0.0));
      // Just below the still threshold still reads as flat.
      expect(
        DragTilt.target(const Offset(DragTilt.minSpeedForTilt - 1, 0)),
        (0.0, 0.0),
      );
    });

    test('dragging down tips the leading (bottom) edge away: +X tilt', () {
      final (double x, double y) = DragTilt.target(
        const Offset(0, DragTilt.speedForMaxTilt),
      );
      expect(x, closeTo(DragTilt.maxTiltX, 1e-9));
      expect(y, closeTo(0, 1e-9));
    });

    test('dragging up gives the opposite X sign', () {
      final (double x, _) = DragTilt.target(
        const Offset(0, -DragTilt.speedForMaxTilt),
      );
      expect(x, closeTo(-DragTilt.maxTiltX, 1e-9));
    });

    test('dragging right leans -Y; left leans +Y', () {
      final (_, double right) = DragTilt.target(
        const Offset(DragTilt.speedForMaxTilt, 0),
      );
      final (_, double left) = DragTilt.target(
        const Offset(-DragTilt.speedForMaxTilt, 0),
      );
      expect(right, closeTo(-DragTilt.maxTiltY, 1e-9));
      expect(left, closeTo(DragTilt.maxTiltY, 1e-9));
    });

    test('speed past the peak is clamped to the max angle', () {
      final (double x, _) = DragTilt.target(
        const Offset(0, DragTilt.speedForMaxTilt * 10),
      );
      expect(x, closeTo(DragTilt.maxTiltX, 1e-9));
    });

    test('intensity scales linearly with speed below the peak', () {
      final (double x, _) = DragTilt.target(
        const Offset(0, DragTilt.speedForMaxTilt / 2),
      );
      expect(x, closeTo(DragTilt.maxTiltX / 2, 1e-9));
    });
  });

  group('DragTilt.smooth', () {
    test('eases toward the target without overshooting', () {
      const double target = 0.4;
      double current = 0;
      double prevGap = target;
      for (int i = 0; i < 20; i++) {
        current = DragTilt.smooth(current, target, 1 / 60);
        final double gap = target - current;
        // Monotonic approach: never past the target, gap always shrinks.
        expect(current, lessThanOrEqualTo(target));
        expect(gap, lessThan(prevGap));
        prevGap = gap;
      }
      expect(current, closeTo(target, 0.05));
    });

    test('a longer step moves further toward the target', () {
      final double small = DragTilt.smooth(0, 1, 1 / 120);
      final double large = DragTilt.smooth(0, 1, 1 / 30);
      expect(large, greaterThan(small));
    });

    test('eases back toward flat from a leaned angle', () {
      final double next = DragTilt.smooth(0.4, 0, 1 / 60);
      expect(next, lessThan(0.4));
      expect(next, greaterThan(0));
    });
  });
}
