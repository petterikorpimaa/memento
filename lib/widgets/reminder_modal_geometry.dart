import 'package:flutter/widgets.dart';

import 'reminder_tile.dart';

/// Pure geometry for the expand-into-modal hand-off, split out of
/// `RemindersScreen` so the target-rect maths can be unit-tested without
/// pumping a frame. The render-object measurement helpers live here too so all
/// the modal's coordinate work sits in one place.
class ModalGeometry {
  const ModalGeometry._();

  /// The rect the modal expands into, in the list viewport's coordinates.
  ///
  /// The modal fills from [topPadding] down to [bottomMargin] above the body
  /// bottom (less the [bottomInset] home-indicator gap). Horizontally it keeps
  /// the tile's "closer" width — [ReminderTile.expandedScale], pushed out toward
  /// the screen edges and centred — instead of snapping back to the list width.
  /// The tile scales up from its centre, so its top edge lifts above the list
  /// top by half the added height; the target top is raised by that same lift so
  /// the modal settles at the lifted tile's top rather than the list top.
  /// [sourceHeight] is 0 when no modal is open, so the lift is 0 too.
  static Rect targetRect({
    required BoxConstraints constraints,
    required double sourceHeight,
    required double hPadding,
    required double topPadding,
    required double bottomMargin,
    required double bottomInset,
  }) {
    final double scaledHalfWidth =
        (constraints.maxWidth - 2 * hPadding) * ReminderTile.expandedScale / 2;
    final double centerX = constraints.maxWidth / 2;
    final double topLift = (ReminderTile.expandedScale - 1) / 2 * sourceHeight;
    return Rect.fromLTRB(
      centerX - scaledHalfWidth,
      topPadding - topLift,
      centerX + scaledHalfWidth,
      constraints.maxHeight - bottomMargin - bottomInset,
    );
  }

  /// The rect of whatever [key] sits on, expressed in [viewportKey]'s
  /// coordinates (null if either is unattached). Used for list tiles (the modal
  /// hand-off) and the empty state's add-origin tile. The key sits on the tile's
  /// outermost box, so this is the unscaled slot — the tile's internal "closer"
  /// scale does not skew it.
  static Rect? rectInViewport(GlobalKey key, GlobalKey viewportKey) {
    final BuildContext? tileContext = key.currentContext;
    final BuildContext? viewportContext = viewportKey.currentContext;
    if (tileContext == null || viewportContext == null) return null;

    final RenderBox tileBox = tileContext.findRenderObject()! as RenderBox;
    final RenderBox viewportBox =
        viewportContext.findRenderObject()! as RenderBox;
    if (!tileBox.attached || !viewportBox.attached) return null;

    final Offset topLeft = viewportBox.globalToLocal(
      tileBox.localToGlobal(Offset.zero),
    );
    return topLeft & tileBox.size;
  }

  /// The list viewport's top-left in global (screen) coordinates. The modal is
  /// hosted in the full-screen app overlay, so the viewport-local source/target
  /// rects are shifted by this to land in the right place on screen.
  static Offset viewportOrigin(GlobalKey viewportKey) {
    final BuildContext? viewportContext = viewportKey.currentContext;
    final RenderObject? box = viewportContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return Offset.zero;
    return box.localToGlobal(Offset.zero);
  }
}
