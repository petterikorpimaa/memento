import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/in_memory_locale_repository.dart';
import 'data/locale_repository.dart';
import 'data/reminder_repository.dart';
import 'data/shared_preferences_locale_repository.dart';
import 'data/shared_preferences_reminder_repository.dart';
import 'l10n/app_locale.dart';
import 'l10n/locale_controller.dart';
import 'l10n/locale_scope.dart';
import 'notifications/local_notification_service.dart';
import 'notifications/noop_notification_service.dart';
import 'notifications/notification_service.dart';
import 'screens/home_shell.dart';
import 'widgets/app_scroll_behavior.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only — the liquid-glass layout and animations are tuned for a tall
  // single column, so lock out landscape rather than reflow for it.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Wire the persistent stores and OS notifications, then hand them to the app.
  final ReminderRepository repository =
      await SharedPreferencesReminderRepository.create();
  final LocaleRepository localeRepository =
      await SharedPreferencesLocaleRepository.create();
  final AppLocale initialLocale = await _resolveInitialLocale(localeRepository);
  final NotificationService notifications = _notificationService();
  await notifications.init();
  runApp(
    MyApp(
      repository: repository,
      notificationService: notifications,
      localeRepository: localeRepository,
      initialLocale: initialLocale,
    ),
  );
}

/// The startup language: the saved choice if there is one, otherwise the device
/// language when we ship it, falling back to [AppLocale.fallback].
Future<AppLocale> _resolveInitialLocale(LocaleRepository repository) async {
  final AppLocale? saved = await repository.load();
  if (saved != null) return saved;
  final String deviceCode =
      WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  return AppLocale.fromCode(deviceCode) ?? AppLocale.fallback;
}

/// The notification backend for this platform: the real plugin on Android/iOS,
/// a no-op everywhere else (`flutter_local_notifications` supports neither web
/// nor desktop here).
NotificationService _notificationService() =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS)
    ? LocalNotificationService()
    : const NoopNotificationService();

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.repository,
    this.notificationService,
    this.localeRepository,
    this.initialLocale,
  });

  /// The persistent store, injected by [main]. When null — e.g. a bare
  /// `const MyApp()` in tests — [HomeShell] falls back to an in-memory
  /// repository seeded with the demo reminders, so the widget tests keep seeing
  /// the seed data while production starts from whatever is on disk.
  final ReminderRepository? repository;

  /// The OS notification backend, injected by [main]. Null defaults to a no-op.
  final NotificationService? notificationService;

  /// The language store, injected by [main]. Null defaults to an in-memory one,
  /// so `const MyApp()` runs without touching disk.
  final LocaleRepository? localeRepository;

  /// The language to start in, resolved by [main] from the saved choice or the
  /// device locale. Null defaults to [AppLocale.fallback].
  final AppLocale? initialLocale;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  /// Owns the app-wide language: it has to outlive any single route, so it lives
  /// here above the navigator and is shared down through [LocaleScope].
  late final LocaleController _localeController = LocaleController(
    widget.localeRepository ?? InMemoryLocaleRepository(),
    initial: widget.initialLocale,
  );

  @override
  void dispose() {
    _localeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      controller: _localeController,
      // Rebuild MaterialApp on a language change so its `locale` flows to the
      // framework's own localizations — that is what translates the Cupertino
      // date/time pickers. Our custom UI strings still come from LocaleScope.
      // HomeShell is passed as the stable `child` so it isn't rebuilt here.
      child: ListenableBuilder(
        listenable: _localeController,
        builder: (BuildContext context, Widget? child) {
          return MaterialApp(
            onGenerateTitle: (BuildContext context) =>
                LocaleScope.stringsOf(context).appTitle,
            debugShowCheckedModeBanner: false,
            scrollBehavior: const AppScrollBehavior(),
            locale: _localeController.locale.locale,
            supportedLocales: AppLocale.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(
              brightness: Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF5EEAD4),
                brightness: Brightness.dark,
              ),
            ),
            home: child,
          );
        },
        child: HomeShell(
          repository: widget.repository,
          notificationService: widget.notificationService,
        ),
      ),
    );
  }
}
