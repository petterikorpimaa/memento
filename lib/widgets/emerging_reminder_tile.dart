import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../models/reminder_item.dart';
import 'add_reminder_tile.dart';
import 'glass.dart';
import 'reminder_tile.dart';

/// The trailing "add" button mid-transformation into a fresh reminder tile.
///
/// Plays the two opening stages of the add flow, driven by [animation] (0 -> 1):
///  1. **morph** — the dashed "+" circle grows from its 58px footprint into a
///     full-width glass tile while the "+" icon fades out;
///  2. **emerge** — the new reminder's content fades in inside that glass.
///
/// The end state (animation == 1) is built to be pixel-identical to a resting
/// [ReminderTile]: the same resting glass tint, edge rim and content padding,
/// and no backdrop blur. That lets the parent swap this for a real tile — which
/// then plays its own "closer" lean and hands off into the modal — without any
/// visible pop, and keeps the list's "no blurred glass at rest" performance
/// invariant intact.
class EmergingReminderTile extends StatelessWidget {
  const EmergingReminderTile({
    super.key,
    required this.animation,
    required this.item,
    required this.enabled,
    required this.height,
    required this.fullWidth,
    this.compact = false,
    this.showGlyph = true,
  });

  /// The 0 -> 1 add driver. Stage boundaries below carve it into the morph and
  /// the content fade.
  final Animation<double> animation;

  /// The reminder being born — its content is what fades in.
  final ReminderItem item;

  /// Whether the new reminder's notification is on (drives the bell/chip shade).
  final bool enabled;

  /// Resting row height (a measured tile's height); the glass grows to it.
  final double height;

  /// Resting row width (the tile slot's width); the glass grows to it.
  final double fullWidth;

  /// Whether the formed tile uses the compact layout, so the morph's final
  /// frame matches the resting [ReminderTile] it is swapped for.
  final bool compact;

  /// Whether to draw the dashed "+" glyph the glass grows over. True for the
  /// list's add row (whose resting affordance is that dashed circle); false for
  /// the empty state, whose "New reminder" pill is a different shape — there the
  /// glass simply grows and fades in, with no stray dashed circle.
  final bool showGlyph;

  /// The circle grows into the full tile over the first part of the timeline.
  static final Animatable<double> _morph = CurveTween(
    curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
  );

  /// The "+" fades out a touch faster, clearing the way for the glass.
  static final Animatable<double> _iconFade = CurveTween(
    curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
  );

  /// The reminder content fades in only once the glass has formed.
  static final Animatable<double> _contentFade = CurveTween(
    curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
  );

  /// Content inset from the glass edge, matched to [ReminderTile] (compact and
  /// all) so the row lands in the exact resting position once formed.
  EdgeInsets get _contentInset =>
      EdgeInsets.all(ReminderTile.contentInset(compact));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth,
      height: height,
      child: AnimatedBuilder(
        animation: animation,
        // The content is laid out once and reused every tick — only its opacity
        // wrapper rebuilds as it fades in.
        child: ReminderTileContent(
          item: item,
          enabled: enabled,
          onBellTap: _noop,
          compact: compact,
        ),
        builder: (BuildContext context, Widget? content) {
          final double t = animation.value;
          final double morph = _morph.transform(t);
          final double iconOpacity = 1 - _iconFade.transform(t);
          final double contentOpacity = _contentFade.transform(t);

          // The glass footprint grows from the 58px circle to the full tile;
          // its corner radius eases from a full circle to the tile squircle.
          final double w = lerpDouble(
            AddReminderTile.diameter,
            fullWidth,
            morph,
          )!;
          final double h = lerpDouble(AddReminderTile.diameter, height, morph)!;
          final double radius = lerpDouble(
            AddReminderTile.diameter / 2,
            ReminderTile.glassRadius,
            morph,
          )!;

          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // The growing glass tile, cross-dissolving in over the "+" circle.
              Opacity(
                opacity: morph,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: GlassSurface(
                    borderRadius: radius,
                    // Resting shade + cheap fake glass (no backdrop blur): this
                    // tile floats over the flat list background, and its final
                    // frame must match a resting [ReminderTile] exactly.
                    tint: ReminderTile.glassTint(0),
                    blurSigma: 0,
                    // Lay the content out at its full resting size regardless of
                    // the (smaller, mid-morph) glass, so it never reflows; the
                    // glass simply clips it to the squircle until it has grown.
                    child: OverflowBox(
                      minWidth: fullWidth,
                      maxWidth: fullWidth,
                      minHeight: height,
                      maxHeight: height,
                      alignment: Alignment.center,
                      child: Opacity(
                        opacity: contentOpacity,
                        child: Padding(padding: _contentInset, child: content),
                      ),
                    ),
                  ),
                ),
              ),
              // The dashed "+" circle, fading out as the glass takes over.
              if (showGlyph && iconOpacity > 0)
                Opacity(opacity: iconOpacity, child: const AddReminderGlyph()),
            ],
          );
        },
      ),
    );
  }

  static void _noop() {}
}
