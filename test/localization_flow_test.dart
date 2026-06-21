// End-to-end localization: switching the language from settings retranslates the
// app, persists the choice, and a restart with the saved choice starts in it.

import 'package:flutter_test/flutter_test.dart';

import 'package:memento/data/in_memory_locale_repository.dart';
import 'package:memento/l10n/app_locale.dart';
import 'package:memento/main.dart';

void main() {
  testWidgets('switching to Finnish retranslates the app and is persisted', (
    WidgetTester tester,
  ) async {
    final InMemoryLocaleRepository localeRepo = InMemoryLocaleRepository();
    await tester.pumpWidget(MyApp(localeRepository: localeRepo));
    await tester.pumpAndSettle();

    // Starts in the default language: the English header and settings button.
    expect(find.text('Reminders'), findsOneWidget);
    expect(find.text('Muistutukset'), findsNothing);

    // Open settings and pick Suomi from the language selector.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Suomi'), findsOneWidget);

    await tester.tap(find.text('Suomi'));
    await tester.pumpAndSettle();

    // The settings page itself is now in Finnish, and the choice was persisted.
    expect(find.text('Asetukset'), findsOneWidget);
    expect(await localeRepo.load(), AppLocale.finnish);

    // Back out: the reminders header is now Finnish too.
    await tester.tap(find.byTooltip('Takaisin'));
    await tester.pumpAndSettle();
    expect(find.text('Muistutukset'), findsOneWidget);
    expect(find.text('Reminders'), findsNothing);
  });

  testWidgets('an injected saved language is the startup language', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MyApp(initialLocale: AppLocale.finnish));
    await tester.pumpAndSettle();

    expect(find.text('Muistutukset'), findsOneWidget);
    expect(find.text('Reminders'), findsNothing);
  });
}
