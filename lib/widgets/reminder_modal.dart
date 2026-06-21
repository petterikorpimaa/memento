import 'package:flutter/cupertino.dart'
    show
        CupertinoDatePicker,
        CupertinoDatePickerMode,
        CupertinoPicker,
        CupertinoTheme,
        CupertinoThemeData;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../constants/app_durations.dart';
import '../l10n/app_strings.dart';
import '../l10n/locale_scope.dart';
import '../models/reminder_item.dart';
import 'glass.dart';
import 'pill_segmented_control.dart';
import 'reminder_tile.dart';

part 'reminder_modal_fields.dart';
part 'reminder_modal_date_time.dart';

/// The floating modal a reminder expands into once its "closer" animation has
/// finished.
///
/// It fills the list viewport's [Stack] (so it is pinned and never scrolls):
///  * the card morphs from [sourceRect] (the tapped tile's slot) to
///    [targetRect] (top of the list down to the bottom of the plus button),
///    driven by [expandAnimation];
///  * the original tile content stays pinned at the top of the card;
///  * once expanded, a horizontal divider grows from its centre outwards,
///    driven by [dividerAnimation].
///
/// Only the content section above the divider closes the modal (via
/// [onDismiss]); the bell within it stays interactive and toggles the
/// notification (via [onToggle]).
///
/// Below the divider sits the editable detail: title and description text
/// fields that fade and scale in once the modal has finished expanding (driven
/// by [fieldsAnimation]). Edits are reported up live via [onTitleChanged] /
/// [onSubtitleChanged].
class ReminderModalOverlay extends StatelessWidget {
  const ReminderModalOverlay({
    super.key,
    required this.item,
    required this.enabled,
    required this.sourceRect,
    required this.targetRect,
    required this.expandAnimation,
    required this.dividerAnimation,
    required this.fieldsAnimation,
    required this.onDismiss,
    required this.onToggle,
    required this.onTitleChanged,
    required this.onSubtitleChanged,
    required this.onTypeChanged,
    required this.onDateChanged,
    required this.onDurationChanged,
    required this.barrierRect,
    this.remaining,
    this.compact = false,
  });

  final ReminderItem item;
  final bool enabled;

  /// The region the tap barrier covers, in the same (global) coordinate space
  /// as [sourceRect] / [targetRect]. Limited to the list body so the header
  /// above it — its edit and settings buttons — stays interactive while the
  /// modal is open.
  final Rect barrierRect;

  /// Whether the source tile used the compact layout. Carried so the content
  /// row and its inset match the tile, keeping the expand hand-off continuous.
  final bool compact;

  /// Where the card starts (the tile's slot, in viewport coordinates).
  final Rect sourceRect;

  /// Where the card settles (the full modal area, in viewport coordinates).
  final Rect targetRect;

  /// 0 -> card sits at [sourceRect], 1 -> card fills [targetRect].
  final Animation<double> expandAnimation;

  /// 0 -> divider hidden, 1 -> divider spans the full content width.
  final Animation<double> dividerAnimation;

  /// 0 -> edit fields hidden (faded out, slightly shrunk), 1 -> fully shown.
  /// Driven only after the modal has finished expanding.
  final Animation<double> fieldsAnimation;

  /// Closes the modal. Wired to the content section above the divider.
  final VoidCallback onDismiss;

  /// Toggles the reminder's notification. Wired to the bell inside the content.
  final VoidCallback onToggle;

  /// Edits to the title / description fields, reported live so the parent can
  /// update the reminder.
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onSubtitleChanged;

  /// A new reminder type picked from the Alert / Timer segmented control.
  final ValueChanged<ReminderType> onTypeChanged;

  /// A new alarm date/time picked from the always-open date/time pickers. Only
  /// fires while the alarm pickers show, so it always describes an alarm.
  final ValueChanged<DateTime> onDateChanged;

  /// A new timer length picked from the always-open duration picker. Only fires
  /// while the timer picker shows, so it always describes a timer.
  final ValueChanged<Duration> onDurationChanged;

  /// The reminder's live countdown (for a timer), owned by the screen so the
  /// header preview continues from the list's value instead of resetting, holds
  /// still when the screen freezes it, and repaints just the chip on each tick.
  /// Null for alarms.
  final ValueListenable<Duration>? remaining;

  /// Inset of the card content from the card edge, matching the tile (compact
  /// and all) so the row keeps its exact position through the morph.
  double get _contentInset => ReminderTile.contentInset(compact);

  /// Gap between the content row and the divider beneath it.
  static const double _dividerGap = 16;

  static const Color _dividerColor = Color(0x1FFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          expandAnimation,
          dividerAnimation,
        ]),
        builder: (BuildContext context, Widget? child) {
          // Lerp the on-screen rect directly between the lifted tile (the slot
          // scaled by the "closer" factor about its centre) and the open
          // target. We used to lerp slot -> target and scale the card about its
          // centre, but that bowed the top edge upward mid-morph: the card's
          // height grows while the scale eases, so the centre-anchored top
          // dipped up and then settled. Lerping the final rects keeps the top
          // moving in a straight line.
          final Rect rect = Rect.lerp(
            _scaleAboutCentre(sourceRect, ReminderTile.expandedScale),
            targetRect,
            expandAnimation.value,
          )!;
          return Stack(
            children: <Widget>[
              // Body barrier: swallows taps over the list so it stays inert
              // behind the modal, but stops short of the header so its edit and
              // settings buttons remain tappable. Does NOT dismiss — only the
              // content section does.
              Positioned.fromRect(
                rect: barrierRect,
                child: const AbsorbPointer(),
              ),
              Positioned.fromRect(
                rect: rect,
                child: _card(rect.size, expandAnimation.value),
              ),
            ],
          );
        },
      ),
    );
  }

  /// [rect] scaled by [factor] about its centre.
  static Rect _scaleAboutCentre(Rect rect, double factor) => Rect.fromCenter(
    center: rect.center,
    width: rect.width * factor,
    height: rect.height * factor,
  );

  Widget _card(Size size, double progress) {
    // The row holds the tile's "closer" scale and its own width the whole time,
    // so the glass simply grows around it.
    const double closerScale = ReminderTile.expandedScale;
    // Frost only develops as the card settles. A `BackdropFilter` re-blurs
    // everything behind it every frame, and the card's area grows toward
    // full-screen across the morph — so blurring at full strength the whole way
    // is the open's biggest per-frame cost. Ramp the sigma with the (eased)
    // expand progress instead: ~no blur while the card is small and racing
    // outward, full [kGlassBlurSigma] once it lands (so the settled modal you
    // actually edit in looks identical). Over the app's near-flat background the
    // missing frost mid-flight is imperceptible — the same reason resting tiles
    // skip the filter entirely.
    final double blurSigma =
        kGlassBlurSigma * Curves.easeIn.transform(progress);
    return DecoratedBox(
      // Lift shadow matching the tile's, so nothing flickers at the hand-off.
      // It rides on this box; BlurStyle.outer hugs the shape's edge.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ReminderTile.glassRadius),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            blurStyle: BlurStyle.outer,
            color: Color(0x66000000),
            blurRadius: 26,
          ),
        ],
      ),
      // Opens at the fully-lightened shade (progress 1), continuing seamlessly
      // from the lifted tile, which hands off at that same shade. As the active
      // surface it frosts the list behind it (kGlassBlurSigma) and clips
      // overhanging content to the squircle while the card is still short during
      // the morph.
      child: GlassSurface(
        borderRadius: ReminderTile.glassRadius,
        tint: ReminderTile.glassTint(1),
        blurSigma: blurSigma,
        // Size the glass to the morphing rect so it fills the card; a bare Stack
        // of only positioned children would otherwise collapse to nothing.
        child: SizedBox.fromSize(
          size: size,
          // A Stack (not a Column) so the content can overhang the card while it
          // is still short during the morph and simply get clipped — no overflow.
          child: Stack(
            children: <Widget>[
              Positioned(
                top: _contentInset * closerScale,
                left: 0,
                right: 0,
                // Extend the hit-test box down to the card bottom. The content
                // is painted 6% larger (the tile's "closer" scale), but a
                // Transform's layout box stays unscaled — so the bottom of the
                // scaled content (e.g. the Alert/Timer control) would otherwise
                // overhang a dead, unhittable strip. Scaling a full-height Align
                // keeps the look identical while every control stays tappable.
                bottom: 0,
                child: Transform.scale(
                  scale: closerScale,
                  alignment: Alignment.topCenter,
                  // Pin the content to the top-centre at the tile's own
                  // (narrower) width. The [Align] loosens the parent's tight
                  // constraints (min 0) so the scroll view below can be the
                  // content's natural height when it fits — laid out exactly as
                  // the old overhang-and-clip did, pinned to the top while the
                  // card is still short during the morph — and only as tall as
                  // the card (so it scrolls) once the content overflows, e.g.
                  // when a date/time picker opens. That keeps the modal usable
                  // on short screens without changing the resting look.
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: sourceRect.width - 2 * _contentInset,
                      child: SingleChildScrollView(
                        // Clamping (not bouncing) physics so a modal whose
                        // content fits sits perfectly still: maxScrollExtent is
                        // 0, leaving nothing to scroll until content overflows.
                        physics: const ClampingScrollPhysics(),
                        // Don't clip at the viewport. The bell's glow sits at the
                        // content's top-left; this viewport hugs the content, so
                        // it would cut the glow tight on the top and left during
                        // the morph — unlike a resting tile, where only the glass
                        // squircle clips it (a little further out). The enclosing
                        // GlassSurface still clips everything to the card, so
                        // nothing escapes; the glow just reads the same as it
                        // does in the list.
                        clipBehavior: Clip.none,
                        // The content is painted [closerScale]× larger about its
                        // top, so its bottom overhangs the card by that fraction
                        // and the glass clips it. When the content overflows and
                        // scrolls, that would crop the last control (the
                        // date/time picker) at the very bottom — so reserve a
                        // matching scroll inset so it can always scroll fully
                        // clear of the clip.
                        padding: EdgeInsets.only(
                          bottom: (closerScale - 1) * size.height,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            // Only this section (everything above the divider)
                            // closes the modal. The bell keeps its own gesture,
                            // so it toggles instead.
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onDismiss,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  bottom: _dividerGap,
                                ),
                                child: ReminderTileContent(
                                  item: item,
                                  enabled: enabled,
                                  onBellTap: onToggle,
                                  compact: compact,
                                  chipRemaining: remaining,
                                ),
                              ),
                            ),
                            _divider(),
                            _ReminderEditFields(
                              item: item,
                              animation: fieldsAnimation,
                              onTitleChanged: onTitleChanged,
                              onSubtitleChanged: onSubtitleChanged,
                              onTypeChanged: onTypeChanged,
                              onDateChanged: onDateChanged,
                              onDurationChanged: onDurationChanged,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    // Scale a full-width line horizontally from its centre, so it grows out to
    // the left and right together.
    return Transform.scale(
      scaleX: dividerAnimation.value,
      child: Container(
        height: 1.5,
        decoration: BoxDecoration(
          color: _dividerColor,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}
