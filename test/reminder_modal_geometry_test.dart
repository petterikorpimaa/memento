// Unit tests for the pure modal target-rect maths. The render-object
// measurement helpers (rectInViewport / viewportOrigin) are exercised by the
// widget tests that open the modal; the target-rect geometry — the scaled-out
// width and the top lift — is pinned down here without pumping a frame.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/widgets/reminder_modal_geometry.dart';
import 'package:memento/widgets/reminder_tile.dart';

void main() {
  group('ModalGeometry.targetRect', () {
    const BoxConstraints constraints = BoxConstraints(
      maxWidth: 400,
      maxHeight: 800,
    );
    const double hPadding = 20;
    const double topPadding = 6;
    const double bottomMargin = 16;
    const double bottomInset = 34;

    Rect target({double sourceHeight = 0}) => ModalGeometry.targetRect(
      constraints: constraints,
      sourceHeight: sourceHeight,
      hPadding: hPadding,
      topPadding: topPadding,
      bottomMargin: bottomMargin,
      bottomInset: bottomInset,
    );

    test('widens past the list width by the tile\'s "closer" scale, centred', () {
      final Rect rect = target();
      // List content width is maxWidth - 2*hPadding = 360; scaled by
      // expandedScale and centred on maxWidth/2 = 200.
      final double scaledHalfWidth =
          (constraints.maxWidth - 2 * hPadding) *
          ReminderTile.expandedScale /
          2;
      expect(rect.left, closeTo(200 - scaledHalfWidth, 1e-9));
      expect(rect.right, closeTo(200 + scaledHalfWidth, 1e-9));
      // The scaled width exceeds the plain list content width.
      expect(rect.width, greaterThan(constraints.maxWidth - 2 * hPadding));
    });

    test('subtracts the bottom margin and home-indicator inset', () {
      final Rect rect = target();
      expect(
        rect.bottom,
        closeTo(constraints.maxHeight - bottomMargin - bottomInset, 1e-9),
      );
    });

    test('zero source height means no top lift — top sits at the padding', () {
      expect(target(sourceHeight: 0).top, closeTo(topPadding, 1e-9));
    });

    test('a real source height raises the top by half the added scale', () {
      const double sourceHeight = 80;
      final Rect rect = target(sourceHeight: sourceHeight);
      final double expectedLift =
          (ReminderTile.expandedScale - 1) / 2 * sourceHeight;
      expect(rect.top, closeTo(topPadding - expectedLift, 1e-9));
      // Lifting raises the top edge above the list padding.
      expect(rect.top, lessThan(topPadding));
    });
  });
}
