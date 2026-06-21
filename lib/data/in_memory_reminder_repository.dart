import 'reminder_repository.dart';
import 'reminder_state.dart';

/// A [ReminderRepository] that keeps the snapshot in memory only.
///
/// Two uses: as a test seam (seed it with a known [ReminderState] and assert on
/// what gets saved), and as the default when no repository is injected — `const
/// MyApp()` falls back to one seeded with the demo reminders, so the widget
/// tests keep seeing the seed data while production wires the persistent
/// repository in `main`.
class InMemoryReminderRepository implements ReminderRepository {
  InMemoryReminderRepository([ReminderState? initial])
    : _state = initial ?? ReminderState.empty();

  ReminderState _state;

  @override
  Future<ReminderState> load() async => _state;

  @override
  Future<void> save(ReminderState state) async => _state = state;
}
