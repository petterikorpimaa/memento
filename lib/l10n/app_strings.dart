import 'app_locale.dart';

/// Every user-facing string in the app, with one immutable instance per
/// language.
///
/// This is the in-house alternative to generated `AppLocalizations`: widgets
/// read the active instance through `LocaleScope.stringsOf(context)` and rebuild
/// when the language changes. Add a string by declaring it here and
/// implementing it in every subclass — the compiler then flags any language
/// that is missing a translation.
abstract class AppStrings {
  const AppStrings();

  /// The strings for [locale].
  static AppStrings of(AppLocale locale) => switch (locale) {
    AppLocale.english => const EnglishStrings(),
    AppLocale.finnish => const FinnishStrings(),
  };

  /// Application brand name ("Memento"), shown by the OS (task switcher,
  /// recents). A proper noun, so it is intentionally the same in every language.
  String get appTitle;

  /// Reminders list header title.
  String get remindersTitle;

  /// Header subtitle reflecting how many reminders are enabled.
  String activeReminders(int count);

  /// Settings page title, and the tooltip of the button that opens it.
  String get settingsTitle;

  /// Tooltip of the settings page's back button.
  String get back;

  /// "Compact view" setting title.
  String get compactViewTitle;

  /// "Compact view" setting supporting line.
  String get compactViewDescription;

  /// "Language" setting title.
  String get languageTitle;

  /// "Language" setting supporting line.
  String get languageDescription;

  /// Empty-state headline on a genuine first launch.
  String get welcomeHeadline;

  /// Empty-state headline once the list has been cleared at least once.
  String get allClearHeadline;

  /// Empty-state explainer beneath the headline.
  String get emptyRemindersBody;

  /// Label of the "New reminder" add button.
  String get newReminder;

  /// Placeholder for the reminder title field.
  String get titleHint;

  /// Placeholder for the reminder description field.
  String get descriptionHint;

  /// "Alert" (alarm) segment label in the reminder type control.
  String get alertLabel;

  /// "Timer" segment label in the reminder type control.
  String get timerLabel;

  /// Tooltip of the header edit button when not editing.
  String get edit;

  /// Tooltip of the header button that cancels a pending edit.
  String get cancel;

  /// Tooltip of the header edit button while editing with nothing marked.
  String get done;

  /// Tooltip of the header check that commits pending deletions.
  String get confirm;
}

/// English (`en`) — the default language and fallback.
class EnglishStrings extends AppStrings {
  const EnglishStrings();

  @override
  String get appTitle => 'Memento';

  @override
  String get remindersTitle => 'Reminders';

  @override
  String activeReminders(int count) => switch (count) {
    0 => 'No active reminders',
    1 => '1 active reminder',
    _ => '$count active reminders',
  };

  @override
  String get settingsTitle => 'Settings';

  @override
  String get back => 'Back';

  @override
  String get compactViewTitle => 'Compact view';

  @override
  String get compactViewDescription =>
      'No subtitles in the list, more compact rows.';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageDescription => 'Choose the app language.';

  @override
  String get welcomeHeadline => 'Welcome';

  @override
  String get allClearHeadline => 'All clear';

  @override
  String get emptyRemindersBody =>
      'You have no reminders right now.\n'
      'Tap the button below to create your first one.';

  @override
  String get newReminder => 'New reminder';

  @override
  String get titleHint => 'Title';

  @override
  String get descriptionHint => 'Description';

  @override
  String get alertLabel => 'Alert';

  @override
  String get timerLabel => 'Timer';

  @override
  String get edit => 'Edit';

  @override
  String get cancel => 'Cancel';

  @override
  String get done => 'Done';

  @override
  String get confirm => 'Confirm';
}

/// Finnish (`fi`).
class FinnishStrings extends AppStrings {
  const FinnishStrings();

  @override
  String get appTitle => 'Memento';

  @override
  String get remindersTitle => 'Muistutukset';

  @override
  String activeReminders(int count) => switch (count) {
    0 => 'Ei aktiivisia muistutuksia',
    1 => '1 aktiivinen muistutus',
    _ => '$count aktiivista muistutusta',
  };

  @override
  String get settingsTitle => 'Asetukset';

  @override
  String get back => 'Takaisin';

  @override
  String get compactViewTitle => 'Tiivis näkymä';

  @override
  String get compactViewDescription =>
      'Ei alaotsikoita listauksessa, tiiviimmät rivit.';

  @override
  String get languageTitle => 'Kieli';

  @override
  String get languageDescription => 'Valitse sovelluksen kieli.';

  @override
  String get welcomeHeadline => 'Tervetuloa';

  @override
  String get allClearHeadline => 'Kaikki hoidettu';

  @override
  String get emptyRemindersBody =>
      'Sinulla ei ole nyt muistutuksia.\n'
      'Luo ensimmäinen napauttamalla alla olevaa painiketta.';

  @override
  String get newReminder => 'Uusi muistutus';

  @override
  String get titleHint => 'Otsikko';

  @override
  String get descriptionHint => 'Kuvaus';

  @override
  String get alertLabel => 'Hälytys';

  @override
  String get timerLabel => 'Ajastin';

  @override
  String get edit => 'Muokkaa';

  @override
  String get cancel => 'Peruuta';

  @override
  String get done => 'Valmis';

  @override
  String get confirm => 'Vahvista';
}
