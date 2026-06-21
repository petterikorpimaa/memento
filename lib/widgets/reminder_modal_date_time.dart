part of 'reminder_modal.dart';

/// Which control in the section is selected (also which button is lit). The
/// pickers can't be closed, so one is always selected.
enum _Picker { date, time, timer }

/// The timing controls in the modal's edit section, sitting beneath the
/// Alert/Timer control. Which controls show depends on the reminder's
/// [ReminderItem.type]:
///  * an **alarm** shows a Date and a Time button over an always-open
///    [CupertinoDatePicker] — the Time picker is selected by default;
///  * a **timer** shows a single Duration button over an always-open
///    hours / minutes / seconds picker styled to match (see [_DurationPicker]).
///
/// The pickers can't be dismissed; the buttons only switch between them:
///  * **Switch** ([_page]) — tapping Date or Time slides the picker content
///    horizontally between the two (date on the left, time on the right).
///  * **Type** ([_mode]) — switching between alarm and timer slides both the
///    button area and the picker area across with a crossfade.
///
/// Both [_page] and [_mode] are driven with `animateTo(curve: easeOutCubic)`,
/// so every slide — to date, to time, to timer, back to alarm — decelerates
/// into its destination with the exact same feel.
///
/// Each picker carries a reset button (top-right) that returns it to a sensible
/// value: the date to today, the time to now, the duration to 5 minutes
/// ([CupertinoDatePicker] is uncontrolled, so a reset rebuilds it at the new
/// value). The picked values are held locally — they drive the button labels —
/// and are also reported up live ([onDateChanged] / [onDurationChanged]) so the
/// reminder's [ReminderItem.date] / [ReminderItem.time] tracks the wheels. Each
/// callback only fires for the type whose pickers are showing (dates from the
/// alarm pickers, durations from the timer picker), so the screen commits with a
/// plain [ReminderItem.copyWith] and the alarm/timer invariant is never at risk.
class _DateTimeSection extends StatefulWidget {
  const _DateTimeSection({
    required this.type,
    required this.onDateChanged,
    required this.onDurationChanged,
    this.initialDate,
    this.initialTime,
  });

  /// The reminder's type, picking which controls show (and animating between
  /// them when it changes).
  final ReminderType type;

  /// Reports the picked alarm date/time up so the reminder tracks it. Fired only
  /// while the alarm pickers show, so the value always describes an alarm.
  final ValueChanged<DateTime> onDateChanged;

  /// Reports the picked timer length up so the reminder tracks it. Fired only
  /// while the timer picker shows, so the value always describes a timer.
  final ValueChanged<Duration> onDurationChanged;

  /// Seeds the date/time pickers. Null (a timer carries no date) falls back to
  /// the current time.
  final DateTime? initialDate;

  /// Seeds the duration picker. Null (an alarm carries no duration) falls back
  /// to a default length.
  final Duration? initialTime;

  @override
  State<_DateTimeSection> createState() => _DateTimeSectionState();
}

class _DateTimeSectionState extends State<_DateTimeSection>
    with TickerProviderStateMixin {
  /// The date/time the alarm pickers edit, seeded once. Drives the labels.
  late DateTime _selected = widget.initialDate ?? DateTime.now();

  /// The duration the timer picker edits, seeded once.
  late Duration _duration = widget.initialTime ?? const Duration(minutes: 5);

  /// Which button is lit / which picker shows.
  late _Picker _open = widget.type == ReminderType.timer
      ? _Picker.timer
      : _Picker.time;

  /// Horizontal position of the alarm pager: 0 == time, 1 == date. Time sits on
  /// the left, so it is the default (value 0).
  late final AnimationController _page = AnimationController(
    vsync: this,
    duration: AppDurations.normal,
    value: 0,
  );

  /// Horizontal position of the section: 0 == alarm controls, 1 == timer.
  late final AnimationController _mode = AnimationController(
    vsync: this,
    duration: AppDurations.normal,
    value: widget.type == ReminderType.timer ? 1 : 0,
  );

  /// Bumped to rebuild a picker at its reset value (the pickers are
  /// uncontrolled, so a changed key reseeds them).
  int _dateTick = 0;
  int _timeTick = 0;
  int _timerTick = 0;

  /// Gap between the buttons and the always-open picker.
  static const double _innerGap = 12;

  /// Height of the inline picker.
  static const double _pickerHeight = 190;

  @override
  void didUpdateWidget(_DateTimeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.type != oldWidget.type) {
      // Slide the section across to the new type's controls. The picker can't
      // be closed, so the destination always lands on an open picker.
      if (widget.type == ReminderType.timer) {
        _open = _Picker.timer;
      } else {
        _open = _Picker.time; // Time is the default alarm picker (left).
        _page.value = 0;
      }
      _mode.animateTo(
        widget.type == ReminderType.timer ? 1 : 0,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _page.dispose();
    _mode.dispose();
    super.dispose();
  }

  void _select(_Picker picker) {
    // Pickers can't be closed, so re-tapping the open one is a no-op.
    if (_open == picker) return;
    setState(() => _open = picker);
    if (picker == _Picker.time) {
      _page.animateTo(0, curve: Curves.easeOutCubic);
    } else if (picker == _Picker.date) {
      _page.animateTo(1, curve: Curves.easeOutCubic);
    }
  }

  /// "24.5.2026" — day.month.year, no leading zeros.
  String _dateLabel() =>
      '${_selected.day}.${_selected.month}.${_selected.year}';

  /// "14:30" — 24-hour, zero-padded.
  String _timeLabel() => '${_two(_selected.hour)}:${_two(_selected.minute)}';

  /// The duration, dropping the "0:" hours part when there are no hours:
  /// "05:00" with no hours, "1:05:00" with.
  String _durationLabel() {
    final int h = _duration.inHours;
    final String m = _two(_duration.inMinutes.remainder(60));
    final String s = _two(_duration.inSeconds.remainder(60));
    return h == 0 ? '$m:$s' : '$h:$m:$s';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buttons(),
        const SizedBox(height: _innerGap),
        _pickerArea(),
      ],
    );
  }

  /// The button area: the alarm controls (Date + Time) and the timer control
  /// (Duration) cross-slid by [_mode].
  Widget _buttons() {
    return AnimatedBuilder(
      animation: _mode,
      builder: (BuildContext context, _) {
        final double m = _mode.value;
        return ClipRect(
          child: SizedBox(
            height: _DateTimeButton.height,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final double w = constraints.maxWidth;
                return Stack(
                  children: <Widget>[
                    if (m < 1)
                      Opacity(
                        key: const ValueKey<String>('alarm-buttons'),
                        opacity: (1 - m).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(-m * w, 0),
                          child: IgnorePointer(
                            ignoring: m > 0.5,
                            child: SizedBox(width: w, child: _alarmButtons()),
                          ),
                        ),
                      ),
                    if (m > 0)
                      Opacity(
                        key: const ValueKey<String>('timer-button'),
                        opacity: m.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset((1 - m) * w, 0),
                          child: IgnorePointer(
                            ignoring: m <= 0.5,
                            child: SizedBox(width: w, child: _timerButton()),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _alarmButtons() {
    return Row(
      children: <Widget>[
        Expanded(
          child: _DateTimeButton(
            icon: Icons.hourglass_empty_rounded,
            label: _timeLabel(),
            active: _open == _Picker.time,
            accent: ReminderColors.teal,
            onTap: () => _select(_Picker.time),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _DateTimeButton(
            icon: Icons.event_rounded,
            label: _dateLabel(),
            active: _open == _Picker.date,
            accent: ReminderColors.blue,
            onTap: () => _select(_Picker.date),
          ),
        ),
      ],
    );
  }

  Widget _timerButton() {
    return _DateTimeButton(
      icon: Icons.av_timer_rounded,
      label: _durationLabel(),
      active: _open == _Picker.timer,
      accent: ReminderColors.pink,
      onTap: () => _select(_Picker.timer),
    );
  }

  /// The always-open picker area: the alarm pager (date/time) and the timer
  /// picker, cross-slid by [_mode] to match the buttons.
  Widget _pickerArea() {
    return SizedBox(
      height: _pickerHeight,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_page, _mode]),
        builder: (BuildContext context, _) {
          final double m = _mode.value;
          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double w = constraints.maxWidth;
              return ClipRect(
                child: Stack(
                  children: <Widget>[
                    if (m < 1)
                      Opacity(
                        key: const ValueKey<String>('alarm-picker'),
                        opacity: (1 - m).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(-m * w, 0),
                          child: SizedBox(
                            width: w,
                            height: _pickerHeight,
                            child: _alarmPager(w),
                          ),
                        ),
                      ),
                    if (m > 0)
                      Opacity(
                        key: const ValueKey<String>('timer-picker'),
                        opacity: m.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset((1 - m) * w, 0),
                          child: SizedBox(
                            width: w,
                            height: _pickerHeight,
                            child: _timerCard(),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// The time and date pickers, slid horizontally between by [_page]. Time is
  /// the left page (pos 0), date the right page (pos 1).
  Widget _alarmPager(double w) {
    final double pos = _page.value;
    return ClipRect(
      child: Stack(
        children: <Widget>[
          if (pos < 1)
            Transform.translate(
              key: const ValueKey<String>('time-card'),
              offset: Offset(-pos * w, 0),
              child: SizedBox(
                width: w,
                height: _pickerHeight,
                child: _timeCard(),
              ),
            ),
          if (pos > 0)
            Transform.translate(
              key: const ValueKey<String>('date-card'),
              offset: Offset((1 - pos) * w, 0),
              child: SizedBox(
                width: w,
                height: _pickerHeight,
                child: _dateCard(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateCard() => _PickerWell(
    onReset: _resetDate,
    child: CupertinoTheme(
      data: const CupertinoThemeData(brightness: Brightness.dark),
      child: CupertinoDatePicker(
        // A changed key reseeds this (uncontrolled) picker on reset.
        key: ValueKey<String>('date-$_dateTick'),
        mode: CupertinoDatePickerMode.date,
        initialDateTime: _selected,
        // The reminder can only be scheduled this year or later.
        minimumYear: DateTime.now().year,
        onDateTimeChanged: _onDatePicked,
      ),
    ),
  );

  Widget _timeCard() => _PickerWell(
    onReset: _resetTime,
    child: CupertinoTheme(
      data: const CupertinoThemeData(brightness: Brightness.dark),
      child: CupertinoDatePicker(
        key: ValueKey<String>('time-$_timeTick'),
        mode: CupertinoDatePickerMode.time,
        use24hFormat: true,
        initialDateTime: _selected,
        onDateTimeChanged: _onTimePicked,
      ),
    ),
  );

  Widget _timerCard() => _PickerWell(
    onReset: _resetTimer,
    child: _DurationPicker(
      key: ValueKey<int>(_timerTick),
      initialDuration: _duration,
      onChanged: (Duration value) {
        setState(() => _duration = value);
        widget.onDurationChanged(value);
      },
    ),
  );

  /// Keeps the time, replacing only the day (the date picker owns the day).
  void _onDatePicked(DateTime value) {
    setState(() {
      _selected = DateTime(
        value.year,
        value.month,
        value.day,
        _selected.hour,
        _selected.minute,
      );
    });
    widget.onDateChanged(_selected);
  }

  /// Keeps the day, replacing only the time (the time picker owns the time).
  void _onTimePicked(DateTime value) {
    setState(() {
      _selected = DateTime(
        _selected.year,
        _selected.month,
        _selected.day,
        value.hour,
        value.minute,
      );
    });
    widget.onDateChanged(_selected);
  }

  void _resetDate() {
    final DateTime now = DateTime.now();
    setState(() {
      _selected = DateTime(
        now.year,
        now.month,
        now.day,
        _selected.hour,
        _selected.minute,
      );
      _dateTick++;
    });
    widget.onDateChanged(_selected);
  }

  void _resetTime() {
    final DateTime now = DateTime.now();
    setState(() {
      _selected = DateTime(
        _selected.year,
        _selected.month,
        _selected.day,
        now.hour,
        now.minute,
      );
      _timeTick++;
    });
    widget.onDateChanged(_selected);
  }

  void _resetTimer() {
    setState(() {
      _duration = const Duration(minutes: 5);
      _timerTick++;
    });
    widget.onDurationChanged(_duration);
  }
}

/// One of the section's pill buttons: matches the modal's other controls, lit
/// with its [accent] while its picker is selected. No glow — a flat pill.
class _DateTimeButton extends StatelessWidget {
  const _DateTimeButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  /// Outer height, shared with the button area that cross-slides them.
  static const double height = 46;
  static const Color _offFill = Color(0x33000000);
  static const Color _offBorder = Color(0x14FFFFFF);
  static const Color _muted = Color(0xFF8A93A0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Ease the lit/unlit transition (fill, rim and content colour) on one
      // driver, the same idiom the segmented control and toggles use.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: active ? 1 : 0),
        duration: AppDurations.fast,
        curve: Curves.easeOut,
        builder: (BuildContext context, double t, _) {
          final Color content = Color.lerp(_muted, accent, t)!;
          return Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Color.lerp(_offFill, accent.withValues(alpha: 0.18), t),
              borderRadius: BorderRadius.circular(height / 2),
              border: Border.all(
                color: Color.lerp(
                  _offBorder,
                  accent.withValues(alpha: 0.5),
                  t,
                )!,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 18, color: content),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: content,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The timer's duration picker: three wheels — hours (0–99), minutes and
/// seconds (0–59) — built from [CupertinoPicker] with the exact item extent,
/// magnification and squeeze a [CupertinoDatePicker] uses, plus its
/// date-time-picker text style, so it reads as the same kind of wheel. A small
/// unit label (h/m/s) rides the centre band of each column.
///
/// Owns its wheel controllers (seeded from [initialDuration]) so they survive
/// the section's per-frame rebuilds; a reset is a fresh instance via a changed
/// key (matching the date/time pickers, which can only reset by rebuilding).
class _DurationPicker extends StatefulWidget {
  const _DurationPicker({
    super.key,
    required this.initialDuration,
    required this.onChanged,
  });

  final Duration initialDuration;
  final ValueChanged<Duration> onChanged;

  @override
  State<_DurationPicker> createState() => _DurationPickerState();
}

class _DurationPickerState extends State<_DurationPicker> {
  late final FixedExtentScrollController _hours = FixedExtentScrollController(
    initialItem: widget.initialDuration.inHours.clamp(0, 99),
  );
  late final FixedExtentScrollController _minutes = FixedExtentScrollController(
    initialItem: widget.initialDuration.inMinutes.remainder(60),
  );
  late final FixedExtentScrollController _seconds = FixedExtentScrollController(
    initialItem: widget.initialDuration.inSeconds.remainder(60),
  );

  // Matched to CupertinoDatePicker's own wheel metrics.
  static const double _itemExtent = 32;
  static const double _magnification = 2.35 / 2.1;
  static const double _squeeze = 1.25;
  static const Color _unitColor = Color(0xFF8A93A0);

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      Duration(
        hours: _hours.selectedItem,
        minutes: _minutes.selectedItem,
        seconds: _seconds.selectedItem,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTheme(
      data: const CupertinoThemeData(brightness: Brightness.dark),
      child: Row(
        children: <Widget>[
          Expanded(child: _wheel(context, _hours, 100, 'h')),
          Expanded(child: _wheel(context, _minutes, 60, 'm')),
          Expanded(child: _wheel(context, _seconds, 60, 's')),
        ],
      ),
    );
  }

  Widget _wheel(
    BuildContext context,
    FixedExtentScrollController controller,
    int count,
    String unit,
  ) {
    final TextStyle style = CupertinoTheme.of(
      context,
    ).textTheme.dateTimePickerTextStyle;
    return Stack(
      children: <Widget>[
        CupertinoPicker.builder(
          scrollController: controller,
          itemExtent: _itemExtent,
          squeeze: _squeeze,
          magnification: _magnification,
          useMagnifier: true,
          onSelectedItemChanged: (_) => _emit(),
          childCount: count,
          itemBuilder: (BuildContext context, int index) => Center(
            child: Text(index.toString().padLeft(2, '0'), style: style),
          ),
        ),
        // Unit label pinned to the centre selection band, just right of the
        // number; ignores pointers so it never blocks the wheel.
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: const Alignment(0.62, 0),
              child: Text(
                unit,
                style: style.copyWith(fontSize: 14, color: _unitColor),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The dark rounded well the pickers sit in (matching the modal's text fields),
/// with a reset button pinned to the top-right corner.
class _PickerWell extends StatelessWidget {
  const _PickerWell({required this.child, required this.onReset});

  final Widget child;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: const Color.fromARGB(82, 6, 8, 13),
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: child),
            Positioned(top: 6, right: 6, child: _ResetButton(onTap: onReset)),
          ],
        ),
      ),
    );
  }
}

/// A small round reset button pinned to a picker's top-right corner. Its
/// anti-clockwise replay glyph reads as "put it back".
class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0x59000000),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x1FFFFFFF)),
        ),
        child: const Icon(
          Icons.replay_rounded,
          size: 17,
          color: Color(0xFFB7C0CC),
        ),
      ),
    );
  }
}
