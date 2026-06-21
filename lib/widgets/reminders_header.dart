import 'package:flutter/material.dart';

import 'edit_mode_actions.dart';
import 'header_icon_button.dart';

/// The reminders screen's header: a title with an "active count" subtitle, the
/// edit / cancel + confirm actions, and the settings button.
///
/// Purely presentational — every string is resolved by the caller and every
/// action is a callback, so it has no state or localization coupling.
class RemindersHeader extends StatelessWidget {
  const RemindersHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.settingsTooltip,
    required this.editing,
    required this.hasChanges,
    required this.onEditPressed,
    required this.onConfirm,
    required this.onOpenSettings,
  });

  /// The screen title (e.g. localized "Reminders").
  final String title;

  /// The subtitle line (e.g. localized "N active").
  final String subtitle;

  /// Tooltip for the settings button.
  final String settingsTooltip;

  /// Whether the screen is in edit mode — flips the primary action between the
  /// edit pencil and a cancel cross, and reveals the confirm check.
  final bool editing;

  /// Whether any tile is marked for deletion — enables the confirm check.
  final bool hasChanges;

  /// The primary action: enter edit mode, or cancel it.
  final VoidCallback onEditPressed;

  /// Commit the pending deletions (the confirm check).
  final VoidCallback onConfirm;

  /// Open the settings page.
  final VoidCallback onOpenSettings;

  static const Color _titleColor = Color(0xFFF4F6FA);
  static const Color _subtitleColor = Color(0xFF8A929E);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    color: _titleColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _subtitleColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          EditModeActions(
            editing: editing,
            hasChanges: hasChanges,
            onPrimary: onEditPressed,
            onConfirm: onConfirm,
          ),
          const SizedBox(width: 8),
          HeaderIconButton(
            icon: Icons.settings_rounded,
            tooltip: settingsTooltip,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}
