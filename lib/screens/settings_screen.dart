import 'package:flutter/material.dart';

import '../l10n/app_locale.dart';
import '../l10n/app_strings.dart';
import '../l10n/locale_controller.dart';
import '../l10n/locale_scope.dart';
import '../models/reminder_item.dart';
import '../widgets/app_page.dart';
import '../widgets/pill_toggle.dart';

/// Settings page, pushed from the reminders header's settings button.
///
/// Carries its own gradient background and a back button so it stands on its
/// own as a pushed route. Holds the app's settings: the "Compact view" toggle,
/// which flips the shared [compactView] flag the reminders list listens to, and
/// the language picker, which writes the app-wide [LocaleController].
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.compactView});

  /// The app-level compact-layout flag, owned by `HomeShell`. The pill writes
  /// it; the reminders list reads it.
  final ValueNotifier<bool> compactView;

  static const Color _titleColor = Color(0xFFF4F6FA);

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = LocaleScope.stringsOf(context);
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 24, 18),
            child: Row(
              children: <Widget>[
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: _titleColor,
                  tooltip: strings.back,
                ),
                const SizedBox(width: 4),
                Text(
                  strings.settingsTitle,
                  style: const TextStyle(
                    color: _titleColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ValueListenableBuilder<bool>(
                  valueListenable: compactView,
                  builder: (BuildContext context, bool compact, _) {
                    return _SettingToggleRow(
                      title: strings.compactViewTitle,
                      description: strings.compactViewDescription,
                      value: compact,
                      onChanged: (bool next) => compactView.value = next,
                    );
                  },
                ),
                const SizedBox(height: 8),
                _LanguageSetting(
                  title: strings.languageTitle,
                  description: strings.languageDescription,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A single settings row: a title, a supporting line, and a [PillToggle] on the
/// trailing edge — plain text on the page, no tile background or border.
/// Tapping anywhere on the row flips it, so the whole row is one comfortable
/// target.
class _SettingToggleRow extends StatelessWidget {
  const _SettingToggleRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _SettingLabel(title: title, description: description),
            ),
            const SizedBox(width: 16),
            // The pill reflects state and is spoken as the toggle for assistive
            // tech via its own semantics; the row's GestureDetector also flips it.
            PillToggle(
              value: value,
              onChanged: onChanged,
              semanticLabel: title,
            ),
          ],
        ),
      ),
    );
  }
}

/// The language setting: a title, a supporting line, and a row of pills — one
/// per shipped [AppLocale] — with the active language filled. Picking one writes
/// the app-wide [LocaleController], which persists the choice and rebuilds the
/// whole app into the new language.
class _LanguageSetting extends StatelessWidget {
  const _LanguageSetting({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final LocaleController controller = LocaleScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SettingLabel(title: title, description: description),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              for (final AppLocale locale in AppLocale.values)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _LanguagePill(
                    label: locale.endonym,
                    selected: locale == controller.locale,
                    onTap: () => controller.setLocale(locale),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single selectable language chip — accent-filled when [selected].
class _LanguagePill extends StatelessWidget {
  const _LanguagePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const Color _selectedText = Color(0xFF0E1116);
  static const Color _idleText = Color(0xFFD7DCE5);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? ReminderColors.teal.withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _selectedText : _idleText,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// The title + supporting line shared by every settings entry.
class _SettingLabel extends StatelessWidget {
  const _SettingLabel({required this.title, required this.description});

  final String title;
  final String description;

  static const Color _titleColor = Color(0xFFF4F6FA);
  static const Color _descriptionColor = Color(0xFF8A929E);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            color: _titleColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          description,
          style: const TextStyle(
            color: _descriptionColor,
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
