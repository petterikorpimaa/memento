import 'package:flutter/material.dart';

import '../constants/app_durations.dart';

/// A compact pill-shaped on/off switch.
///
/// A knob slides across a stadium track whose fill lerps from a muted off shade
/// to [activeColor] (the theme primary by default) and grows a soft glow when
/// on. Tapping flips it via [onChanged]. The whole control is exposed to
/// assistive tech as a single toggle through [Semantics].
class PillToggle extends StatelessWidget {
  const PillToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.semanticLabel,
  });

  /// Whether the toggle is on.
  final bool value;

  /// Called with the requested new value when the pill is tapped.
  final ValueChanged<bool> onChanged;

  /// Track fill (and glow) colour when on. Defaults to the theme's primary.
  final Color? activeColor;

  /// Spoken label for screen readers describing what the toggle controls.
  final String? semanticLabel;

  static const double _width = 52;
  static const double _height = 30;
  static const double _knobInset = 3;

  static const Color _trackOff = Color(0xFF2A303C);
  static const Color _knob = Color(0xFFF4F6FA);

  @override
  Widget build(BuildContext context) {
    final Color activeFill =
        activeColor ?? Theme.of(context).colorScheme.primary;
    final double knobSize = _height - 2 * _knobInset;
    return Semantics(
      label: semanticLabel,
      toggled: value,
      container: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: value ? 1 : 0),
          duration: AppDurations.fast,
          curve: Curves.easeOut,
          builder: (BuildContext context, double t, _) {
            return Container(
              width: _width,
              height: _height,
              decoration: BoxDecoration(
                color: Color.lerp(_trackOff, activeFill, t),
                borderRadius: BorderRadius.circular(_height / 2),
                boxShadow: t > 0
                    ? <BoxShadow>[
                        BoxShadow(
                          color: activeFill.withValues(alpha: 0.35 * t),
                          blurRadius: 12 * t,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    // Travel spans the track minus the knob's two insets.
                    left: _knobInset + t * (_width - _height),
                    top: _knobInset,
                    child: Container(
                      width: knobSize,
                      height: knobSize,
                      decoration: const BoxDecoration(
                        color: _knob,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
