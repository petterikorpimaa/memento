import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import 'reminder_repository.dart';
import 'reminder_state.dart';

/// A [ReminderRepository] backed by `shared_preferences`, storing the whole
/// snapshot as a single JSON string. Available on every target platform.
class SharedPreferencesReminderRepository implements ReminderRepository {
  SharedPreferencesReminderRepository(this._prefs);

  /// The single key the JSON snapshot is stored under.
  static const String _key = 'reminders_state_v1';

  final SharedPreferences _prefs;

  /// Opens shared preferences and wraps it in a repository.
  static Future<SharedPreferencesReminderRepository> create() async =>
      SharedPreferencesReminderRepository(
        await SharedPreferences.getInstance(),
      );

  @override
  Future<ReminderState> load() async {
    final String? raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return ReminderState.empty();
    try {
      return ReminderState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error, stackTrace) {
      developer.log(
        'Could not decode stored reminders; starting empty.',
        name: 'memento.persistence',
        error: error,
        stackTrace: stackTrace,
      );
      return ReminderState.empty();
    }
  }

  @override
  Future<void> save(ReminderState state) =>
      _prefs.setString(_key, jsonEncode(state.toJson()));
}
