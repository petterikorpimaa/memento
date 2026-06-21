import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_locale.dart';
import 'locale_repository.dart';

/// A [LocaleRepository] backed by `shared_preferences`, storing the language as
/// its [AppLocale.code] under a single key. Available on every target platform.
class SharedPreferencesLocaleRepository implements LocaleRepository {
  SharedPreferencesLocaleRepository(this._prefs);

  /// The key the language code is stored under.
  static const String _key = 'app_locale_v1';

  final SharedPreferences _prefs;

  /// Opens shared preferences and wraps it in a repository.
  static Future<SharedPreferencesLocaleRepository> create() async =>
      SharedPreferencesLocaleRepository(await SharedPreferences.getInstance());

  @override
  Future<AppLocale?> load() async => AppLocale.fromCode(_prefs.getString(_key));

  @override
  Future<void> save(AppLocale locale) => _prefs.setString(_key, locale.code);
}
