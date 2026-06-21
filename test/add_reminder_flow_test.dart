// Tests the "add reminder" entrance choreography wired to the trailing "+"
// button: it morphs into a fresh tile (the icon fades out, the glass tile grows
// in, the content fades in) and then floats that tile up into the modal — the
// same hand-off a tapped tile uses. Afterwards the new reminder stays in the
// list and, like every other resting tile, runs no backdrop blur.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/main.dart';
import 'package:memento/models/reminder_item.dart';
import 'package:memento/widgets/add_reminder_tile.dart';
import 'package:memento/widgets/emerging_reminder_tile.dart';
import 'package:memento/widgets/glass.dart';
import 'package:memento/widgets/reminder_chip.dart';
import 'package:memento/widgets/reminder_modal.dart';
import 'package:memento/widgets/reminder_tile.dart';

int _blurredGlassCount(WidgetTester tester) => tester
    .widgetList<GlassSurface>(find.byType(GlassSurface))
    .where((GlassSurface g) => g.blurSigma > 0)
    .length;

void main() {
  testWidgets('tapping "+" morphs it into a tile, then floats it to the modal', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Just the seed reminders so far, and the list is at rest (no blurred
    // glass).
    expect(find.byType(ReminderTile), findsNWidgets(kReminders.length));
    expect(_blurredGlassCount(tester), 0);

    // Press the add button to kick off the morph.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump(); // start the add controller
    await tester.pump(const Duration(milliseconds: 100));

    // Mid-morph: the "+" slot is now the emerging tile, and a fresh add button
    // still rides below it.
    expect(find.byType(EmergingReminderTile), findsOneWidget);
    expect(find.byType(AddReminderTile), findsOneWidget);

    // Let the whole choreography play out: morph -> "closer" -> modal open.
    await tester.pumpAndSettle();

    // The morph is done (no emerging tile left) and the fresh reminder is now
    // the open modal — which, as the active surface, runs a backdrop blur. The
    // new reminder starts blank, so it has no title text (the fields show their
    // placeholders); identify it structurally instead.
    expect(find.byType(EmergingReminderTile), findsNothing);
    expect(find.byType(ReminderModalOverlay), findsOneWidget);
    expect(find.byType(ReminderTile), findsNWidgets(kReminders.length + 1));
    expect(
      _blurredGlassCount(tester),
      greaterThan(0),
      reason: 'the add flow should end with the new reminder open as the modal',
    );

    // Dismiss the modal via its header preview — tap the status chip, which sits
    // in the dismiss area above the divider.
    await tester.tap(
      find.descendant(
        of: find.byType(ReminderModalOverlay),
        matching: find.byType(ReminderChip),
      ),
    );
    await tester.pumpAndSettle();

    // The new reminder persists in the list, at rest, with no blurred glass.
    expect(find.byType(ReminderModalOverlay), findsNothing);
    expect(find.byType(ReminderTile), findsNWidgets(kReminders.length + 1));
    expect(
      _blurredGlassCount(tester),
      0,
      reason: 'after the modal closes every tile must revert to fake glass',
    );
  });

  testWidgets('the add button is inert while a reminder is being added', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // First press starts the add.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(EmergingReminderTile), findsOneWidget);

    // A second press on the trailing add button mid-morph is ignored — still
    // exactly one emerging tile. (Target the button's own icon: the morphing
    // tile also paints a fading "+" glyph, so a bare icon finder is ambiguous.)
    await tester.tap(
      find.descendant(
        of: find.byType(AddReminderTile),
        matching: find.byIcon(Icons.add_rounded),
      ),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(EmergingReminderTile), findsOneWidget);

    await tester.pumpAndSettle();
  });
}
