// Unit tests for the pure drag-to-reorder geometry. The visual behaviour
// (lift, tilt, shuffle, settle) lives in the widget, but the index maths that
// decides where every tile sits is split out here so the easy-to-get-wrong
// off-by-ones are pinned down without pumping a frame.

import 'package:flutter_test/flutter_test.dart';

import 'package:memento/widgets/reorder_math.dart';

void main() {
  group('ReorderMath.visualSlotFor', () {
    // With four tiles, dragging one tile opens a gap at the insertion index;
    // the other three fill the remaining slots in their original order. The
    // helper reports where each *non-dragged* tile should sit.
    int slot(int displayIndex, int dragged, int insertion) =>
        ReorderMath.visualSlotFor(
          displayIndex: displayIndex,
          draggedIndex: dragged,
          insertionIndex: insertion,
        );

    test('hovering the home slot leaves every other tile put', () {
      // Drag tile 0, still hovering slot 0 -> 1,2,3 keep slots 1,2,3.
      expect(slot(1, 0, 0), 1);
      expect(slot(2, 0, 0), 2);
      expect(slot(3, 0, 0), 3);
    });

    test('dragging the top tile to the bottom slides the rest up', () {
      // Drag tile 0 to slot 3 -> 1,2,3 slide up into 0,1,2.
      expect(slot(1, 0, 3), 0);
      expect(slot(2, 0, 3), 1);
      expect(slot(3, 0, 3), 2);
    });

    test('dragging a middle tile to the top slides the rest down', () {
      // Drag tile 2 to slot 0 -> 0,1 slide down, 3 stays below.
      expect(slot(0, 2, 0), 1);
      expect(slot(1, 2, 0), 2);
      expect(slot(3, 2, 0), 3);
    });

    test('reordering never collides with the landing slot', () {
      // For any drag/insertion combo, the non-dragged tiles plus the dragged
      // tile's landing slot must cover 0..n-1 exactly once (a valid permutation
      // — no two tiles share a slot, none is skipped).
      const int n = 4;
      for (int dragged = 0; dragged < n; dragged++) {
        for (int insertion = 0; insertion < n; insertion++) {
          final Set<int> occupied = <int>{
            insertion,
          }; // the dragged tile lands here
          for (int di = 0; di < n; di++) {
            if (di == dragged) continue;
            final int s = slot(di, dragged, insertion);
            expect(
              occupied.add(s),
              isTrue,
              reason: 'slot $s reused for drag=$dragged insertion=$insertion',
            );
          }
          expect(occupied, <int>{0, 1, 2, 3});
        }
      }
    });
  });

  group('ReorderMath.insertionIndexForTop', () {
    const double topPadding = 6;
    const double extent = 94; // 78px tile + 16px gap

    int indexFor(double top, {int count = 4}) =>
        ReorderMath.insertionIndexForTop(
          top,
          topPadding: topPadding,
          extent: extent,
          count: count,
        );

    test('snaps to the slot the tile top is nearest', () {
      expect(indexFor(topPadding), 0);
      expect(indexFor(topPadding + extent), 1);
      expect(indexFor(topPadding + 2 * extent), 2);
    });

    test('crosses to the next slot past the half-way point', () {
      expect(indexFor(topPadding + extent * 0.49), 0);
      expect(indexFor(topPadding + extent * 0.51), 1);
    });

    test('clamps beyond either end into a valid slot', () {
      expect(indexFor(-1000), 0);
      expect(indexFor(10000), 3);
    });

    test('a single-item list has only slot 0', () {
      expect(indexFor(10000, count: 1), 0);
    });
  });
}
