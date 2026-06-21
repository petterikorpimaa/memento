import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/reminder_item.dart';
import 'reminder_tile.dart';

/// One reminder row: a [ReminderTile] wrapped in the gesture handling and the
/// lift/tilt machinery the reorder interaction needs.
///
/// The gesture + tile subtree is structurally identical for every tile and
/// every drag state, so the long-press recogniser survives the transition into
/// (and out of) the lifted state. The tile content is passed as
/// [AnimatedBuilder]'s `child` so it is not rebuilt on every lift tick.
///
/// The [RepaintBoundary] carries [tileKey]: it both isolates repaints and —
/// sitting on the tile's outermost (untransformed) box — lets the parent
/// snapshot the tile for the disintegration effect and measure its slot for the
/// modal hand-off. `ReorderableReminderList` keeps the wrapping
/// [AnimatedPositioned] (and its `reorder-tile-$id` key) so this widget's
/// subtree stays a stable, keyed slot.
class DraggableReminderTile extends StatelessWidget {
  const DraggableReminderTile({
    super.key,
    required this.item,
    required this.enabled,
    required this.expanded,
    required this.editing,
    required this.marked,
    required this.hidden,
    required this.dissolving,
    required this.compact,
    required this.chipRemaining,
    required this.active,
    required this.lift,
    required this.tiltX,
    required this.tiltY,
    required this.tileKey,
    required this.dragEnabled,
    required this.onToggle,
    required this.onExpandTap,
    required this.onExpandComplete,
    required this.onDeleteTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onPaintStart,
    required this.onPaintUpdate,
    required this.onPaintEnd,
  });

  /// Perspective of the 3D drag tilt.
  static const double _perspective = 0.0035;

  /// How far the lifted tile scales up — matched to the tile's own "closer"
  /// scale so the visual language is consistent.
  static const double _liftScale = ReminderTile.expandedScale;

  final ReminderItem item;
  final bool enabled;
  final bool expanded;
  final bool editing;
  final bool marked;
  final bool hidden;
  final bool dissolving;
  final bool compact;
  final ValueListenable<Duration>? chipRemaining;

  /// Whether this tile is the one being dragged or settling into place — it
  /// lifts, tilts and paints above its neighbours.
  final bool active;

  /// Drives the lift up / ease back down. Listened to every frame; its value is
  /// only applied while [active].
  final Animation<double> lift;
  final double tiltX;
  final double tiltY;

  /// Outermost (untransformed) key, used for the modal hand-off measurement and
  /// the disintegration snapshot.
  final Key tileKey;

  /// Whether a long press may start a drag (suspended while a modal is open or
  /// in edit mode, where the delete button drags instead).
  final bool dragEnabled;

  final VoidCallback onToggle;
  final VoidCallback onExpandTap;
  final VoidCallback onExpandComplete;
  final VoidCallback onDeleteTap;
  final void Function(LongPressStartDetails) onDragStart;
  final void Function(LongPressMoveUpdateDetails) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;
  final void Function(Offset) onPaintStart;
  final void Function(Offset) onPaintUpdate;
  final VoidCallback onPaintEnd;

  @override
  Widget build(BuildContext context) {
    final Widget content = RepaintBoundary(
      key: tileKey,
      child: Visibility(
        visible: !hidden && !dissolving,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Reorder long-press is suspended whenever dragging is disabled (a
          // modal open, or edit mode) — in edit mode the delete button drags.
          onLongPressStart: dragEnabled ? onDragStart : null,
          onLongPressMoveUpdate: dragEnabled ? onDragUpdate : null,
          onLongPressEnd: dragEnabled
              ? (LongPressEndDetails d) => onDragEnd()
              : null,
          // A cancelled long press (OS interruption, the parent scrollable
          // taking over, app backgrounding) never fires onLongPressEnd, so
          // clean the drag up here too or the tile stays stuck lifted on the
          // real shader. Harmless if no drag had started.
          onLongPressCancel: dragEnabled ? onDragCancel : null,
          child: ReminderTile(
            item: item,
            enabled: enabled,
            expanded: expanded,
            onToggle: onToggle,
            onExpandTap: onExpandTap,
            onExpandComplete: onExpandComplete,
            // Lifts the glass to the modal's active shade while dragging/landing.
            liftAnimation: active ? lift : null,
            editing: editing,
            markedForDeletion: marked,
            onDeleteTap: onDeleteTap,
            // Press-and-drag on the bell or the delete button paints the same
            // toggle across the list (enabled when resting, marked in edit mode).
            onPaintStart: onPaintStart,
            onPaintUpdate: onPaintUpdate,
            onPaintEnd: onPaintEnd,
            compact: compact,
            chipRemaining: chipRemaining,
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: lift,
      builder: (BuildContext context, Widget? child) {
        final double liftValue = active ? lift.value : 0.0;
        final double scale = 1 + (_liftScale - 1) * liftValue;
        final double tx = active ? tiltX : 0.0;
        final double ty = active ? tiltY : 0.0;
        final Matrix4 transform = Matrix4.identity()
          ..setEntry(3, 2, _perspective)
          ..rotateX(tx)
          ..rotateY(ty)
          ..scaleByDouble(scale, scale, scale, 1);
        return Transform(
          alignment: Alignment.center,
          transform: transform,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ReminderTile.glassRadius),
              // No offset: BlurStyle.outer clips the shadow to the ring outside
              // the shape, so an offset would detach that ring and leave a gap
              // under the (translucent) glass. The lift reads through the
              // scale-up and a deeper blur instead.
              boxShadow: liftValue > 0
                  ? <BoxShadow>[
                      BoxShadow(
                        blurStyle: BlurStyle.outer,
                        color: Colors.black.withValues(alpha: 0.55 * liftValue),
                        blurRadius: 34 * liftValue,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        );
      },
      child: content,
    );
  }
}
