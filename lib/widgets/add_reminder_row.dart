import 'package:flutter/material.dart';

import '../constants/app_durations.dart';
import 'add_reminder_tile.dart';

/// The reorderable list's trailing dashed "add reminder" row.
///
/// It isn't part of the order — never dragged, painted or reordered — it just
/// rides at the slot past the final reminder and slides up (via the wrapping
/// [AnimatedPositioned]) whenever a row above it is removed.
///
/// While a reminder is being added the morph "spends" the old add slot becoming
/// the new tile, so a fresh add button takes the slot below it: it is held
/// hidden through the morph and fades back in (the [Interval] on [addAnimation])
/// as the new tile forms, rather than visibly sliding past the morph.
///
/// In edit mode it fades out, scales down and stops taking taps while tiles are
/// marked for deletion, then fades back in on the way out. The slot stays
/// reserved, so the list doesn't reflow as it disappears and returns.
class AddReminderRow extends StatelessWidget {
  const AddReminderRow({
    super.key,
    required this.onAdd,
    required this.editing,
    required this.addingId,
    required this.addAnimation,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.duration,
    required this.curve,
  });

  final VoidCallback onAdd;
  final bool editing;
  final int? addingId;
  final Animation<double>? addAnimation;
  final double left;
  final double top;
  final double width;
  final double height;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    Widget addChild = AddReminderTile(onTap: onAdd);
    if (addingId != null && addAnimation != null) {
      addChild = AnimatedBuilder(
        animation: addAnimation!,
        builder: (BuildContext context, Widget? child) => Opacity(
          opacity: const Interval(
            0.7,
            1.0,
            curve: Curves.easeOut,
          ).transform(addAnimation!.value),
          child: child,
        ),
        child: addChild,
      );
    }
    addChild = IgnorePointer(
      ignoring: editing,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: editing ? 0.0 : 1.0),
        duration: AppDurations.normal,
        curve: Curves.easeOut,
        child: addChild,
        builder: (BuildContext context, double t, Widget? child) => Opacity(
          opacity: t,
          child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
        ),
      ),
    );
    return AnimatedPositioned(
      duration: duration,
      curve: curve,
      left: left,
      top: top,
      width: width,
      height: height,
      child: addChild,
    );
  }
}
