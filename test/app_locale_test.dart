// Unit tests for the AppLocale enum: code/endonym values, code parsing, and the
// supported-locale list that drives MaterialApp.

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/l10n/app_locale.dart';

void main() {
  test('each language carries its subtag and endonym', () {
    expect(AppLocale.english.code, 'en');
    expect(AppLocale.english.endonym, 'English');
    expect(AppLocale.finnish.code, 'fi');
    expect(AppLocale.finnish.endonym, 'Suomi');
  });

  test('the fallback language is English', () {
    expect(AppLocale.fallback, AppLocale.english);
  });

  test('fromCode resolves a known subtag', () {
    expect(AppLocale.fromCode('en'), AppLocale.english);
    expect(AppLocale.fromCode('fi'), AppLocale.finnish);
  });

  test('fromCode returns null for an unknown or missing subtag', () {
    expect(AppLocale.fromCode('sv'), isNull);
    expect(AppLocale.fromCode(''), isNull);
    expect(AppLocale.fromCode(null), isNull);
  });

  test('locale builds a Flutter Locale from the subtag', () {
    expect(AppLocale.finnish.locale, const Locale('fi'));
  });

  test('supportedLocales lists every shipped language', () {
    expect(AppLocale.supportedLocales, <Locale>[
      const Locale('en'),
      const Locale('fi'),
    ]);
  });
}
