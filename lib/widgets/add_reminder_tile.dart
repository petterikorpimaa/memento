import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The list's trailing "add reminder" affordance: a dotted circle centred in
/// the row, with a "+" icon in the same muted colour as the border.
///
/// Where the other rows are solid, full-width glass, this one is just an empty
/// circular outline — a transparent fill inside a dotted ring — so it reads as
/// a placeholder inviting a new reminder rather than as content. Only the
/// circle is tappable; tapping it calls [onTap].
class AddReminderTile extends StatelessWidget {
  const AddReminderTile({super.key, required this.onTap});

  /// Tapped to add a reminder: the button morphs into a fresh reminder tile
  /// that floats up into the modal (see `EmergingReminderTile`).
  final VoidCallback onTap;

  /// Diameter of the circular button — matched to the tile's leading bell /
  /// delete button (58) so it rhymes with them, and used by the add morph as
  /// the size the glass tile grows out from.
  static const double diameter = 58;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const AddReminderGlyph(),
      ),
    );
  }
}

/// The dotted circle enclosing a "+" — the visual of the add affordance, shared
/// by the resting [AddReminderTile] and the morphing `EmergingReminderTile`
/// (which fades it out as the glass tile grows in).
class AddReminderGlyph extends StatelessWidget {
  const AddReminderGlyph({super.key});

  /// Muted slate shared by the border and the icon — matches the inactive
  /// bell's grey so the affordance reads as quiet/secondary.
  static const Color _outline = Color(0xFF8A93A0);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedCirclePainter(
        color: _outline,
        strokeWidth: 1,
        dashLength: 2,
        gapLength: 5,
      ),
      child: const SizedBox.square(
        dimension: AddReminderTile.diameter,
        child: Icon(Icons.add_rounded, color: _outline, size: 30),
      ),
    );
  }
}

/// Strokes a dotted circle inscribed in the paint bounds.
///
/// Walks the ring with [ui.PathMetric] and draws a short dash, skips a gap, and
/// repeats around the perimeter (a round [StrokeCap] turns short dashes into
/// dots). Repaints only when its inputs change, never while scrolling.
class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  @override
  void paint(Canvas canvas, Size size) {
    // Inset by half the stroke on each side so the ring sits fully inside the
    // bounds rather than being clipped.
    final double radius = (size.shortestSide - strokeWidth) / 2;
    if (radius <= 0) return;
    final Path ring = Path()
      ..addOval(
        Rect.fromCircle(center: size.center(Offset.zero), radius: radius),
      );

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (final ui.PathMetric metric in ring.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double end = (distance + dashLength).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashLength != dashLength ||
      oldDelegate.gapLength != gapLength;
}
