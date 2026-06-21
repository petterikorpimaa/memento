// Tests for the "all clear" empty state: once every reminder is deleted, the
// list hands the screen over to a floating-bell empty state that carries its
// own "New reminder" add affordance.
//
// The empty state runs continuous float/pulse animations while it is on screen,
// so a `pumpAndSettle` would never settle with it visible — these tests drive it
// with bounded `pump`s instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/main.dart';
import 'package:memento/widgets/add_reminder_tile.dart';
import 'package:memento/widgets/emerging_reminder_tile.dart';
import 'package:memento/widgets/empty_reminders_state.dart';
import 'package:memento/widgets/glass.dart';
import 'package:memento/widgets/reminder_tile.dart';

/// Pumps fixed 50ms steps until [finder] matches or [maxFrames] elapse. Used in
/// place of `pumpAndSettle`, which never settles while the empty state's
/// continuous float/glint animations are on screen.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 80,
}) async {
  for (int i = 0; i < maxFrames && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Number of glass surfaces currently running an (expensive) backdrop blur.
int blurredGlassCount(WidgetTester tester) => tester
    .widgetList<GlassSurface>(find.byType(GlassSurface))
    .where((GlassSurface g) => g.blurSigma > 0)
    .length;

/// Deletes every reminder via edit mode and drives past the dissolve and the
/// empty-state crossfade with bounded pumps (the empty state never "settles").
Future<void> clearAllReminders(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Edit'));
  await tester.pumpAndSettle();

  // Mark every tile for deletion. The delete icon is the same whether or not a
  // tile is marked, so all the buttons stay findable as we tap each one.
  final int count = tester
      .widgetList(find.byIcon(Icons.delete_outline_rounded))
      .length;
  for (int i = 0; i < count; i++) {
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).at(i));
    await tester.pump();
  }

  // Commit via the confirm check that slides out once a tile is marked (let it
  // finish sliding so it's fully hittable), then drive the "Thanos" dissolve
  // (1200ms), the early slot reclaim, and the empty-state crossfade-in.
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Confirm'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('the empty state is absent while reminders are present', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byType(EmptyRemindersState), findsNothing);
    expect(find.text('All clear'), findsNothing);
    // The list's own dashed add row owns the add affordance while populated.
    expect(find.byType(AddReminderTile), findsOneWidget);
  });

  testWidgets('deleting every reminder transitions in the "all clear" state', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await clearAllReminders(tester);

    expect(find.text('All clear'), findsOneWidget);
    expect(find.text('New reminder'), findsOneWidget);
    // The list's trailing dashed circle is suppressed — the empty state's
    // button is the only add affordance now.
    expect(find.byType(AddReminderTile), findsNothing);
  });

  testWidgets('the empty state runs no backdrop blur (perf invariant)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await clearAllReminders(tester);

    expect(find.byType(EmptyRemindersState), findsOneWidget);
    expect(
      blurredGlassCount(tester),
      0,
      reason: 'the empty state bell uses resting (un-blurred) glass',
    );
  });

  testWidgets('tapping "New reminder" morphs on the button, then opens a modal', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await clearAllReminders(tester);
    expect(find.byType(EmergingReminderTile), findsNothing);

    await tester.tap(find.text('New reminder'));
    await tester.pump();

    // Stage 1 — the new reminder first appears on top of the button: the
    // morphing "+"-into-tile is hosted inside the empty state (not at the list's
    // top).
    expect(
      find.descendant(
        of: find.byType(EmptyRemindersState),
        matching: find.byType(EmergingReminderTile),
      ),
      findsOneWidget,
    );

    // Stage 2 — after the morph, a real tile plays the "closer" lean on the
    // button (the animation that was previously skipped) before the modal.
    await tester.pump(const Duration(milliseconds: 500)); // morph completes
    expect(
      find.descendant(
        of: find.byType(EmptyRemindersState),
        matching: find.byType(ReminderTile),
      ),
      findsOneWidget,
    );

    // Stage 3 — it hands off into the modal with seeded edit fields, just like a
    // list add, and the empty state retires.
    await pumpUntilFound(tester, find.byType(TextField));
    expect(find.byType(TextField), findsNWidgets(2));
    // The empty state crossfades out once the add lands.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(EmptyRemindersState), findsNothing);
  });
}
