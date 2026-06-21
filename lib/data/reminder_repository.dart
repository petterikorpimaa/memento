import 'reminder_state.dart';

/// Loads and stores the whole reminder snapshot.
///
/// The screen always rewrites the full [ReminderState] (it is the single owner
/// of that state), so the repository deals in whole snapshots rather than
/// per-row CRUD. Implementations: `SharedPreferencesReminderRepository` for the
/// device, `InMemoryReminderRepository` for tests and the in-app demo seed.
abstract interface class ReminderRepository {
  /// Reads the stored snapshot, or [ReminderState.empty] when nothing is saved.
  Future<ReminderState> load();

  /// Persists [state], replacing any previously stored snapshot.
  Future<void> save(ReminderState state);
}
