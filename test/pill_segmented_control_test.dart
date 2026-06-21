// Unit tests for the controlled, pill-shaped segmented control: tapping a
// segment reports its value and slides the indicator; dragging the indicator
// scrubs it freely and, on release, snaps to (and reports) the nearest segment.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/widgets/pill_segmented_control.dart';

void main() {
  // Pumps the two-segment Alert/Timer control at a fixed width so drag
  // distances map predictably to segments, and exposes the live value via [ref].
  Future<void> pumpControl(WidgetTester tester, _ValueRef ref) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  return PillSegmentedControl<String>(
                    value: ref.value,
                    onChanged: (String next) =>
                        setState(() => ref.value = next),
                    segments: const <PillSegment<String>>[
                      PillSegment<String>(
                        value: 'alert',
                        label: 'Alert',
                        icon: Icons.alarm_rounded,
                      ),
                      PillSegment<String>(
                        value: 'timer',
                        label: 'Timer',
                        icon: Icons.timer_rounded,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double indicatorX(WidgetTester tester) {
    final Align align = tester.widget<Align>(
      find.byKey(PillSegmentedControl.indicatorKey),
    );
    return (align.alignment as Alignment).x;
  }

  testWidgets('reports taps and slides the indicator to the selection', (
    WidgetTester tester,
  ) async {
    final _ValueRef ref = _ValueRef('alert');
    await pumpControl(tester, ref);

    // Both options render; the indicator starts on the first (left) segment.
    expect(find.text('Alert'), findsOneWidget);
    expect(find.text('Timer'), findsOneWidget);
    expect(indicatorX(tester), -1);

    // Pick the second segment: the value is reported and the indicator slides
    // to the right.
    await tester.tap(find.text('Timer'));
    await tester.pumpAndSettle();
    expect(ref.value, 'timer');
    expect(indicatorX(tester), 1);

    // ...and back to the first.
    await tester.tap(find.text('Alert'));
    await tester.pumpAndSettle();
    expect(ref.value, 'alert');
    expect(indicatorX(tester), -1);

    // The whole segment slot is tappable, not just the centred label: a tap near
    // the top edge of the right (Timer) half — above the text — still selects it.
    final Rect rect = tester.getRect(find.byType(PillSegmentedControl<String>));
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.top + 7));
    await tester.pumpAndSettle();
    expect(ref.value, 'timer');
    expect(indicatorX(tester), 1);

    // ...and the gesture area reaches all the way down: a tap just above the
    // bottom edge of the left (Alert) half — below the text — still selects it.
    await tester.tapAt(Offset(rect.left + rect.width * 0.25, rect.bottom - 2));
    await tester.pumpAndSettle();
    expect(ref.value, 'alert');
    expect(indicatorX(tester), -1);
  });

  testWidgets(
    'dragging past the midpoint snaps to and reports the next segment',
    (WidgetTester tester) async {
      final _ValueRef ref = _ValueRef('alert');
      await pumpControl(tester, ref);
      expect(indicatorX(tester), -1);

      // Drag the indicator well past the halfway point toward Timer, then release.
      await tester.drag(
        find.byType(PillSegmentedControl<String>),
        const Offset(120, 0),
      );
      await tester.pumpAndSettle();

      expect(ref.value, 'timer');
      expect(indicatorX(tester), 1);
    },
  );

  testWidgets('a short drag snaps back to the original segment', (
    WidgetTester tester,
  ) async {
    final _ValueRef ref = _ValueRef('alert');
    await pumpControl(tester, ref);

    // A small nudge that does not cross the midpoint settles back on Alert.
    await tester.drag(
      find.byType(PillSegmentedControl<String>),
      const Offset(20, 0),
    );
    await tester.pumpAndSettle();

    expect(ref.value, 'alert');
    expect(indicatorX(tester), -1);
  });

  testWidgets('dragging back leftward snaps to and reports the first segment', (
    WidgetTester tester,
  ) async {
    final _ValueRef ref = _ValueRef('timer');
    await pumpControl(tester, ref);
    expect(indicatorX(tester), 1);

    await tester.drag(
      find.byType(PillSegmentedControl<String>),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();

    expect(ref.value, 'alert');
    expect(indicatorX(tester), -1);
  });

  testWidgets('mid-drag the indicator tracks the finger between segments', (
    WidgetTester tester,
  ) async {
    final _ValueRef ref = _ValueRef('alert');
    await pumpControl(tester, ref);

    // Press and move part-way without releasing: the indicator should sit
    // between the two slots (strictly inside the -1..1 range).
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(PillSegmentedControl<String>)),
    );
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    final double x = indicatorX(tester);
    expect(x, greaterThan(-1));
    expect(x, lessThan(1));

    // Value is only committed on release.
    expect(ref.value, 'alert');

    await gesture.up();
    await tester.pumpAndSettle();
  });
}

/// A tiny mutable holder so the pumped [StatefulBuilder] and the test share the
/// control's current value.
class _ValueRef {
  _ValueRef(this.value);
  String value;
}
