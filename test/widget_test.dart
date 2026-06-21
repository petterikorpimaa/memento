// Tests for the single-screen shell: a full-height reminders list with edit and
// settings buttons in the header (the old bottom tab bar is gone).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/main.dart';
import 'package:memento/models/reminder_item.dart';
import 'package:memento/widgets/add_reminder_tile.dart';
import 'package:memento/widgets/glass.dart';
import 'package:memento/widgets/pill_segmented_control.dart';
import 'package:memento/widgets/reminder_chip.dart';
import 'package:memento/widgets/reminder_modal.dart';
import 'package:memento/widgets/reminder_tile.dart';
import 'package:memento/widgets/reorderable_reminder_list.dart';

void main() {
  testWidgets('renders the reminders list with no bottom nav bar', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Reminders'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('the settings button pushes (and pops) the settings page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Compact view'), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Compact view'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Compact view'), findsNothing);
    expect(find.text('Reminders'), findsOneWidget);
  });

  testWidgets(
    'edit mode swaps bells for delete buttons and removes marked tiles',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      expect(find.text('Morning workout'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);

      // Enter edit mode -> every tile shows a delete button.
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.delete_outline_rounded),
        findsNWidgets(kReminders.length),
      );

      // Mark the first tile (Morning workout) for deletion, then commit it via
      // the confirm check that slides out once a change is pending.
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Morning workout'), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    },
  );

  testWidgets(
    'marking a tile morphs edit into cancel and reveals save; unmarking reverts',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // At rest only the Edit button is in the header.
      expect(find.byTooltip('Edit'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();

      // Edit mode with nothing marked: still just the one button (now "Done"),
      // no save check yet.
      expect(find.byTooltip('Done'), findsOneWidget);
      expect(find.byTooltip('Confirm'), findsNothing);
      expect(find.byTooltip('Cancel'), findsNothing);

      // Mark a tile -> the edit button morphs into the cancel cross, and the
      // save (confirm) check appears beside it.
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Confirm'), findsOneWidget);
      expect(find.byTooltip('Cancel'), findsOneWidget);
      expect(find.byTooltip('Done'), findsNothing);

      // Unmark it -> the cancel cross morphs back to edit ("Done") and the save
      // check fades away.
      await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Done'), findsOneWidget);
      expect(find.byTooltip('Confirm'), findsNothing);
      expect(find.byTooltip('Cancel'), findsNothing);
    },
  );

  testWidgets('edit mode fades out the add row', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // The add row fades/scales out in place rather than being removed, so it
    // stays in the tree; check the opacity its enclosing fade settles to.
    double addOpacity() => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byType(AddReminderTile),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    expect(addOpacity(), 1.0);

    // Entering edit mode fades the trailing "+" row out — adding is off while
    // tiles are in delete mode.
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(addOpacity(), 0.0);

    // Leaving edit mode fades it back in.
    await tester.tap(find.byTooltip('Done'));
    await tester.pumpAndSettle();
    expect(addOpacity(), 1.0);
  });

  testWidgets('cancel leaves edit mode without deleting marked tiles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    // Mark the first tile for deletion.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cancel'), findsOneWidget);

    // Cancelling drops out of edit mode without removing anything.
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(find.text('Morning workout'), findsOneWidget);
    // Back to the resting header: the lone edit button, no save/cancel pair.
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsNothing);
    expect(find.byTooltip('Confirm'), findsNothing);
  });

  testWidgets('toggling "Compact view" hides subtitles and shortens the rows', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // At rest the first reminder shows its subtitle.
    expect(find.text('Leg day at the gym'), findsOneWidget);
    final double fullHeight = tester
        .getSize(find.byType(ReminderTile).first)
        .height;

    // Flip the compact toggle from the settings page, then return.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compact view'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Subtitles are gone and the rows are visibly shorter.
    expect(find.text('Leg day at the gym'), findsNothing);
    final double compactHeight = tester
        .getSize(find.byType(ReminderTile).first)
        .height;
    expect(compactHeight, lessThan(fullHeight));

    // The title still shows — only the supporting line is dropped.
    expect(find.text('Morning workout'), findsOneWidget);
  });

  testWidgets('tapping a reminder reveals seeded title & description fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // No edit fields until a reminder's modal is open.
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Morning workout'));
    await tester.pumpAndSettle();

    // The modal hosts a title and a description field, seeded from the tapped
    // reminder.
    expect(find.byType(TextField), findsNWidgets(2));
    final TextField title = tester.widget<TextField>(
      find.byType(TextField).first,
    );
    final TextField description = tester.widget<TextField>(
      find.byType(TextField).last,
    );
    expect(title.controller?.text, 'Morning workout');
    expect(description.controller?.text, 'Leg day at the gym');

    // Labels live as placeholders now, shown only while a field is empty.
    expect(title.decoration?.hintText, 'Title');
    expect(description.decoration?.hintText, 'Description');

    // The content keeps a clear horizontal inset — it must not span the modal
    // edge to edge. Regression guard for the scaled-content width: a too-tight
    // width constraint once forced the row out to the card edges.
    final double overlayWidth = tester
        .getSize(find.byType(ReminderModalOverlay))
        .width;
    final double fieldWidth = tester
        .getSize(find.byType(TextField).first)
        .width;
    expect(fieldWidth, lessThan(overlayWidth - 30));
  });

  testWidgets('editing a field updates the reminder once the modal closes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning workout'));
    await tester.pumpAndSettle();

    // Type a new title into the first (title) field. The edit commits live, so
    // the header preview row picks up the new title too.
    await tester.enterText(find.byType(TextField).first, 'Evening run');
    await tester.pump();

    // Close the modal via its header preview (the first 'Evening run' in the
    // overlay; the second is the title field), then drop focus so the
    // cursor-blink timer ends and the test can settle.
    await tester.tap(
      find
          .descendant(
            of: find.byType(ReminderModalOverlay),
            matching: find.text('Evening run'),
          )
          .first,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    // The edit persisted to the reminder: the resting tile shows the new title.
    expect(find.text('Evening run'), findsOneWidget);
    expect(find.text('Morning workout'), findsNothing);
  });

  testWidgets('tapping Edit while the modal is open closes it (and edits)', (
    WidgetTester tester,
  ) async {
    // The header buttons sit above the modal's tap barrier, so they stay live
    // while a reminder is open. Tapping Edit must both enter edit mode and fold
    // the modal away.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning workout'));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderModalOverlay), findsOneWidget);

    await tester.tap(find.byTooltip('Edit'));

    // Mid-close the modal is still collapsing, and edit mode has NOT engaged
    // yet: snapping into it at once would reverse the hidden tile early and
    // swallow its rest animation. Bells stay bells until the close finishes.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(ReminderModalOverlay), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);

    await tester.pumpAndSettle();

    // The modal is gone and only now is the list in edit mode (bells -> deletes).
    expect(find.byType(ReminderModalOverlay), findsNothing);
    expect(
      find.byIcon(Icons.delete_outline_rounded),
      findsNWidgets(kReminders.length),
    );
  });

  testWidgets('the settings button is tappable while the modal is open', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning workout'));
    await tester.pumpAndSettle();
    expect(find.byType(ReminderModalOverlay), findsOneWidget);

    // The barrier no longer swallows header taps, so Settings is reachable. It
    // closes the open modal first (full animation), then pushes the page.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Compact view'), findsNothing);

    await tester.pumpAndSettle();

    // The settings page is now up and the modal has been dismissed.
    expect(find.text('Compact view'), findsOneWidget);
    expect(find.byType(ReminderModalOverlay), findsNothing);
  });

  testWidgets('the modal hosts an Alert/Timer segmented control bound to type', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // 'Morning workout' is an alarm due today -> its chip shows a clock, never
    // the timer's hourglass.
    await tester.tap(find.text('Morning workout'));
    await tester.pumpAndSettle();

    // The control sits under the inputs with both options.
    expect(find.byType(PillSegmentedControl<ReminderType>), findsOneWidget);
    expect(find.text('Alert'), findsOneWidget);
    expect(find.text('Timer'), findsOneWidget);

    // The modal's own chip starts as a clock (the list has a separate timer
    // reminder with its own hourglass, so scope the check to the overlay).
    Finder modalHourglass() => find.descendant(
      of: find.byType(ReminderModalOverlay),
      matching: find.byIcon(Icons.hourglass_bottom_rounded),
    );
    expect(modalHourglass(), findsNothing);

    // Picking Timer flips the reminder's type, so the modal's header chip swaps
    // to the countdown hourglass.
    await tester.tap(find.text('Timer'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(modalHourglass(), findsOneWidget);
  });

  testWidgets('the modal segmented control is tappable to its bottom edge', (
    WidgetTester tester,
  ) async {
    // Regression: the modal scales its content by the tile's "closer" factor,
    // and a Transform's layout box stays unscaled — so the bottom of the
    // (scaled) Alert/Timer control used to overhang a dead, unhittable strip.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning workout'));
    await tester.pumpAndSettle();

    Finder modalHourglass() => find.descendant(
      of: find.byType(ReminderModalOverlay),
      matching: find.byIcon(Icons.hourglass_bottom_rounded),
    );
    expect(modalHourglass(), findsNothing);

    // Tap low in the Timer (right) half — a few px above the control's bottom
    // edge, below its label — and it must still switch the type to a timer.
    final Rect rect = tester.getRect(
      find.byType(PillSegmentedControl<ReminderType>),
    );
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.bottom - 3));
    await tester.pump(const Duration(milliseconds: 350));

    expect(modalHourglass(), findsOneWidget);
  });

  testWidgets('touching the type control freezes the modal timer preview', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Open a timer reminder — its modal header runs a live countdown.
    await tester.tap(find.text('Water the plants'));
    await tester.pumpAndSettle();

    String modalCountdown() {
      final Finder text = find.descendant(
        of: find.descendant(
          of: find.byType(ReminderModalOverlay),
          matching: find.byType(ReminderChip),
        ),
        matching: find.byType(Text),
      );
      return tester.widget<Text>(text).data!;
    }

    // It ticks down on its own.
    final String start = modalCountdown();
    await tester.pump(const Duration(seconds: 2));
    expect(modalCountdown(), isNot(start));

    // Touch the type control: the countdown freezes in place (not reset) and
    // stays put while the modal is open.
    await tester.tap(find.text('Timer'));
    await tester.pump();
    final String frozen = modalCountdown();
    await tester.pump(const Duration(seconds: 3));
    expect(
      modalCountdown(),
      frozen,
      reason: 'a paused countdown must hold its value, not keep ticking',
    );
  });

  testWidgets('opening a running timer keeps its countdown live, not reset', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Let the resting list's timer run down a few seconds.
    await tester.pump(const Duration(seconds: 4));

    await tester.tap(find.text('Water the plants'));
    await tester.pumpAndSettle();

    String modalCountdown() {
      final Finder text = find.descendant(
        of: find.descendant(
          of: find.byType(ReminderModalOverlay),
          matching: find.byType(ReminderChip),
        ),
        matching: find.byType(Text),
      );
      return tester.widget<Text>(text).data!;
    }

    // No reset: the preview continues below the full 25:00, not back at it.
    final String opened = modalCountdown();
    expect(opened, isNot('25:00'));

    // No pause: nothing was touched, so it keeps ticking on its own.
    await tester.pump(const Duration(seconds: 2));
    expect(modalCountdown(), isNot(opened));
  });

  testWidgets('the list stays scrollable in edit mode', (
    WidgetTester tester,
  ) async {
    // Regression guard: edit mode used to disable scrolling outright (so the
    // paint-to-delete drag wasn't stolen). The paint button now wins the
    // gesture arena on its own, so scrolling must stay enabled or long lists
    // become unreachable while marking tiles. See [_PaintToggleButton].
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();

    final SingleChildScrollView scrollView = tester
        .widget<SingleChildScrollView>(
          find.ancestor(
            of: find.byType(ReorderableReminderList),
            matching: find.byType(SingleChildScrollView),
          ),
        );
    expect(
      scrollView.physics,
      isNot(isA<NeverScrollableScrollPhysics>()),
      reason:
          'Edit mode must remain scrollable so tiles below the fold stay '
          'reachable while marking them for deletion.',
    );
  });

  testWidgets('a tile marked for deletion dims its edge rim', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    Iterable<GlassSurface> markedSurfaces() => tester
        .widgetList<GlassSurface>(find.byType(GlassSurface))
        .where(
          (GlassSurface s) => s.edgeOpacity == ReminderTile.markedEdgeOpacity,
        );

    // Nothing is marked at rest, so no tile uses the dimmed (darker) edge.
    expect(markedSurfaces(), isEmpty);

    // Enter edit mode and mark the first tile for deletion.
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();

    // Exactly that one tile's edge rim has darkened.
    expect(markedSurfaces(), hasLength(1));
  });

  testWidgets('the add row is the list\'s last item', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // The "+" affordance now lives in the list as a single trailing row...
    expect(find.byType(AddReminderTile), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AddReminderTile),
        matching: find.byIcon(Icons.add_rounded),
      ),
      findsOneWidget,
    );

    // ...sitting below the last reminder tile.
    final double lastTileBottom = tester
        .getBottomLeft(find.byType(ReminderTile).last)
        .dy;
    final double addTop = tester.getTopLeft(find.byType(AddReminderTile)).dy;
    expect(addTop, greaterThan(lastTileBottom));
  });

  testWidgets('a recurring reminder badges its chip with a repeat icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Exactly one demo reminder ("Call Mom", a weekly catch-up) is recurring,
    // so the resting list shows one repeat badge — on that chip and no other.
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ReminderTile, 'Call Mom'),
        matching: find.byIcon(Icons.repeat_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('screen text has no debug yellow underline (Material ancestor)', (
    WidgetTester tester,
  ) async {
    // Regression guard: a Material ancestor must wrap the screens, otherwise
    // every Text inherits Flutter's debug underline decoration.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    final Iterable<RenderParagraph> paragraphs = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText));
    expect(paragraphs, isNotEmpty);
    for (final RenderParagraph paragraph in paragraphs) {
      expect(
        paragraph.text.style?.decoration,
        isNot(TextDecoration.underline),
        reason:
            'Text rendered without a Material ancestor shows the debug '
            'yellow underline.',
      );
    }
  });
}
