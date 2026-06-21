// Ground-truth tests for the reported bug: after an interaction ends (the modal
// closes, or a drag is dropped) the tile must drop its expensive backdrop blur
// and go back to the cheap "fake" glass (tint + edge rim only). If a tile keeps
// a backdrop blur, every interacted-with tile carries its own filter and a long
// list starts to lag.
//
// A tile (or the modal card) is the *active* (blurred) glass exactly when its
// `GlassSurface` has `blurSigma > 0`. Resting tiles build a `GlassSurface` with
// `blurSigma == 0` (no BackdropFilter at all). Counting surfaces with a
// positive sigma therefore counts the active, expensive glass — and that
// decision is made in our own widgets, so it is observable in a headless test.

import 'package:flutter_test/flutter_test.dart';

import 'package:memento/main.dart';
import 'package:memento/widgets/glass.dart';
import 'package:memento/widgets/reminder_modal.dart';

/// Number of glass surfaces currently running an (expensive) backdrop blur.
int blurredGlassCount(WidgetTester tester) => tester
    .widgetList<GlassSurface>(find.byType(GlassSurface))
    .where((GlassSurface g) => g.blurSigma > 0)
    .length;

void main() {
  testWidgets('all resting tiles use the cheap fake glass', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(
      blurredGlassCount(tester),
      0,
      reason: 'no tile should run a backdrop blur while the list is at rest',
    );
  });

  testWidgets('opening then closing the modal leaves no tile blurred', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(blurredGlassCount(tester), 0);

    // Tap a tile body to bring it "closer" and hand off into the modal.
    await tester.tap(find.text('Morning workout'));
    await tester.pumpAndSettle();
    expect(
      blurredGlassCount(tester),
      greaterThan(0),
      reason: 'the open modal card runs a backdrop blur',
    );

    // Dismiss via the modal's content section (the area above the divider). The
    // title now appears twice in the modal — once in the header preview row and
    // once in the editable title field — so dismiss via the first (the header).
    final Finder modalTitle = find.descendant(
      of: find.byType(ReminderModalOverlay),
      matching: find.text('Morning workout'),
    );
    expect(modalTitle, findsWidgets);
    await tester.tap(modalTitle.first);
    await tester.pumpAndSettle();

    expect(
      blurredGlassCount(tester),
      0,
      reason: 'after the modal closes every tile must revert to fake glass',
    );
  });

  testWidgets('dragging a tile and dropping it leaves no tile blurred', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(blurredGlassCount(tester), 0);

    final Finder tile = find.text('Morning workout');
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(tile),
    );
    // Hold past the long-press threshold to lift the tile into a drag.
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      blurredGlassCount(tester),
      greaterThan(0),
      reason: 'the lifted/dragged tile runs a backdrop blur',
    );

    // Drop it.
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      blurredGlassCount(tester),
      0,
      reason: 'after the drag settles the tile must revert to fake glass',
    );
  });

  testWidgets('a CANCELLED drag still reverts the tile to fake glass', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(blurredGlassCount(tester), 0);

    final Finder tile = find.text('Morning workout');
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(tile),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 80));
    expect(blurredGlassCount(tester), greaterThan(0));

    // The OS, app backgrounding, or a parent scrollable winning the gesture
    // arena cancels the pointer mid-drag instead of a clean lift. The long-press
    // recogniser fires onLongPressCancel here, NOT onLongPressEnd.
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(
      blurredGlassCount(tester),
      0,
      reason: 'a cancelled drag must also tear down the backdrop blur',
    );
  });
}
