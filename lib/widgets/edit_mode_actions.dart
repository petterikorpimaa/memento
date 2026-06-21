import 'package:flutter/material.dart';

import '../constants/app_durations.dart';
import '../l10n/app_strings.dart';
import '../l10n/locale_scope.dart';
import '../models/reminder_item.dart';
import 'header_icon_button.dart';

/// The reminders header's edit control: the edit button morphs into a cancel
/// cross once a change is pending, and a save check fades in beside it.
///
/// Three resting shapes, driven by [editing] and [hasChanges]:
///  * **not editing** — a single idle edit button; tapping it enters edit mode;
///  * **editing, nothing changed** — the same button, now accent-filled; tapping
///    it leaves edit mode (there is nothing to undo);
///  * **editing, a change pending** — the edit button morphs in place into a
///    red "cancel" cross (fill and glyph ease over), and a green "save" check
///    fades + scales in to its left (no horizontal movement: its layout slot
///    opens while the right-anchored cancel cross holds the edit button's slot).
///
/// The morphing button reports [onPrimary]; the parent decides what that means
/// by mode (enter when resting, cancel when editing). The save check reports
/// [onConfirm] — committing the pending changes — and only this commits.
class EditModeActions extends StatelessWidget {
  const EditModeActions({
    super.key,
    required this.editing,
    required this.hasChanges,
    required this.onPrimary,
    required this.onConfirm,
  });

  /// Whether the list is in edit mode.
  final bool editing;

  /// Whether edit mode has a pending change to save or discard (a tile is
  /// marked for deletion). Morphs the button to "cancel" and reveals the save
  /// check.
  final bool hasChanges;

  /// The edit / cancel button was tapped.
  final VoidCallback onPrimary;

  /// The save check was tapped — apply the pending changes.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Only the save check transitions by fade + scale. An AnimatedSwitcher
        // swaps it against an empty box, so its slot simply opens (no slide):
        // the incoming check sizes the slot at once, and the right-anchored
        // primary button below holds its place while the check fades/scales in.
        AnimatedSwitcher(
          duration: AppDurations.normal,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (Widget child, Animation<double> animation) =>
              FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                  child: child,
                ),
              ),
          child: editing && hasChanges
              ? Padding(
                  key: const ValueKey<String>('save'),
                  padding: const EdgeInsets.only(right: 8),
                  child: _ConfirmButton(onPressed: onConfirm),
                )
              : const SizedBox(key: ValueKey<String>('no-save')),
        ),
        // The edit button itself morphs in place into the cancel cross.
        _PrimaryEditButton(
          editing: editing,
          danger: editing && hasChanges,
          onPressed: onPrimary,
        ),
      ],
    );
  }
}

/// The header's edit button as it morphs through edit mode: idle edit glyph →
/// accent-filled edit glyph (editing) → red cross ([danger], a change pending).
/// The fill, border and glyph all ease, so the change of meaning is legible.
class _PrimaryEditButton extends StatelessWidget {
  const _PrimaryEditButton({
    required this.editing,
    required this.danger,
    required this.onPressed,
  });

  final bool editing;

  /// Editing with a pending change: the button becomes a red "cancel" cross.
  final bool danger;

  final VoidCallback onPressed;

  static const Color _idleIcon = Color(0xFFC7CDD6);
  static const Color _accentIcon = Color(0xFF0E1116);

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = LocaleScope.stringsOf(context);
    final Color fill;
    final Color iconColor;
    if (danger) {
      fill = kCancelRed.withValues(alpha: 0.95);
      iconColor = Colors.white;
    } else if (editing) {
      fill = ReminderColors.teal.withValues(alpha: 0.95);
      iconColor = _accentIcon;
    } else {
      fill = Colors.white.withValues(alpha: 0.06);
      iconColor = _idleIcon;
    }
    return HeaderActionButton(
      fill: fill,
      border: editing
          ? Colors.transparent
          : Colors.white.withValues(alpha: 0.08),
      onPressed: onPressed,
      tooltip: !editing
          ? strings.edit
          : danger
          ? strings.cancel
          : strings.done,
      child: HeaderGlyph(
        icon: danger ? Icons.close_rounded : Icons.edit_outlined,
        color: iconColor,
      ),
    );
  }
}

/// The green check that commits the pending edit-mode changes.
class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return HeaderActionButton(
      fill: kConfirmGreen.withValues(alpha: 0.95),
      border: Colors.transparent,
      onPressed: onPressed,
      tooltip: LocaleScope.stringsOf(context).confirm,
      child: const HeaderGlyph(
        icon: Icons.check_rounded,
        color: Color(0xFF0E1116),
      ),
    );
  }
}

/// Red of the "cancel" cross, matched to the tile's delete-toggle accent so the
/// destructive language reads the same in the header as on the rows.
const Color kCancelRed = Color(0xFFFF5A5A);

/// Green of the "save" check — a clear, positive counterpart to the cancel red,
/// distinct from the app's teal accent.
const Color kConfirmGreen = Color(0xFF34D399);
