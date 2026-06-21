import 'package:flutter/material.dart';

import '../data/in_memory_reminder_repository.dart';
import '../data/reminder_repository.dart';
import '../data/reminder_state.dart';
import '../notifications/notification_service.dart';
import '../notifications/noop_notification_service.dart';
import '../widgets/app_page.dart';
import 'reminders_screen.dart';
import 'settings_screen.dart';

/// Application shell: a single full-height reminders page. The old bottom tab
/// bar is gone — settings is reached from a button in the list header, which
/// pushes the [SettingsScreen] onto the app's navigator.
///
/// Owns the app-level [_compactView] flag because it is the one place that
/// builds both screens: the reminders list reads it to render its compact
/// layout, and the settings page flips it. Also resolves the data + notification
/// dependencies once and threads them into the list.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.repository, this.notificationService});

  /// The persistent store. Null falls back to an in-memory repository seeded
  /// with the demo reminders (see [MyApp]).
  final ReminderRepository? repository;

  /// The OS notification backend. Null falls back to a no-op service.
  final NotificationService? notificationService;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Whether reminders render in their compact layout (smaller bells, no
  /// subtitle, shorter rows). A single boolean shared across two screens, so a
  /// [ValueNotifier] fits: the settings pill writes it, the list listens.
  final ValueNotifier<bool> _compactView = ValueNotifier<bool>(false);

  /// Resolve the dependencies once: injected ones in production, sensible
  /// fallbacks (demo data + no-op notifications) when none are supplied.
  late final ReminderRepository _repository =
      widget.repository ??
      InMemoryReminderRepository(ReminderState.fromKReminders());
  late final NotificationService _notificationService =
      widget.notificationService ?? const NoopNotificationService();

  @override
  void dispose() {
    _compactView.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      child: RemindersScreen(
        repository: _repository,
        notificationService: _notificationService,
        compactView: _compactView,
        onOpenSettings: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                SettingsScreen(compactView: _compactView),
          ),
        ),
      ),
    );
  }
}
