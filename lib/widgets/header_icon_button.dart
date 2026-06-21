import 'package:flutter/material.dart';

import '../constants/app_durations.dart';
import '../models/reminder_item.dart';

/// Shared chrome for a 44×44 rounded-square header button.
///
/// An [AnimatedContainer] eases its [fill] and [border] whenever they change,
/// wrapping a centred [child] (usually a [HeaderGlyph]) with the tap ink and an
/// optional [tooltip]. Colours are resolved by the caller, so any number of
/// on / off / "danger" states can animate through the same box (see
/// [HeaderIconButton] for the simple two-state case and `EditModeActions` for
/// the edit → cancel morph).
class HeaderActionButton extends StatelessWidget {
  const HeaderActionButton({
    super.key,
    required this.fill,
    required this.border,
    required this.onPressed,
    required this.child,
    this.tooltip,
    this.duration = AppDurations.fast,
  });

  /// Box fill colour. Eased on change.
  final Color fill;

  /// Box border colour. Eased on change.
  final Color border;

  final VoidCallback onPressed;

  /// Centred content, typically a [HeaderGlyph].
  final Widget child;

  final String? tooltip;

  /// How long the fill/border ease takes when they change.
  final Duration duration;

  /// Footprint and corner radius shared by every header button.
  static const double size = 44;
  static const double radius = 14;

  @override
  Widget build(BuildContext context) {
    final Widget button = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onPressed,
          child: Center(child: child),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// A header-button glyph that eases its [color] on change and cross-fades when
/// the [icon] shape itself swaps (e.g. the edit pencil morphing into a close
/// cross), so a button can change both what it shows and its tint smoothly.
class HeaderGlyph extends StatelessWidget {
  const HeaderGlyph({
    super.key,
    required this.icon,
    required this.color,
    this.duration = AppDurations.fast,
  });

  final IconData icon;
  final Color color;
  final Duration duration;

  static const double _iconSize = 22;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      transitionBuilder: (Widget child, Animation<double> animation) =>
          ScaleTransition(
            scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
      // Keyed by the glyph shape: a colour-only change keeps the same key (so
      // the inner builder just eases the tint), while an icon swap mounts a
      // fresh subtree and the switcher cross-fades between them.
      child: TweenAnimationBuilder<Color?>(
        key: ValueKey<IconData>(icon),
        tween: ColorTween(end: color),
        duration: duration,
        builder: (BuildContext context, Color? tint, Widget? _) =>
            Icon(icon, size: _iconSize, color: tint),
      ),
    );
  }
}

/// Small rounded-square icon button used in the reminders header (edit and
/// settings sit side by side). When [active] it fills with the app accent and
/// flips its glyph dark, so an "on" state (e.g. edit mode) reads clearly.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;

  /// Whether the button is in its "on" state (accent fill, dark glyph).
  final bool active;

  final String? tooltip;

  static const Color _idleIcon = Color(0xFFC7CDD6);
  static const Color _activeIcon = Color(0xFF0E1116);

  @override
  Widget build(BuildContext context) {
    return HeaderActionButton(
      fill: active
          ? ReminderColors.teal.withValues(alpha: 0.95)
          : Colors.white.withValues(alpha: 0.06),
      border: active
          ? Colors.transparent
          : Colors.white.withValues(alpha: 0.08),
      onPressed: onPressed,
      tooltip: tooltip,
      child: HeaderGlyph(icon: icon, color: active ? _activeIcon : _idleIcon),
    );
  }
}
