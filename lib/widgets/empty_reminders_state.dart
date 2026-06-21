import 'dart:math' show atan2, cos, pi, sin;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/locale_scope.dart';
import '../models/reminder_item.dart';
import 'glass.dart';
import 'reminder_tile.dart';

/// Shown in place of the list once every reminder has been cleared.
///
/// A slowly floating glass "bell" tile — with an occasional glint sweeping its
/// edge — sits above a headline, a short explainer, and a glass "New reminder"
/// pill that re-enters the same add flow as the list's trailing "+" row.
///
/// The headline is "Welcome" on a genuine first launch ([firstLaunch]) and
/// "All clear" once the user has created at least one reminder before.
///
/// The screen crossfades this in (via an [AnimatedSwitcher]) only while the list
/// is empty, so its continuous animations don't run — and aren't in the tree at
/// all — while reminders are present.
class EmptyRemindersState extends StatelessWidget {
  const EmptyRemindersState({
    super.key,
    required this.onAdd,
    required this.addSlotHeight,
    this.addingTile,
    this.firstLaunch = false,
  });

  /// Tapped the "New reminder" button — starts the same add flow the list's
  /// trailing "+" row does.
  final VoidCallback onAdd;

  /// Height reserved for the add affordance at the bottom of the block. The
  /// resting "New reminder" pill and the (taller) morphing add tile share this
  /// slot, so swapping one for the other never changes the column's height —
  /// which, under the centring [Align], would otherwise nudge the whole block
  /// upward the instant an add begins. Matched by the screen to the real
  /// reminder row height the morph grows into.
  final double addSlotHeight;

  /// While a reminder is being added from here, the morphing "+"-into-tile to
  /// show in place of the button — so the new reminder first appears right on
  /// top of the button before it floats up into the modal. Null otherwise.
  final Widget? addingTile;

  /// Whether this is a genuine first launch (the user has never created a
  /// reminder). Drives the headline: "Welcome" when true, "All clear" otherwise.
  final bool firstLaunch;

  /// Horizontal inset for the headline/explainer text only. The add-origin tile
  /// and button aren't inset by this — the morph is sized by the screen to a
  /// real reminder row's width so it matches a list add.
  static const double _textHPadding = 32;

  static const Color _titleColor = Color(0xFFF4F6FA);
  static const Color _subtitleColor = Color(0xFF8A929E);

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = LocaleScope.stringsOf(context);
    // Sit above centre so the block reads as anchored to the upper portion of
    // the (header-less) list area rather than floating dead-centre.
    return Align(
      alignment: const Alignment(0, -0.4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Freeze the bell's (relatively costly) float/glint loops while a
          // reminder is being added from here: the empty state is mid-crossfade
          // out and the user's focus is the morphing tile, so its per-frame path
          // work would only compete with the add choreography for frame budget.
          _FloatingBell(animating: addingTile == null),
          const SizedBox(height: 40),
          // Only the text is inset; the tile/button below span their own width.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _textHPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  firstLaunch
                      ? strings.welcomeHeadline
                      : strings.allClearHeadline,
                  style: const TextStyle(
                    color: _titleColor,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  strings.emptyRemindersBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _subtitleColor,
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Once tapped, the morphing tile takes the button's place so the new
          // reminder first appears right where the button was, at a real row's
          // width. The slot reserves the tile's full height (see [addSlotHeight])
          // so the swap doesn't grow the column and shift the block upward; the
          // pill centres within it, which is also where the morph grows from.
          SizedBox(
            height: addSlotHeight,
            child: Center(
              child: addingTile ?? _NewReminderButton(onTap: onAdd),
            ),
          ),
        ],
      ),
    );
  }
}

/// The floating glass bell tile.
///
/// Two looping animations run while this is mounted: a slow vertical bob (so it
/// reads as gently floating) and an occasional 3D "tilt-around" that rolls the
/// box and lights a glint on whichever edge reads as raised (see [_GlassBell]).
class _FloatingBell extends StatefulWidget {
  const _FloatingBell({this.animating = true});

  /// Whether the float/glint loops run. Set false while a reminder is being
  /// added from the empty state, so the bell holds still (and stops doing its
  /// per-frame path work) instead of competing with the add animation.
  final bool animating;

  @override
  State<_FloatingBell> createState() => _FloatingBellState();
}

class _FloatingBellState extends State<_FloatingBell>
    with TickerProviderStateMixin {
  /// Slow up/down bob of the glass tile.
  late final AnimationController _floatController;
  late final CurvedAnimation _float;

  /// Drives the occasional 3D tilt (and the glint riding its raised edge). Most
  /// of each cycle is an idle, flat pause, so the tilt fires only occasionally
  /// (see [_GlassBell]).
  late final AnimationController _tiltController;

  /// Peak vertical travel of the bob, in logical pixels.
  static const double _floatTravel = 7;

  /// Footprint of the glass tile.
  static const double _tileSize = 120;

  static const Color _accent = ReminderColors.teal;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _float = CurvedAnimation(parent: _floatController, curve: Curves.easeInOut);
    _tiltController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    );
    _applyAnimating();
  }

  @override
  void didUpdateWidget(_FloatingBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating != oldWidget.animating) _applyAnimating();
  }

  /// Starts or stops the looping animations to match [_FloatingBell.animating].
  /// When stopping, the tilt is reset to flat so the glint can't freeze lit
  /// mid-roll; the bob simply holds wherever it is (imperceptible behind the
  /// add).
  void _applyAnimating() {
    if (widget.animating) {
      if (!_floatController.isAnimating) _floatController.repeat(reverse: true);
      if (!_tiltController.isAnimating) _tiltController.repeat();
    } else {
      _floatController.stop();
      _tiltController.stop();
      _tiltController.value = 0;
    }
  }

  @override
  void dispose() {
    // Dispose the CurvedAnimation before its parent so it drops the status
    // listener it added to the controller.
    _float.dispose();
    _floatController.dispose();
    _tiltController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The bob only translates the tile, so it's the AnimatedBuilder's static
    // child — never rebuilt per frame; the inner tilt/glint layer does its own
    // per-frame work (see [_GlassBell]).
    return AnimatedBuilder(
      animation: _float,
      builder: (BuildContext context, Widget? child) => Transform.translate(
        offset: Offset(0, (_float.value * 2 - 1) * _floatTravel),
        child: child,
      ),
      child: _GlassBell(
        size: _tileSize,
        accent: _accent,
        tilt: _tiltController,
      ),
    );
  }
}

/// A rounded glass square holding the bell glyph, with a soft accent glow.
///
/// Occasionally it rolls in 3D: the box leans out, the lean direction orbits
/// once around, and the box settles back flat. A bright glint rides the edge
/// that the lean raises toward the camera throughout, so the highlight reads as
/// light catching the high side.
///
/// Uses a resting [GlassSurface] (no [BackdropFilter]) so it honours the list's
/// glass performance invariant: only actively interacting surfaces ever frost.
class _GlassBell extends StatelessWidget {
  const _GlassBell({
    required this.size,
    required this.accent,
    required this.tilt,
  });

  final double size;
  final Color accent;

  /// The raw tilt cycle (0..1, looping).
  final Animation<double> tilt;

  static const double _radius = 32;

  /// Fraction of the cycle spent tilting; the rest is an idle, flat pause.
  static const double _active = 0.4;

  /// Peak lean of the 3D roll (radians) and the perspective depth.
  static const double _maxTilt = 0.22;
  static const double _perspective = 0.002;

  @override
  Widget build(BuildContext context) {
    // Built once and reused: only the surrounding Transform and the glint layer
    // recompute per frame.
    final Widget box = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.16),
            blurRadius: 44,
            spreadRadius: 2,
          ),
        ],
      ),
      child: GlassSurface(
        borderRadius: _radius,
        // Reuse the tiles' resting tint so the box reads as the same glass.
        tint: ReminderTile.glassTintResting,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Icon(
              Icons.notifications_none_rounded,
              size: 56,
              color: accent,
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: tilt,
      builder: (BuildContext context, Widget? child) {
        final double cycle = tilt.value;
        final bool resting = cycle >= _active;
        // p: progress through the tilt (0..1). env: a 0->1->0 swell driving the
        // lean magnitude and glint brightness. progress: the glinted point's
        // eased trip once around the rim, starting/ending at the seam where env
        // is ~0 so the wrap there is invisible.
        final double p = resting ? 0 : cycle / _active;
        final double env = resting ? 0 : sin(pi * p);
        final double progress = Curves.easeInOut.transform(p);
        final double theta = env <= 0
            ? 0
            : _edgeAngleAt(progress, size, _radius);
        final double tiltMag = _maxTilt * env;
        // Lean so the glinted edge (screen direction theta) is the one raised
        // toward the camera; see the sign notes in [_edgeAngleAt].
        final Matrix4 transform = Matrix4.identity()
          ..setEntry(3, 2, _perspective)
          ..rotateX(-tiltMag * sin(theta))
          ..rotateY(tiltMag * cos(theta));
        return Transform(
          alignment: Alignment.center,
          transform: transform,
          child: Stack(
            // The glint rides the rim and may spill a hair past it — don't clip.
            clipBehavior: Clip.none,
            children: <Widget>[
              child!,
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _EdgeGlintPainter(
                      progress: progress,
                      intensity: env,
                      color: Colors.white,
                      radius: _radius,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: box,
    );
  }
}

/// The screen-space angle (from the box centre) of the point a fraction [t]
/// (0..1) of the way around a [side]-square glass outline with corner [radius].
///
/// Used to aim the 3D lean so the glinted edge is the one that reads as raised.
/// Screen y is down, so this returns 0 at the right edge, +π/2 at the bottom.
/// The lean in [_GlassBell] uses `rotateX(-mag·sinθ)` / `rotateY(mag·cosθ)`,
/// which — matching the reorder tile's tilt convention — raises the bottom edge
/// for a negative rotateX and the right edge for a positive rotateY, so the
/// raised side lands exactly on direction θ.
double _edgeAngleAt(double t, double side, double radius) {
  final Path outline = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(radius),
  ).getOuterPath(Rect.fromLTWH(0, 0, side, side));
  final double centre = side / 2;
  // computeMetrics() is a single-pass iterable, so take the first contour in a
  // plain loop (never .isEmpty/.first, which would consume it twice).
  for (final ui.PathMetric metric in outline.computeMetrics()) {
    final ui.Tangent? tangent = metric.getTangentForOffset(t * metric.length);
    if (tangent == null) break;
    return atan2(tangent.position.dy - centre, tangent.position.dx - centre);
  }
  return 0;
}

/// The "New reminder" button: a glass pill echoing the floating bell — the same
/// resting tint, edge rim and soft teal glow — with a teal "+" and a label
/// inside. Tapping it calls [onTap].
class _NewReminderButton extends StatelessWidget {
  const _NewReminderButton({required this.onTap});

  final VoidCallback onTap;

  static const Color _accent = ReminderColors.teal;
  static const Color _labelColor = Color(0xFFEAEEF4);

  /// Fixed height so the radius can make a true stadium (radius = height / 2).
  static const double _height = 52;
  static const double _radius = _height / 2;

  @override
  Widget build(BuildContext context) {
    final String label = LocaleScope.stringsOf(context).newReminder;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassSurface(
          borderRadius: _radius,
          tint: ReminderTile.glassTintResting,
          child: SizedBox(
            height: _height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.add_rounded, color: _accent, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: _labelColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a soft glint along the box's rounded edge.
///
/// Walks the same superellipse outline the glass clips to and lights a short run
/// of it centred on [progress] (0..1 around the perimeter), wrapping cleanly
/// across the path's seam. The run is split into segments whose opacity tapers
/// to nothing at both ends, and the whole glint is scaled by [intensity] (the
/// tilt's swell) so it fades in with the lean and out as it settles — reading as
/// a smooth catch of light rather than a hard dash.
class _EdgeGlintPainter extends CustomPainter {
  _EdgeGlintPainter({
    required this.progress,
    required this.intensity,
    required this.color,
    required this.radius,
  });

  /// Position of the glint around the perimeter (0..1).
  final double progress;

  /// Overall brightness (0..1), driven by the tilt swell.
  final double intensity;

  final Color color;
  final double radius;

  /// Length of the lit run as a fraction of the perimeter.
  static const double _glintFraction = 0.08;
  static const double _peakOpacity = 1;
  static const int _segments = 12;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.01 || progress <= 0 || progress >= 1) return;

    final Path outline = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
    ).getOuterPath(Offset.zero & size);

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);

    for (final ui.PathMetric metric in outline.computeMetrics()) {
      final double length = metric.length;
      final double glintLength = length * _glintFraction;
      final double centre = progress * length;
      for (int i = 0; i < _segments; i++) {
        final double a =
            centre - glintLength / 2 + glintLength * (i / _segments);
        final double b =
            centre - glintLength / 2 + glintLength * ((i + 1) / _segments);
        // Wrap into [0, length): the outline is a loop, so a sub-segment that
        // crosses the seam is simply skipped (≈one tiny gap, imperceptible).
        final double start = (a % length + length) % length;
        final double end = (b % length + length) % length;
        if (end - start < 0.3) continue;
        // Triangular taper: brightest at the run's centre, zero at its ends.
        final double mid = (i + 0.5) / _segments;
        final double taper = 1 - (mid - 0.5).abs() * 2;
        final double alpha = intensity * taper * _peakOpacity;
        if (alpha <= 0.01) continue;
        canvas.drawPath(
          metric.extractPath(start, end),
          paint..color = color.withValues(alpha: alpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_EdgeGlintPainter old) =>
      old.progress != progress ||
      old.intensity != intensity ||
      old.color != color ||
      old.radius != radius;
}
