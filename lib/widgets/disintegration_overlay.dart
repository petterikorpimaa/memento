import 'dart:math' show cos, pi, sin, sqrt;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;

/// The dissolve's particle budget, expressed in tiles. When more than this many
/// tiles dissolve at once, each one is rendered with proportionally fewer (but
/// larger) particles so the *total* particle count never exceeds what this many
/// tiles produce at full resolution — keeping a mass delete from melting the
/// frame rate.
const int _particleBudgetTiles = 3;

/// The linear multiplier to apply to the particle cell size when [simultaneous]
/// tiles dissolve together.
///
/// At or below the budget every tile renders at full resolution (1.0). Above
/// it, particle count per tile scales by `budget / simultaneous`, so the cell —
/// whose area is inversely proportional to that count — grows by the square
/// root. Six tiles, say, halve each tile's particle count (cell scaled by √2).
double _cellScaleFor(int simultaneous) {
  if (simultaneous <= _particleBudgetTiles) return 1.0;
  return sqrt(simultaneous / _particleBudgetTiles);
}

/// Captures the widget behind [boundaryKey] (which must sit on a
/// [RepaintBoundary]) and plays a "Thanos" disintegration of it as a transient
/// overlay: the snapshot crumbles into a grid of particles that drift up and
/// away, shrink and fade. The original widget is expected to be removed by the
/// caller right after — the snapshot starts exactly where it was, so the swap
/// is seamless.
///
/// [onReclaim] fires a little *before* the dissolve finishes so the caller can
/// drop the tile from the layout early — the remaining items then start sliding
/// up to fill the gap while the last of the dust is still settling, which reads
/// as smoother than waiting for the very end.
///
/// [simultaneous] is how many tiles are dissolving together in this batch; it
/// caps the total particle count at [_particleBudgetTiles] tiles' worth, so a
/// big multi-delete stays as cheap to render as a small one (see
/// [_cellScaleFor]).
///
/// Returns false (without scheduling anything) if the boundary can't be found
/// or captured — the caller should reclaim the slot itself in that case.
bool playDisintegration(
  BuildContext context,
  GlobalKey boundaryKey, {
  VoidCallback? onReclaim,
  int simultaneous = 1,
}) {
  final RenderObject? object = boundaryKey.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary || !object.attached) return false;

  final double pixelRatio = MediaQuery.devicePixelRatioOf(context);
  final ui.Image image;
  try {
    image = object.toImageSync(pixelRatio: pixelRatio);
  } catch (_) {
    // Some environments (e.g. certain test/headless setups) can't rasterise a
    // layer synchronously — skip the effect rather than crash.
    return false;
  }

  final Offset topLeft = object.localToGlobal(Offset.zero);
  final Size size = object.size;
  final OverlayState overlay = Overlay.of(context);

  late final OverlayEntry entry;
  bool tornDown = false;
  // Removes the overlay entry and releases the captured image. Idempotent, and
  // called from both the dissolve's completion and its disposal, so an
  // interrupted dissolve — its host overlay torn down mid-flight — can't strand
  // the entry or leak the GPU-backed image.
  void tearDown() {
    if (tornDown) return;
    tornDown = true;
    if (entry.mounted) entry.remove();
    // Defer disposal past this frame so no in-flight paint touches it.
    WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
  }

  entry = OverlayEntry(
    builder: (BuildContext context) => Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: size.width,
      height: size.height,
      child: DisintegrationOverlay(
        image: image,
        pixelRatio: pixelRatio,
        cellScale: _cellScaleFor(simultaneous),
        onReclaim: onReclaim,
        onDone: tearDown,
      ),
    ),
  );
  overlay.insert(entry);
  return true;
}

/// Plays the disintegration of [image] across the box it's given. [onReclaim]
/// fires once the dissolve passes [reclaimAt] (0..1) so the host can free the
/// slot early; [onDone] fires when the animation finishes so the host can tear
/// the overlay down.
class DisintegrationOverlay extends StatefulWidget {
  const DisintegrationOverlay({
    super.key,
    required this.image,
    required this.pixelRatio,
    required this.onDone,
    this.onReclaim,
    this.reclaimAt = 0.5,
    this.cellScale = 1.0,
  });

  final ui.Image image;
  final double pixelRatio;
  final VoidCallback onDone;
  final VoidCallback? onReclaim;
  final double reclaimAt;

  /// Linear multiplier on the particle cell size (>= 1). Larger means fewer,
  /// coarser particles; used to cap total particle count across a batch.
  final double cellScale;

  @override
  State<DisintegrationOverlay> createState() => _DisintegrationOverlayState();
}

class _DisintegrationOverlayState extends State<DisintegrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reclaimed = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 1200),
          )
          ..addListener(_maybeReclaim)
          ..addStatusListener(_onStatus);
    _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    // Tear down after this frame, not inside the status-notification dispatch:
    // onDone removes the overlay entry, which would unmount this widget while
    // the controller is still notifying its listeners.
    if (status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
    }
  }

  // Hand the slot back a touch before the end so the reflow overlaps the dust's
  // final fade rather than starting cold once it's fully gone.
  void _maybeReclaim() {
    if (!_reclaimed && _controller.value >= widget.reclaimAt) {
      _reclaimed = true;
      widget.onReclaim?.call();
    }
  }

  @override
  void dispose() {
    // If the dissolve is disposed before it finishes (its host overlay is torn
    // down mid-flight), the completion path never runs. Tear down here too so
    // the captured image and overlay entry are released; onDone is idempotent,
    // so a normal completion that already ran it makes this a no-op.
    widget.onDone();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) => CustomPaint(
          painter: _DustPainter(
            image: widget.image,
            t: _controller.value,
            pixelRatio: widget.pixelRatio,
            cellScale: widget.cellScale,
          ),
        ),
      ),
    );
  }
}

/// Paints the captured [image] as a grid of particles. Before the dissolve
/// "front" reaches a cell it draws in place at full opacity; once it passes,
/// the cell flies off in a random direction (every direction), shrinks and
/// fades over the remaining time. Per-cell randomness is hashed from the cell
/// coordinates so it's stable frame to frame.
class _DustPainter extends CustomPainter {
  _DustPainter({
    required this.image,
    required this.t,
    required this.pixelRatio,
    this.cellScale = 1.0,
  });

  /// 0 -> intact snapshot, 1 -> fully dispersed.
  final double t;
  final ui.Image image;
  final double pixelRatio;

  /// Multiplier on the base particle size; > 1 yields fewer, coarser particles.
  final double cellScale;

  /// Base particle size in logical pixels — kept tiny so the tile turns to fine
  /// dust. Scaled by [cellScale] to thin out particles in large batches.
  static const double _baseCell = 2.0;

  /// How far (logical px) a particle can travel from its origin.
  static const double _scatter = 110.0;

  /// How much of the timeline the dissolve front spends sweeping across the
  /// tile, and the extra per-cell randomness in when each starts.
  static const double _sweep = 0.45;
  static const double _jitter = 0.15;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final double cell = _baseCell * cellScale;
    final double cellPx = cell * pixelRatio;
    final int cols = (size.width / cell).ceil();
    final int rows = (size.height / cell).ceil();
    final double imgW = image.width.toDouble();
    final double imgH = image.height.toDouble();
    final double span = (1.0 - _sweep - _jitter).clamp(0.05, 1.0);
    final Paint paint = Paint()..filterQuality = FilterQuality.none;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final double sx = col * cellPx;
        final double sy = row * cellPx;
        if (sx >= imgW || sy >= imgH) continue;
        final double sw = (sx + cellPx <= imgW) ? cellPx : imgW - sx;
        final double sh = (sy + cellPx <= imgH) ? cellPx : imgH - sy;
        final Rect src = Rect.fromLTWH(sx, sy, sw, sh);

        final double dx = col * cell;
        final double dy = row * cell;
        final double dw = sw / pixelRatio;
        final double dh = sh / pixelRatio;

        // Dissolve front sweeps diagonally (top-left first); jitter softens it.
        final double front = (col / cols) * 0.6 + (row / rows) * 0.4;
        final double rnd = _hash(col, row);
        final double rnd2 = _hash(col + 101, row + 53);
        final double p = ((t - (front * _sweep + rnd * _jitter)) / span).clamp(
          0.0,
          1.0,
        );

        if (p <= 0.0) {
          paint.colorFilter = null;
          canvas.drawImageRect(
            image,
            src,
            Rect.fromLTWH(dx, dy, dw, dh),
            paint,
          );
          continue;
        }
        if (p >= 1.0) continue;

        // Scatter in every direction, shrinking and fading.
        final double angle = rnd * 2 * pi;
        final double dist = (_scatter * (0.4 + 0.6 * rnd2)) * p;
        final double cx = dx + dw / 2 + cos(angle) * dist;
        final double cy = dy + dh / 2 + sin(angle) * dist;
        final double scale = 1.0 - 0.6 * p;
        paint.colorFilter = ColorFilter.mode(
          Color.fromRGBO(255, 255, 255, 1.0 - p),
          BlendMode.modulate,
        );
        canvas.drawImageRect(
          image,
          src,
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: dw * scale,
            height: dh * scale,
          ),
          paint,
        );
      }
    }
  }

  /// Deterministic 0..1 value for a cell — the classic sin-based GLSL hash.
  double _hash(int a, int b) {
    final double s = sin(a * 12.9898 + b * 78.233) * 43758.5453;
    return s - s.floorToDouble();
  }

  @override
  bool shouldRepaint(_DustPainter old) =>
      old.t != t ||
      old.image != image ||
      old.pixelRatio != pixelRatio ||
      old.cellScale != cellScale;
}
