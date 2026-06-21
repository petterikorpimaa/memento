import 'package:flutter/widgets.dart' show Locale;

/// The languages the app ships with.
///
/// [english] is the default and the fallback when a persisted or device locale
/// is not recognised. Each value carries its IETF language subtag (persisted to
/// disk) and its endonym — the language's name written in that language — which
/// is what the settings language picker shows.
enum AppLocale {
  english('en', 'English'),
  finnish('fi', 'Suomi');

  const AppLocale(this.code, this.endonym);

  /// The IETF language subtag (e.g. `en`, `fi`) persisted to disk and used to
  /// build [locale].
  final String code;

  /// The language's name in its own language, shown in the language picker
  /// (e.g. "English", "Suomi"). Endonyms are intentionally not translated.
  final String endonym;

  /// The default language, used when nothing is stored and the device language
  /// is not one we ship.
  static const AppLocale fallback = AppLocale.english;

  /// The Flutter [Locale] for this language.
  Locale get locale => Locale(code);

  /// The [AppLocale] for a stored or device [code], or null when unrecognised.
  ///
  /// Matches on the language subtag only, so a device locale like `fi_FI`
  /// resolves to [finnish] when passed its `languageCode`.
  static AppLocale? fromCode(String? code) {
    for (final AppLocale value in values) {
      if (value.code == code) return value;
    }
    return null;
  }

  /// Every shipped language as a [Locale], for `MaterialApp.supportedLocales`.
  static List<Locale> get supportedLocales =>
      values.map((AppLocale value) => value.locale).toList(growable: false);
}
