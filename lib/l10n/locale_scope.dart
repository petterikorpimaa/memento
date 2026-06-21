import 'package:flutter/widgets.dart';

import 'app_strings.dart';
import 'locale_controller.dart';

/// Exposes the [LocaleController] to the widget tree.
///
/// Any widget reads the active [AppStrings] with [stringsOf] (or the controller
/// itself with [of]) and rebuilds automatically when the language changes — the
/// `InheritedNotifier` marks its dependents dirty whenever the controller
/// notifies. Place it above `MaterialApp` so pushed routes and overlays (the
/// settings page, the reminder modal) are descendants and can read it too.
class LocaleScope extends InheritedNotifier<LocaleController> {
  const LocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The controller, registering [context] to rebuild on language changes.
  static LocaleController of(BuildContext context) {
    final LocaleScope? scope = context
        .dependOnInheritedWidgetOfExactType<LocaleScope>();
    assert(scope != null, 'No LocaleScope found in context.');
    return scope!.notifier!;
  }

  /// The active strings, registering [context] to rebuild on language changes.
  static AppStrings stringsOf(BuildContext context) => of(context).strings;
}
