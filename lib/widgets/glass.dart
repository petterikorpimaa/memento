import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Self-contained "liquid glass" look, faked without any shader.
///
/// This stands in for the `liquid_glass_renderer` package, which was dropped
/// because its pre-release shader caused too many problems. We reproduce just
/// the parts that read as glass over this app's flat gradient background:
///  * a translucent [tint] fill, clipped to a rounded superellipse;
///  * a soft light rim along the top and bottom edges (see [GlassEdgePainter]);
///  * optionally, a backdrop [blurSigma] that frosts whatever is painted behind.
///
/// ## Performance invariant (read before changing [blurSigma] usage)
/// A `BackdropFilter` is the expensive part — running one per row makes a long
/// list janky. The load-bearing rule, unchanged from the shader days:
///  * **Resting** tiles pass `blurSigma == 0`, so no `BackdropFilter` is built
///    at all. Over the flat background a backdrop blur is invisible anyway, so
///    nothing is lost and the list scrolls cheaply.
///  * Only a surface that floats *over other content* — a tile that is actively
///    expanding, lifted or dragged, or the open modal — passes a positive
///    [blurSigma] to frost what it covers.
///  * After any interaction ends, every tile **must revert to `blurSigma == 0`.**
///    `test/glass_revert_test.dart` is the regression guard: it asserts zero
///    blurred surfaces at rest.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.borderRadius,
    required this.tint,
    required this.child,
    this.blurSigma = 0,
    this.edgeOpacity = kGlassEdgeOpacity,
  });

  /// Corner radius of the glass squircle.
  final double borderRadius;

  /// Translucent fill colour; its alpha is what reads as the glass "shade".
  final Color tint;

  /// Backdrop blur sigma. `0` (the default, for resting tiles) skips the
  /// [BackdropFilter] entirely so a long list stays cheap; an active/lifted
  /// tile or the modal passes a positive value to frost the content behind it.
  final double blurSigma;

  /// Opacity of the soft light rim drawn along the top and bottom edges.
  final double edgeOpacity;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ShapeBorderClipper clipper = ShapeBorderClipper(
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
    return ClipPath(
      clipper: clipper,
      child: Stack(
        // The single non-positioned child ([child]) sizes the stack; the tint,
        // backdrop blur and edge rim fill that size.
        fit: StackFit.passthrough,
        children: <Widget>[
          if (blurSigma > 0)
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: blurSigma,
                  sigmaY: blurSigma,
                  tileMode: TileMode.mirror,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          Positioned.fill(child: ColoredBox(color: tint)),
          child,
          // Rim painted last so it rides over the content's edge; ignores
          // pointers so it never steals taps meant for the row beneath it.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: GlassEdgePainter(
                  radius: borderRadius,
                  color: kGlassEdgeColor.withValues(alpha: edgeOpacity),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cool near-white used for the glass edge highlight.
const Color kGlassEdgeColor = Color(0xFFCFD8E4);

/// Default opacity of the edge highlight.
const double kGlassEdgeOpacity = 0.30;

/// Backdrop blur sigma used by active (lifted/expanding) tiles and the modal.
/// Matched to the old shader's `blur: 12` so the frost reads the same.
const double kGlassBlurSigma = 12;

/// Paints a thin light highlight along the top and bottom edges of a glass
/// squircle. It holds its full thickness across the flat edge and around the
/// rounded corners, then *narrows* to nothing exactly where the corner stops
/// curving and meets the vertical side — all at constant opacity (it does not
/// fade).
///
/// It traces the real squircle outline (the same shape the glass clips to) and
/// builds, for each edge, a filled ribbon from the outline inward. The ribbon's
/// thickness follows how strongly the outline faces up (top) or down (bottom):
/// full where the edge faces straight up/down, zero where it has turned to face
/// sideways — so the highlight wraps the corner and tapers off as the roundness
/// ends. Cheap, and repaints only when [color] or [radius] change, not while
/// scrolling.
class GlassEdgePainter extends CustomPainter {
  GlassEdgePainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  /// Peak thickness of the highlight where an edge faces straight up/down.
  static const double _peakThickness = 1.4;

  /// Spacing between outline samples.
  static const double _step = 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final Rect rect = Offset.zero & size;
    final Path outline = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
    ).getOuterPath(rect);
    final Offset center = rect.center;

    // Walk the outline, recording each point, its inward direction, and how much
    // it faces up vs down.
    final List<Offset> pos = <Offset>[];
    final List<Offset> inward = <Offset>[];
    final List<double> up = <double>[];
    final List<double> down = <double>[];
    for (final ui.PathMetric metric in outline.computeMetrics()) {
      for (double s = 0; s < metric.length; s += _step) {
        final ui.Tangent? t = metric.getTangentForOffset(s);
        if (t == null) continue;
        final Offset p = t.position;
        // Outward normal: perpendicular to the unit tangent, flipped to point
        // away from the centre.
        Offset normal = Offset(-t.vector.dy, t.vector.dx);
        final Offset toEdge = p - center;
        if (normal.dx * toEdge.dx + normal.dy * toEdge.dy < 0) {
          normal = -normal;
        }
        pos.add(p);
        inward.add(-normal);
        up.add((-normal.dy).clamp(0.0, 1.0));
        down.add(normal.dy.clamp(0.0, 1.0));
      }
    }

    final Paint paint = Paint()..color = color;
    _drawEdge(canvas, paint, pos, inward, up);
    _drawEdge(canvas, paint, pos, inward, down);
  }

  /// Fills the ribbon for one edge: the contiguous run of samples whose [face]
  /// is non-zero, offset inward by `face * _peakThickness`.
  void _drawEdge(
    Canvas canvas,
    Paint paint,
    List<Offset> pos,
    List<Offset> inward,
    List<double> face,
  ) {
    final int n = pos.length;
    if (n < 3) return;
    // Anchor the search at a sample that is not on this edge, so the run can't
    // be split across the start of the sample list.
    int anchor = -1;
    for (int i = 0; i < n; i++) {
      if (face[i] <= 0.001) {
        anchor = i;
        break;
      }
    }
    if (anchor == -1) return;
    final List<int> run = <int>[];
    bool started = false;
    for (int k = 1; k <= n; k++) {
      final int i = (anchor + k) % n;
      if (face[i] > 0.001) {
        run.add(i);
        started = true;
      } else if (started) {
        break;
      }
    }
    if (run.length < 2) return;

    final Path ribbon = Path()..moveTo(pos[run.first].dx, pos[run.first].dy);
    for (final int i in run) {
      ribbon.lineTo(pos[i].dx, pos[i].dy);
    }
    for (int k = run.length - 1; k >= 0; k--) {
      final int i = run[k];
      final Offset insidePoint =
          pos[i] + inward[i] * (_peakThickness * face[i]);
      ribbon.lineTo(insidePoint.dx, insidePoint.dy);
    }
    ribbon.close();
    canvas.drawPath(ribbon, paint);
  }

  @override
  bool shouldRepaint(GlassEdgePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
