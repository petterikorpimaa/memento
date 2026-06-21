import '../l10n/app_locale.dart';
import 'locale_repository.dart';

/// A [LocaleRepository] that keeps the chosen language in memory only.
///
/// Two uses: as a test seam (seed it with a known [AppLocale] and assert on what
/// gets saved), and as the default when no repository is injected — `const
/// MyApp()` falls back to one, so the widget tests run without touching disk.
class InMemoryLocaleRepository implements LocaleRepository {
  InMemoryLocaleRepository([this._locale]);

  AppLocale? _locale;

  @override
  Future<AppLocale?> load() async => _locale;

  @override
  Future<void> save(AppLocale locale) async => _locale = locale;
}
