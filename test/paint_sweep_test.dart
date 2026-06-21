// Unit tests for the pure paint-to-toggle / paint-to-delete range logic. The
// gesture wiring (haptics, hit-testing the row under the finger) lives in the
// widget; the set maths that decides which ids the sweep flips is split out
// here so the retreat-restores-the-tail behaviour is pinned down without
// pumping a frame.

import 'package:flutter_test/flutter_test.dart';

import 'package:memento/widgets/paint_sweep.dart';

void main() {
  group('PaintSweep.applied', () {
    // A simple display order whose ids differ from their indices, so a test
    // failure that confuses the two is visible.
    const List<int> order = <int>[3, 1, 4, 1 + 5, 9]; // [3, 1, 4, 6, 9]

    Set<int> sweep({
      required int start,
      required int current,
      required bool add,
      Set<int> pre = const <int>{},
    }) => PaintSweep(
      startIndex: start,
      add: add,
      preGestureSet: pre,
    ).applied(currentIndex: current, order: order);

    test('a forward sweep adds the inclusive range of ids', () {
      // Start at index 1, sweep down to index 3 -> ids at 1,2,3 = {1, 4, 6}.
      expect(sweep(start: 1, current: 3, add: true), <int>{1, 4, 6});
    });

    test('a backward sweep adds the same range regardless of direction', () {
      // Sweeping up from 3 to 1 covers the identical inclusive range.
      expect(sweep(start: 3, current: 1, add: true), <int>{1, 4, 6});
    });

    test('a single-tile sweep touches only the start id', () {
      expect(sweep(start: 2, current: 2, add: true), <int>{4});
    });

    test('add: false removes the swept ids from the pre-gesture set', () {
      // Everything starts enabled; sweeping 0..2 turns those three off.
      expect(
        sweep(start: 0, current: 2, add: false, pre: <int>{3, 1, 4, 6, 9}),
        <int>{6, 9},
      );
    });

    test('retreating restores tiles the finger left behind', () {
      // Reach out to index 4 then pull back to index 2: only 0..2 stay flipped,
      // the tiles at 3 and 4 are restored to their pre-gesture (absent) state.
      final PaintSweep gesture = PaintSweep(
        startIndex: 0,
        add: true,
        preGestureSet: const <int>{},
      );
      expect(gesture.applied(currentIndex: 4, order: order), <int>{
        3,
        1,
        4,
        6,
        9,
      });
      expect(gesture.applied(currentIndex: 2, order: order), <int>{3, 1, 4});
    });

    test('ids outside the range keep their pre-gesture membership', () {
      // id 9 (index 4) is enabled before the gesture and lies outside the swept
      // 0..2 range, so it stays on even though the sweep adds.
      expect(sweep(start: 0, current: 2, add: true, pre: <int>{9}), <int>{
        3,
        1,
        4,
        9,
      });
    });

    test('does not mutate the supplied pre-gesture set', () {
      final Set<int> pre = <int>{9};
      sweep(start: 0, current: 2, add: true, pre: pre);
      expect(pre, <int>{9});
    });
  });
}
