import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

/// App-wide scroll behaviour.
///
/// It keeps Android's native stretch overscroll — the Samsung-style "rubber
/// band" that scales the list at its ends — by *not* overriding
/// [buildOverscrollIndicator]; [MaterialScrollBehavior] supplies the platform
/// [StretchingOverscrollIndicator] on Android (Material 3). The glass tiles are
/// now plain widgets, so the stretch no longer corrupts any backdrop and is
/// free to play.
///
/// The only customisation is [dragDevices]: it additionally lets a mouse,
/// trackpad or stylus drag-scroll the list (handy on the desktop and web
/// targets), on top of the default touch dragging.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
