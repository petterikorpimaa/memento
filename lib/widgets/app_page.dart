import 'package:flutter/material.dart';

/// Full-screen background gradient: a faint teal at the top fading to a faint
/// plum at the bottom. Shared by every page in the app.
const LinearGradient kBackgroundGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: <Color>[Color(0xFF090C0E), Color(0xFF0A0B0F), Color(0xFF0F0C13)],
  stops: <double>[0.0, 0.55, 1.0],
);

/// Wraps a page's [child] with the shared gradient background, the top
/// safe-area inset and a Material ancestor.
///
/// The body keeps its bottom edge at the physical screen bottom (`SafeArea`
/// bottom is left off) so list content can run all the way down. The reminders
/// list now carries its own trailing "add" row, so there is no floating button.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.child, this.background = true});

  /// The page content.
  final Widget child;

  /// Whether to paint the gradient background. Pushed pages that sit over an
  /// already-painted gradient can set this to `false`.
  final bool background;

  @override
  Widget build(BuildContext context) {
    // The screens are Material-built and rely on a Material ancestor for their
    // default text style and ink; provide a transparent one so text never falls
    // back to Flutter's debug yellow underline.
    final Widget content = Material(
      type: MaterialType.transparency,
      child: SafeArea(bottom: false, child: child),
    );
    if (!background) return content;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: kBackgroundGradient),
      child: content,
    );
  }
}
