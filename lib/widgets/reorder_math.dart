/// Pure geometry for the drag-to-reorder interaction, split out so the tricky
/// index maths can be unit-tested without pumping a widget.
class ReorderMath {
  const ReorderMath._();

  /// Where a *non-dragged* tile should sit while another tile is being dragged.
  ///
  /// The dragged tile is lifted out of the flow, leaving the remaining tiles as
  /// a gap-free sequence; we then re-open a single gap at [insertionIndex] so
  /// the dragged tile has somewhere to land. [displayIndex] is the tile's
  /// position in the *original* (unchanged-during-drag) order.
  static int visualSlotFor({
    required int displayIndex,
    required int draggedIndex,
    required int insertionIndex,
  }) {
    // Index within the sequence of "other" tiles (dragged one removed).
    final int j = displayIndex < draggedIndex ? displayIndex : displayIndex - 1;
    // Re-open the gap: everything at/after the insertion point slides down one.
    return j < insertionIndex ? j : j + 1;
  }

  /// The slot the dragged tile is hovering over, derived from its current [top]
  /// in the list's content coordinates. Clamped to a valid slot.
  static int insertionIndexForTop(
    double top, {
    required double topPadding,
    required double extent,
    required int count,
  }) {
    if (count <= 1) return 0;
    final int raw = ((top - topPadding) / extent).round();
    return raw.clamp(0, count - 1);
  }
}
