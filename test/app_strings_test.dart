// Unit tests for the string table: the right instance per language, plural
// handling, and that the two languages actually differ.

import 'package:flutter_test/flutter_test.dart';

import 'package:memento/l10n/app_locale.dart';
import 'package:memento/l10n/app_strings.dart';

void main() {
  test('of() returns the matching language instance', () {
    expect(AppStrings.of(AppLocale.english), isA<EnglishStrings>());
    expect(AppStrings.of(AppLocale.finnish), isA<FinnishStrings>());
  });

  test('English pluralises the active-reminder subtitle', () {
    const AppStrings en = EnglishStrings();
    expect(en.activeReminders(0), 'No active reminders');
    expect(en.activeReminders(1), '1 active reminder');
    expect(en.activeReminders(5), '5 active reminders');
  });

  test('Finnish pluralises the active-reminder subtitle', () {
    const AppStrings fi = FinnishStrings();
    expect(fi.activeReminders(0), 'Ei aktiivisia muistutuksia');
    expect(fi.activeReminders(1), '1 aktiivinen muistutus');
    expect(fi.activeReminders(5), '5 aktiivista muistutusta');
  });

  test('the brand name is the same in every language', () {
    // appTitle is a proper noun, so it is intentionally not translated.
    expect(const EnglishStrings().appTitle, 'Memento');
    expect(const FinnishStrings().appTitle, 'Memento');
  });

  test('the two languages differ for every translated string', () {
    const AppStrings en = EnglishStrings();
    const AppStrings fi = FinnishStrings();
    expect(en.remindersTitle, isNot(fi.remindersTitle));
    expect(en.settingsTitle, isNot(fi.settingsTitle));
    expect(en.languageTitle, isNot(fi.languageTitle));
    expect(en.newReminder, isNot(fi.newReminder));
    expect(en.edit, isNot(fi.edit));
  });
}
