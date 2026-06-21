// Guards the disintegration overlay's teardown contract: onDone fires once when
// the dissolve completes, and also when the overlay is disposed mid-flight — so
// an interrupted dissolve can release its captured image and entry instead of
// leaking them.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/widgets/disintegration_overlay.dart';

/// A tiny image built synchronously (no codec/async), so it can be created
/// straight inside the widget-test fake-async zone.
ui.Image makeImage() {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  return recorder.endRecording().toImageSync(8, 8);
}

/// Hosts the overlay in a small, tightly-bounded box — exactly as
/// `playDisintegration` wraps it in a Positioned at the tile's size. Without a
/// tight size the dust painter would tile the full test surface.
Widget host(ui.Image image, VoidCallback onDone) => MaterialApp(
  home: Overlay(
    initialEntries: <OverlayEntry>[
      OverlayEntry(
        builder: (BuildContext context) => Positioned(
          left: 0,
          top: 0,
          width: 40,
          height: 40,
          child: DisintegrationOverlay(
            image: image,
            pixelRatio: 1,
            onDone: onDone,
          ),
        ),
      ),
    ],
  ),
);

void main() {
  testWidgets('a completed dissolve fires onDone', (WidgetTester tester) async {
    final ui.Image image = makeImage();
    int done = 0;
    await tester.pumpWidget(host(image, () => done++));

    // Past the 1200ms dissolve; the completion handler defers onDone a frame.
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();

    expect(done, 1);
    image.dispose();
  });

  testWidgets('a dissolve interrupted mid-flight still fires onDone', (
    WidgetTester tester,
  ) async {
    final ui.Image image = makeImage();
    int done = 0;
    await tester.pumpWidget(host(image, () => done++));

    // Only partway through, then tear the tree down — the completion path never
    // runs, so disposal must drive the teardown instead.
    await tester.pump(const Duration(milliseconds: 200));
    expect(done, 0);
    await tester.pumpWidget(const SizedBox());

    expect(done, 1);
    expect(tester.takeException(), isNull);
    image.dispose();
  });
}
