import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../data/locale_repository.dart';
import 'app_locale.dart';
import 'app_strings.dart';

/// Holds the active [AppLocale], exposes its [AppStrings], and persists changes.
///
/// A [ChangeNotifier] so the widget tree can rebuild on a language change;
/// `LocaleScope` adapts it into an `InheritedNotifier` for descendants. This is
/// the one piece of app state shared across screens that has to outlive any
/// single route, so it is owned by `MyApp` rather than a screen.
class LocaleController extends ChangeNotifier {
  LocaleController(this._repository, {AppLocale? initial})
    : _locale = initial ?? AppLocale.fallback;

  final LocaleRepository _repository;
  AppLocale _locale;

  /// The active language.
  AppLocale get locale => _locale;

  /// The strings for the active language.
  AppStrings get strings => AppStrings.of(_locale);

  /// Switches the language, then persists the choice.
  ///
  /// Notifies listeners first so the UI updates immediately; persistence is best
  /// effort and a failure to write is logged rather than surfaced — the change
  /// still applies for this session.
  Future<void> setLocale(AppLocale next) async {
    if (next == _locale) return;
    _locale = next;
    notifyListeners();
    try {
      await _repository.save(next);
    } catch (error, stackTrace) {
      developer.log(
        'Could not persist the chosen language.',
        name: 'memento.locale',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
