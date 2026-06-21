// Exercises the locale repositories: the in-memory seam and the
// shared_preferences-backed store (empty load, round-trip, unknown-code reset).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:memento/data/in_memory_locale_repository.dart';
import 'package:memento/data/shared_preferences_locale_repository.dart';
import 'package:memento/l10n/app_locale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InMemoryLocaleRepository', () {
    test('starts empty unless seeded', () async {
      expect(await InMemoryLocaleRepository().load(), isNull);
      expect(
        await InMemoryLocaleRepository(AppLocale.finnish).load(),
        AppLocale.finnish,
      );
    });

    test('save then load round-trips the language', () async {
      final InMemoryLocaleRepository repo = InMemoryLocaleRepository();
      await repo.save(AppLocale.finnish);
      expect(await repo.load(), AppLocale.finnish);
    });
  });

  group('SharedPreferencesLocaleRepository', () {
    Future<SharedPreferencesLocaleRepository> repo() =>
        SharedPreferencesLocaleRepository.create();

    test('an empty store loads as null (no choice yet)', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await (await repo()).load(), isNull);
    });

    test('save then load round-trips across a fresh repository', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await (await repo()).save(AppLocale.finnish);
      expect(await (await repo()).load(), AppLocale.finnish);
    });

    test('an unrecognised stored code loads as null', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_locale_v1': 'sv',
      });
      expect(await (await repo()).load(), isNull);
    });
  });
}
