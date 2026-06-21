import '../l10n/app_locale.dart';

/// Persists the user's chosen [AppLocale] across launches.
///
/// Mirrors [ReminderRepository] so the app's two persisted concerns share one
/// shape: an interface with a `shared_preferences` implementation in production
/// and an in-memory one for tests.
abstract class LocaleRepository {
  /// The saved language, or null when the user has never chosen one.
  Future<AppLocale?> load();

  /// Persists [locale] as the user's chosen language.
  Future<void> save(AppLocale locale);
}
