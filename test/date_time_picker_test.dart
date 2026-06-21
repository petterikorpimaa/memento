// Tests the modal's timing controls: Date/Time buttons (alarm) or a Duration
// button (timer) over an always-open picker. Behaviour under test:
//  * date/time use CupertinoDatePicker; the Time picker shows by default;
//  * the pickers can't be closed (re-tapping the active button is a no-op);
//  * tapping Date slides to the date picker (year floored to this year);
//  * picking Timer slides in the matching h/m/s duration picker;
//  * each picker has an anti-clockwise reset button; the timer resets to 5 min.

import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode, CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/l10n/app_locale.dart';
import 'package:memento/main.dart';
import 'package:memento/widgets/reminder_chip.dart';
import 'package:memento/widgets/reminder_modal.dart';

void main() {
  Future<void> openAlarm(WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning workout'));
    await tester.pumpAndSettle();
  }

  Future<void> openTimer(WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Water the plants'));
    await tester.pumpAndSettle();
  }

  Finder inModal(Finder matching) => find.descendant(
    of: find.byType(ReminderModalOverlay),
    matching: matching,
  );
  Finder dateButton() => inModal(find.byIcon(Icons.event_rounded));
  Finder timeButton() => inModal(find.byIcon(Icons.hourglass_empty_rounded));
  Finder timerButton() => inModal(find.byIcon(Icons.av_timer_rounded));
  Finder resetButtons() => inModal(find.byIcon(Icons.replay_rounded));

  // The single Cupertino date/time picker currently shown (date and time are
  // never mounted at once — one is always slid away).
  CupertinoDatePicker shownPicker(WidgetTester tester) => tester
      .widgetList<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
      .single;

  // The label on the modal header's status chip (above the divider). Reads from
  // the live reminder — time/date for an alarm, the shared countdown for a timer
  // — so it reflects what a picker has committed back to the reminder, unlike
  // the section's own button labels (which track local state regardless).
  String modalChipLabel(WidgetTester tester) {
    final Finder label = find.descendant(
      of: inModal(find.byType(ReminderChip)),
      matching: find.byType(Text),
    );
    return tester.widget<Text>(label).data!;
  }

  testWidgets('opens with the Time picker selected by default', (
    WidgetTester tester,
  ) async {
    await openAlarm(tester);

    expect(dateButton(), findsOneWidget);
    expect(timeButton(), findsOneWidget);

    // A Cupertino time picker is shown by default.
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(shownPicker(tester).mode, CupertinoDatePickerMode.time);
  });

  testWidgets('the Date button shows the date as d.M.yyyy', (
    WidgetTester tester,
  ) async {
    final DateTime now = DateTime.now();
    await openAlarm(tester);

    expect(
      inModal(find.text('${now.day}.${now.month}.${now.year}')),
      findsOneWidget,
    );
  });

  testWidgets('tapping Date slides to the date picker; year starts this year', (
    WidgetTester tester,
  ) async {
    await openAlarm(tester);

    await tester.tap(dateButton());
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(shownPicker(tester).mode, CupertinoDatePickerMode.date);
    expect(shownPicker(tester).minimumYear, DateTime.now().year);
  });

  testWidgets('the pickers cannot be closed', (WidgetTester tester) async {
    await openAlarm(tester);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);

    // Tapping the active (Time) button again does nothing — it stays open.
    await tester.tap(timeButton());
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(shownPicker(tester).mode, CupertinoDatePickerMode.time);
  });

  testWidgets('switching to Timer slides in the h/m/s duration picker', (
    WidgetTester tester,
  ) async {
    await openAlarm(tester);

    await tester.tap(find.text('Timer'));
    await tester.pumpAndSettle();

    // No date/time picker now; the timer's three wheels (h/m/s) are shown.
    expect(timerButton(), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsNothing);
    expect(find.byType(CupertinoPicker), findsNWidgets(3));
  });

  testWidgets('the open picker carries an anti-clockwise reset button', (
    WidgetTester tester,
  ) async {
    await openAlarm(tester);

    // Only the open (Time) picker is mounted, so exactly one reset button.
    expect(resetButtons(), findsOneWidget);
  });

  testWidgets('the timer reset returns the duration to 5 minutes', (
    WidgetTester tester,
  ) async {
    // 'Water the plants' is a 25-minute timer, so its Duration button reads
    // "25:00" (no hours -> no "0:" prefix).
    await openTimer(tester);
    expect(timerButton(), findsOneWidget);
    expect(inModal(find.text('25:00')), findsWidgets);

    // Reset returns the wheels to 0h 5m 0s, so the Duration button reads
    // "05:00" (the chip's countdown formats the same length as "5:00", so only
    // the button matches the padded label).
    await tester.tap(resetButtons());
    await tester.pumpAndSettle();
    expect(inModal(find.text('05:00')), findsOneWidget);
  });

  testWidgets('picking a timer length commits it to the reminder', (
    WidgetTester tester,
  ) async {
    await openTimer(tester);

    // Reset commits 5 minutes back to the reminder and freezes the preview, so
    // the header chip — which reads the live reminder countdown, not the
    // section's local button label — holds at the new length ("5:00", the
    // countdown's unpadded format). Before this committed, the chip kept ticking
    // down from 25 minutes regardless of the picker.
    await tester.tap(resetButtons());
    await tester.pumpAndSettle();
    expect(modalChipLabel(tester), '5:00');

    // It stuck on the reminder itself: dismiss and reopen, and the freshly
    // seeded Duration button reads the committed 5 minutes, not the old 25.
    await tester.tap(inModal(find.byType(ReminderChip)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Water the plants'));
    await tester.pumpAndSettle();
    expect(inModal(find.text('05:00')), findsOneWidget);
    expect(inModal(find.text('25:00')), findsNothing);
  });

  testWidgets('picking a date commits it to the reminder', (
    WidgetTester tester,
  ) async {
    // 'Call Mom' fires a week out at 19:00, so its chip shows a date (d.MM.),
    // not a time.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Call Mom'));
    await tester.pumpAndSettle();
    expect(modalChipLabel(tester), isNot('19:00'));

    // Reset the Date picker to today (it keeps the 19:00 time). That commits a
    // today-dated reminder, so the chip flips from a date to today's time —
    // proving the picked date reached the reminder, not just the button label.
    await tester.tap(dateButton());
    await tester.pumpAndSettle();
    await tester.tap(resetButtons());
    await tester.pumpAndSettle();
    expect(modalChipLabel(tester), '19:00');
  });

  testWidgets('the Time button sits to the left of the Date button', (
    WidgetTester tester,
  ) async {
    await openAlarm(tester);

    final double timeX = tester.getCenter(timeButton()).dx;
    final double dateX = tester.getCenter(dateButton()).dx;
    expect(timeX, lessThan(dateX));
  });

  testWidgets('the date picker uses Finnish month names in Finnish', (
    WidgetTester tester,
  ) async {
    const List<String> fiMonths = <String>[
      'tammikuu',
      'helmikuu',
      'maaliskuu',
      'huhtikuu',
      'toukokuu',
      'kesäkuu',
      'heinäkuu',
      'elokuu',
      'syyskuu',
      'lokakuu',
      'marraskuu',
      'joulukuu',
    ];
    const List<String> enMonths = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    await tester.pumpWidget(MyApp(initialLocale: AppLocale.finnish));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Morning workout'));
    await tester.pumpAndSettle();

    // Slide to the date picker (it shows month names; the time picker is digits).
    await tester.tap(dateButton());
    await tester.pumpAndSettle();
    expect(shownPicker(tester).mode, CupertinoDatePickerMode.date);

    Finder monthIn(String name) => find.descendant(
      of: find.byType(CupertinoDatePicker),
      matching: find.textContaining(name),
    );

    // At least one Finnish month is visible on the wheel, and no English one.
    expect(
      fiMonths.any((String m) => monthIn(m).evaluate().isNotEmpty),
      isTrue,
      reason: 'expected a Finnish month name in the date picker',
    );
    for (final String m in enMonths) {
      expect(monthIn(m), findsNothing);
    }
  });
}
