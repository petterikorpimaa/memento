import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../constants/app_durations.dart';
import '../models/reminder_item.dart';
import 'glass.dart';
import 'reminder_chip.dart';

/// A single reminder row.
///
/// Two visual states, driven by [enabled]:
///  * off  — muted grey bell + greyed-out status chip (notification not set)
///  * on    — mode-coloured glowing bell + status chip on the right
///
/// Tapping the bell calls [onToggle]. Tapping anywhere else on the tile calls
/// [onExpandTap]; whether the tile is actually expanded is owned by the parent
/// (so only one tile is "closer" at a time) and fed back in via [expanded].
/// Expanding plays a 3D "lean toward the camera" animation: the bottom edge
/// tilts forward first, the top edge follows, and the card settles flat but
/// scaled up so it reads as having moved closer.
class ReminderTile extends StatefulWidget {
  const ReminderTile({
    super.key,
    required this.item,
    required this.enabled,
    required this.expanded,
    required this.onToggle,
    required this.onExpandTap,
    this.onExpandComplete,
    this.liftAnimation,
    this.editing = false,
    this.markedForDeletion = false,
    this.onDeleteTap,
    this.onPaintStart,
    this.onPaintUpdate,
    this.onPaintEnd,
    this.compact = false,
    this.chipRemaining,
  });

  final ReminderItem item;
  final bool enabled;

  /// Whether this tile is the one currently brought closer. Owned by the parent.
  final bool expanded;

  /// Called when the bell is tapped (toggles the notification).
  final VoidCallback onToggle;

  /// Called when the tile body (anywhere but the bell) is tapped.
  final VoidCallback onExpandTap;

  /// Called once the "closer" expand animation has fully played out, so the
  /// parent can hand off into the floating modal stage.
  final VoidCallback? onExpandComplete;

  /// While the tile is lifted for dragging, this 0->1 animation lightens its
  /// glass to the same "active" shade the modal opens at, so picking a tile up
  /// reads like the start of the same hand-off. Null when it is not lifted.
  final Animation<double>? liftAnimation;

  /// In edit mode the bell becomes a delete toggle (trash-can) button.
  final bool editing;

  /// Whether this tile is marked for deletion (delete button shown red, content
  /// dimmed). Only meaningful while [editing].
  final bool markedForDeletion;

  /// Tapping the delete button toggles this tile's marked state.
  final VoidCallback? onDeleteTap;

  /// Press-and-drag on the leading button paints its toggle across the list:
  /// the bell paints notification on/off, the delete button paints deletion.
  /// These forward the finger's global position so the list can map it to tiles
  /// and apply the action over the swept range.
  final ValueChanged<Offset>? onPaintStart;
  final ValueChanged<Offset>? onPaintUpdate;
  final VoidCallback? onPaintEnd;

  /// Compact layout: a smaller bell, no subtitle, and a tighter content inset,
  /// so the row sits shorter. Shared with the emerging tile and the modal the
  /// tile hands off into so the look stays continuous through every transition.
  final bool compact;

  /// Live countdown for a timer chip, owned by the screen and passed through to
  /// the row's [ReminderChip] so a tick repaints only the chip. Null for alarms.
  final ValueListenable<Duration>? chipRemaining;

  /// Glass tint shades, shared with the expanded modal so the tile and modal
  /// read as one continuous pane of glass through the hand-off:
  ///  * resting tiles use [glassTintResting] — a light, subtle slate so the
  ///    tiles read a touch brighter than the background;
  ///  * a tapped/lifted tile lerps toward [glassTintActive] — a darker smoked
  ///    shade — as it comes "closer", and the modal opens at that same darker
  ///    shade, so the focused surface reads as dark glass over the lighter list.
  /// The alpha channel is what reads as "shade": more opaque + dark = darker.
  static const Color glassTintResting = Color.fromARGB(82, 39, 45, 59);
  static const Color glassTintActive = Color.fromARGB(180, 21, 24, 33);

  /// Corner radius of the glass squircle, shared by tile and modal.
  static const double glassRadius = 22;

  /// The glass tint for a given 0->1 "closer" [progress]: it darkens from the
  /// resting (lighter) shade to the active (darker) shade as [progress] runs
  /// 0 -> 1. The tile drives this with its expand animation; the modal passes 1
  /// so it stays at the fully darkened shade.
  static Color glassTint(double progress) =>
      Color.lerp(glassTintResting, glassTintActive, progress)!;

  /// How much larger the card grows when brought "closer". Shared with the
  /// modal so it can start at the exact same scale (no jump at the hand-off).
  static const double expandedScale = 1.06;

  /// Inset of the content row from the glass edge. The compact layout tightens
  /// it so rows sit shorter. Shared (via this helper) with the emerging tile and
  /// the modal so the content lands in the exact same place through the morph.
  static double contentInset(bool compact) => compact ? 8 : 10;

  /// Edge-rim opacity for a tile marked for deletion. Dimmer than the resting
  /// [kGlassEdgeOpacity] so the lit border recedes, reading as a slightly darker
  /// edge — the tile fades out alongside its dimmed content.
  static const double markedEdgeOpacity = 0.12;

  static const Color _titleColor = Color(0xFFF4F6FA);
  static const Color _subtitleColor = Color(0xFF878F9C);
  static const Color _mutedBell = Color(0xFF8A93A0);

  @override
  State<ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<ReminderTile>
    with TickerProviderStateMixin {
  /// Strength of the perspective foreshortening; larger = more dramatic 3D.
  static const double _perspective = 0.0015;

  /// Peak lean of the bottom edge, in radians (~10°). Under this perspective a
  /// negative rotateX brings the bottom toward the camera (used when expanding);
  /// a positive one pushes it away (used when moving back).
  static const double _maxTilt = 0.18;

  /// Fraction of the tilt bump spent leaning out before the top catches up.
  static const double _tiltLeadFraction = 0.45;

  /// Drives expandedness: forward to expand, reverse to collapse.
  late final AnimationController _scaleController;

  /// Eased 0->1 expansion amount, drives scale and the lift shadow.
  late final Animation<double> _expand;

  /// One-shot 0->1 bump replayed on every tap; shapes the transient tilt.
  late final AnimationController _tiltController;

  /// Sign of the current tilt: -1 leans the bottom toward the camera while
  /// expanding, +1 pushes it away while moving back.
  double _tiltDirection = -1;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: AppDurations.normal,
      // Match the initial expansion without animating on first build.
      value: widget.expanded ? 1 : 0,
    );
    _expand = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutCubic,
    );
    _tiltController = AnimationController(
      vsync: this,
      duration: AppDurations.normal,
    );
    // Notify the parent only when the expand (forward) animation finishes, so
    // it can take over for the modal stage. Collapsing ends "dismissed", never
    // "completed", so this stays silent on the way back.
    _scaleController.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        widget.onExpandComplete?.call();
      }
    });
  }

  @override
  void didUpdateWidget(ReminderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded) {
      if (widget.expanded) {
        _tiltDirection = -1; // Expanding: bottom leans toward the camera first.
        _scaleController.forward();
      } else {
        _tiltDirection = 1; // Moving back: tilt reversed, bottom leans away.
        _scaleController.reverse();
      }
      // Replay the bump from the start so the bottom edge always leads.
      _tiltController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _tiltController.dispose();
    super.dispose();
  }

  /// Shapes the tilt over the bump's 0->1 progress: the bottom leads out over
  /// the first [_tiltLeadFraction], then the top follows and the card settles
  /// level (returns to 0) over the remainder.
  double _tiltBump(double p) {
    if (p <= _tiltLeadFraction) {
      return Curves.easeOut.transform(p / _tiltLeadFraction);
    }
    return 1 -
        Curves.easeInOut.transform(
          (p - _tiltLeadFraction) / (1 - _tiltLeadFraction),
        );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onExpandTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _scaleController,
          _tiltController,
          if (widget.liftAnimation != null) widget.liftAnimation!,
        ]),
        builder: (BuildContext context, Widget? child) {
          final double progress = _expand.value;
          // The drag lift drives the glass to the same active shade as the
          // expand "closer" stage; the scale/shadow stay on [progress] alone so
          // the lifted tile isn't double-scaled (its wrapper does the lift).
          final double lift = widget.liftAnimation?.value ?? 0;
          final double glassProgress = lift > progress ? lift : progress;
          // A backdrop blur is the expensive part — running one per row made
          // scrolling a long list janky, and a blur is invisible on a resting
          // tile over the flat background anyway. So a resting tile draws as
          // cheap "fake" glass (tint + edge rim, no BackdropFilter); only a tile
          // that is actively coming "closer", opening into the modal, or lifted
          // for a drag frosts what it floats over. The switch happens at
          // glassProgress == 0, where blurSigma is 0 either way, so no pop.
          final bool active = glassProgress > 0;
          final double scale = 1 + (ReminderTile.expandedScale - 1) * progress;
          final double tilt =
              _tiltDirection * _maxTilt * _tiltBump(_tiltController.value);
          final Matrix4 transform = Matrix4.identity()
            ..setEntry(3, 2, _perspective)
            ..rotateX(tilt)
            ..scaleByDouble(scale, scale, scale, 1);
          // Marking a tile for deletion dims its lit edge rim (a slightly darker
          // border) in step with the content fade. TweenAnimationBuilder eases
          // the rim between the resting and marked opacities so it doesn't pop;
          // its end value only changes when the marked state flips, so it stays
          // still during the expand/lift animations driving the outer builder.
          final Widget glass = TweenAnimationBuilder<double>(
            tween: Tween<double>(
              end: widget.markedForDeletion
                  ? ReminderTile.markedEdgeOpacity
                  : kGlassEdgeOpacity,
            ),
            duration: AppDurations.fast,
            curve: Curves.easeOut,
            child: Padding(
              padding: EdgeInsets.all(
                ReminderTile.contentInset(widget.compact),
              ),
              child: child,
            ),
            builder: (BuildContext context, double edgeOpacity, Widget? body) {
              return GlassSurface(
                borderRadius: ReminderTile.glassRadius,
                // Lightens as the tile comes closer or is lifted.
                tint: ReminderTile.glassTint(glassProgress),
                // Only the active surface frosts the content behind it.
                blurSigma: active ? kGlassBlurSigma : 0,
                edgeOpacity: edgeOpacity,
                child: body!,
              );
            },
          );
          return Transform(
            alignment: Alignment.center,
            transform: transform,
            child: DecoratedBox(
              // Lift shadow grows as the card moves closer. It rides on this
              // wrapping box; BlurStyle.outer keeps it hugging the shape's edge,
              // not bleeding under the translucent glass.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ReminderTile.glassRadius),
                boxShadow: progress > 0
                    ? <BoxShadow>[
                        BoxShadow(
                          blurStyle: BlurStyle.outer,
                          color: Colors.black.withValues(alpha: 0.4 * progress),
                          blurRadius: 26 * progress,
                        ),
                      ]
                    : null,
              ),
              child: glass,
            ),
          );
        },
        child: ReminderTileContent(
          item: widget.item,
          enabled: widget.enabled,
          onBellTap: widget.onToggle,
          editing: widget.editing,
          marked: widget.markedForDeletion,
          onDeleteTap: widget.onDeleteTap,
          onPaintStart: widget.onPaintStart,
          onPaintUpdate: widget.onPaintUpdate,
          onPaintEnd: widget.onPaintEnd,
          compact: widget.compact,
          chipRemaining: widget.chipRemaining,
        ),
      ),
    );
  }
}

/// The inner row shown inside a tile (and reused at the top of the expanded
/// modal): the bell on the left, title/subtitle in the middle, and the status
/// chip on the right. Kept presentational so both the tile and the modal render
/// it identically.
class ReminderTileContent extends StatelessWidget {
  const ReminderTileContent({
    super.key,
    required this.item,
    required this.enabled,
    required this.onBellTap,
    this.editing = false,
    this.marked = false,
    this.onDeleteTap,
    this.onPaintStart,
    this.onPaintUpdate,
    this.onPaintEnd,
    this.compact = false,
    this.chipRemaining,
  });

  final ReminderItem item;
  final bool enabled;
  final VoidCallback onBellTap;

  /// Compact layout: a smaller leading button and the subtitle hidden, so the
  /// row reads as a single tight line.
  final bool compact;

  /// Live countdown for a timer chip (see [ReminderChip.remaining]), owned by
  /// the screen. Null for alarms or when not supplied.
  final ValueListenable<Duration>? chipRemaining;

  /// In edit mode the bell becomes the trash-can delete toggle.
  final bool editing;
  final bool marked;
  final VoidCallback? onDeleteTap;

  /// Press-and-drag paint callbacks, shared by the bell (notification on/off)
  /// and the delete button. The list routes them to the right action by mode.
  final ValueChanged<Offset>? onPaintStart;
  final ValueChanged<Offset>? onPaintUpdate;
  final VoidCallback? onPaintEnd;

  /// Brighter-than-the-icon red used by the delete toggle when marked.
  static const Color _deleteRed = Color(0xFFFF5A5A);

  @override
  Widget build(BuildContext context) {
    // Bell and chip share the reminder's mode colour so the whole row reads in
    // one colour: teal (time today), blue (date) or pink (timer countdown).
    final Color modeColor = reminderModeColor(item);
    // The leading slot crossfades between the bell and the delete button when
    // edit mode toggles — both are the same paint-toggle button, differing only
    // in accent/icon/active state, so a tap or a press-drag behaves the same on
    // each. Distinct keys drive the AnimatedSwitcher transition.
    final Widget leading = AnimatedSwitcher(
      duration: AppDurations.fast,
      child: editing
          ? _PaintToggleButton(
              key: const ValueKey<String>('delete'),
              accent: _deleteRed,
              icon: Icons.delete_outline_rounded,
              active: marked,
              compact: compact,
              onTap: onDeleteTap ?? () {},
              onPaintStart: onPaintStart ?? (_) {},
              onPaintUpdate: onPaintUpdate ?? (_) {},
              onPaintEnd: onPaintEnd ?? () {},
            )
          : _PaintToggleButton(
              key: const ValueKey<String>('bell'),
              accent: modeColor,
              icon: Icons.notifications_none_rounded,
              active: enabled,
              compact: compact,
              onTap: onBellTap,
              onPaintStart: onPaintStart ?? (_) {},
              onPaintUpdate: onPaintUpdate ?? (_) {},
              onPaintEnd: onPaintEnd ?? () {},
            ),
    );
    // Marked tiles dim their content (but not the red delete button) to read
    // as "about to be removed".
    final double contentOpacity = marked ? 0.4 : 1.0;
    return Row(
      children: <Widget>[
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedOpacity(
            duration: AppDurations.fast,
            opacity: contentOpacity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ReminderTile._titleColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // The compact layout drops the subtitle so the row collapses to
                // a single line; an empty subtitle is dropped too, so the lone
                // title centres vertically (the Row centres its children) rather
                // than sitting above a blank line.
                if (!compact && item.subtitle.isNotEmpty)
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ReminderTile._subtitleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // The chip is always visible; it's greyed out while the notification is
        // switched off and mode-coloured once it's on. What it shows (time,
        // date or a live countdown) depends on the reminder's type and date.
        const SizedBox(width: 2),
        AnimatedOpacity(
          duration: AppDurations.fast,
          opacity: contentOpacity,
          child: ReminderChip(
            item: item,
            enabled: enabled,
            remaining: chipRemaining,
          ),
        ),
      ],
    );
  }
}

/// The rounded-square leading button on each tile. Used both as the bell
/// (notification on/off) and, in edit mode, as the trash-can delete toggle —
/// only [accent], [icon] and [active] differ.
///
/// A tap toggles just this tile ([onTap]); a vertical press-and-drag paints the
/// same toggle across the list — the start/update callbacks forward the
/// finger's global position so the list can apply it over the swept range. The
/// fill, glow and icon colour all ride one 0->1 "active" driver so they animate
/// on the exact same timeline.
///
/// The sweep uses a *vertical* drag recogniser (not a pan) on purpose: the list
/// scrolls vertically too, and a `VerticalDragGestureRecognizer` matches the
/// scrollable's own recogniser type and slop. Because this button sits deeper in
/// the hit-test tree, its recogniser is dispatched first and reliably wins the
/// arena tie, so a sweep that starts on the button paints instead of scrolling —
/// while a drag that starts anywhere else still scrolls the list. A pan
/// recogniser (larger slop) used to lose that race whenever the list overflowed,
/// which made painting unreliable.
class _PaintToggleButton extends StatelessWidget {
  const _PaintToggleButton({
    super.key,
    required this.accent,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.onPaintStart,
    required this.onPaintUpdate,
    required this.onPaintEnd,
    this.compact = false,
  });

  final Color accent;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<Offset> onPaintStart;
  final ValueChanged<Offset> onPaintUpdate;
  final VoidCallback onPaintEnd;

  /// Compact layout: a smaller footprint, corner radius and icon.
  final bool compact;

  /// Footprint of the button in the resting and compact layouts. The compact
  /// size also drives how short the row can sit, since the button is the
  /// tallest thing in it.
  static const double _size = 58;
  static const double _compactSize = 44;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onVerticalDragStart: (DragStartDetails d) =>
          onPaintStart(d.globalPosition),
      onVerticalDragUpdate: (DragUpdateDetails d) =>
          onPaintUpdate(d.globalPosition),
      onVerticalDragEnd: (DragEndDetails d) => onPaintEnd(),
      // A cancelled drag never fires onVerticalDragEnd, which would leave the
      // paint sweep flagged active; end it here too so the state can't get stuck.
      onVerticalDragCancel: onPaintEnd,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: active ? 1.0 : 0.0),
        duration: AppDurations.fast,
        curve: Curves.easeOut,
        builder: (BuildContext context, double t, Widget? child) {
          final Color fill = Color.lerp(
            accent.withValues(alpha: 0.05),
            accent.withValues(alpha: 0.18),
            t,
          )!;
          final Color iconColor = Color.lerp(
            ReminderTile._mutedBell,
            accent,
            t,
          )!;
          final double size = compact ? _compactSize : _size;
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(compact ? 14 : 18),
              boxShadow: t > 0
                  ? <BoxShadow>[
                      BoxShadow(
                        color: accent.withValues(alpha: 0.45 * t),
                        blurRadius: 22 * t,
                        spreadRadius: t,
                      ),
                    ]
                  : null,
            ),
            child: Icon(icon, size: compact ? 22 : 26, color: iconColor),
          );
        },
      ),
    );
  }
}
