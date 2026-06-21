import 'dart:math' show max, min;

/// Pure range logic for the paint-to-toggle / paint-to-delete sweep, split out
/// so the set maths can be unit-tested without pumping a widget or firing
/// haptics.
///
/// A sweep begins on a leading button (the bell or the delete toggle) and runs
/// the finger up or down the list. Every tile between the start tile and the one
/// under the finger takes the sweep's action ([add]); tiles the finger has since
/// retreated past are restored to their pre-gesture state ([preGestureSet]).
class PaintSweep {
  const PaintSweep({
    required this.startIndex,
    required this.add,
    required this.preGestureSet,
  });

  /// Display index the sweep started on.
  final int startIndex;

  /// Whether the sweep adds ids to the target set (true) or removes them
  /// (false). Decided by the start tile's state — pressing an "off" tile turns
  /// the range on, pressing an "on" tile turns it off.
  final bool add;

  /// The target set captured at gesture start. Tiles outside the swept range —
  /// including those the finger retreated past — are restored to this.
  final Set<int> preGestureSet;

  /// The target set after sweeping from [startIndex] to [currentIndex] over
  /// [order]. Ids in the inclusive index range take [add]; every other id keeps
  /// its [preGestureSet] membership.
  Set<int> applied({required int currentIndex, required List<int> order}) {
    final int lo = min(startIndex, currentIndex);
    final int hi = max(startIndex, currentIndex);
    final Set<int> next = Set<int>.from(preGestureSet);
    for (int i = lo; i <= hi; i++) {
      final int id = order[i];
      if (add) {
        next.add(id);
      } else {
        next.remove(id);
      }
    }
    return next;
  }
}
