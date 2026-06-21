part of 'reminder_modal.dart';

/// The editable detail below the modal divider: a title and a description text
/// field, seeded from the reminder. Once [animation] runs (the parent starts it
/// after the modal has expanded) the fields rise into place and fade in, each
/// staggered so the top one leads and the next begins halfway through it.
///
/// Stateful so the [TextEditingController]s outlive the per-frame rebuilds of
/// the enclosing modal; edits are pushed up live via the change callbacks.
class _ReminderEditFields extends StatefulWidget {
  const _ReminderEditFields({
    required this.item,
    required this.animation,
    required this.onTitleChanged,
    required this.onSubtitleChanged,
    required this.onTypeChanged,
    required this.onDateChanged,
    required this.onDurationChanged,
  });

  final ReminderItem item;
  final Animation<double> animation;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onSubtitleChanged;
  final ValueChanged<ReminderType> onTypeChanged;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<Duration> onDurationChanged;

  /// Gap above the field block (below the divider).
  static const double _topGap = 18;

  @override
  State<_ReminderEditFields> createState() => _ReminderEditFieldsState();
}

class _ReminderEditFieldsState extends State<_ReminderEditFields> {
  // Seeded once from the reminder. Later edits commit upward, so the parent's
  // updated item never needs to (and must not) reseed these mid-typing.
  late final TextEditingController _title = TextEditingController(
    text: widget.item.title,
  );
  late final TextEditingController _subtitle = TextEditingController(
    text: widget.item.subtitle,
  );

  /// Whether the heavy field block (text fields, segmented control and — the
  /// expensive part — the Cupertino date/time/duration pickers) has been built
  /// yet. Held back until the reveal animation actually starts.
  ///
  /// The enclosing card is rebuilt on every frame of the open *morph* (its
  /// position/size are animated), so without this gate the pickers would be
  /// constructed ~60×/s during the open — and first built on the very frame the
  /// morph starts, spiking that frame. But the fields stay fully transparent
  /// until [widget.animation] (the parent's fields controller) starts, which is
  /// only after the morph completes. So defer building them until then: during
  /// the morph this whole block is a zero-size box, and the pickers are built
  /// exactly once, while the card is stationary.
  bool _revealStarted = false;

  @override
  void initState() {
    super.initState();
    widget.animation.addListener(_onRevealTick);
    _onRevealTick();
  }

  @override
  void didUpdateWidget(_ReminderEditFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animation != oldWidget.animation) {
      oldWidget.animation.removeListener(_onRevealTick);
      widget.animation.addListener(_onRevealTick);
      _onRevealTick();
    }
  }

  /// Builds the fields the first time the reveal animation leaves rest, then
  /// stops listening — once built they stay built (so they animate back out on
  /// close too).
  void _onRevealTick() {
    if (_revealStarted || widget.animation.value == 0) return;
    widget.animation.removeListener(_onRevealTick);
    setState(() => _revealStarted = true);
  }

  @override
  void dispose() {
    widget.animation.removeListener(_onRevealTick);
    _title.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  /// How much each successive field overlaps the previous one's reveal: 0.5
  /// means a field starts when the one above is halfway through. Smaller -> more
  /// cascade; larger -> closer to simultaneous.
  static const double _stagger = 0.5;

  /// The eased sub-window of [widget.animation] over which field [index] (of
  /// [count]) reveals. Windows are equal length and overlap by [_stagger], with
  /// the last one ending exactly at 1, so the whole cascade fills the run.
  Interval _revealFor(int index, int count) {
    final double span = 1 / ((count - 1) * (1 - _stagger) + 1);
    final double start = index * span * (1 - _stagger);
    return Interval(start, start + span, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    // Built lazily: during the open morph (when these are invisible anyway) this
    // is a zero-size box, keeping the expensive pickers out of the per-frame
    // rebuild and off the morph's first frame. See [_revealStarted].
    if (!_revealStarted) return const SizedBox.shrink();
    final AppStrings strings = LocaleScope.stringsOf(context);
    final List<Widget> fields = <Widget>[
      _EditField(
        hint: strings.titleHint,
        controller: _title,
        onChanged: widget.onTitleChanged,
        style: const TextStyle(
          color: Color(0xFFF4F6FA),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      _EditField(
        hint: strings.descriptionHint,
        controller: _subtitle,
        onChanged: widget.onSubtitleChanged,
        style: const TextStyle(
          color: Color(0xFFD7DCE5),
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
      ),
      // Reflects the reminder's type live (it is controlled by the parent, not
      // seeded like the text fields), so picking a segment commits immediately.
      PillSegmentedControl<ReminderType>(
        value: widget.item.type,
        onChanged: widget.onTypeChanged,
        segments: <PillSegment<ReminderType>>[
          PillSegment<ReminderType>(
            value: ReminderType.alarm,
            label: strings.alertLabel,
            icon: Icons.alarm_rounded,
            color: ReminderColors.teal,
          ),
          PillSegment<ReminderType>(
            value: ReminderType.timer,
            label: strings.timerLabel,
            icon: Icons.timer_rounded,
            color: ReminderColors.pink,
          ),
        ],
      ),
      // Date/time controls for an alarm, or the duration control for a timer,
      // sitting beneath the Alert/Timer control. Each button reveals an inline
      // picker; the section owns the reveal / slide / collapse choreography, and
      // slides between the alarm and timer controls as the type changes (see
      // [_DateTimeSection]).
      _DateTimeSection(
        type: widget.item.type,
        initialDate: widget.item.date,
        initialTime: widget.item.time,
        onDateChanged: widget.onDateChanged,
        onDurationChanged: widget.onDurationChanged,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: _ReminderEditFields._topGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < fields.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 14),
            _StaggeredReveal(
              animation: widget.animation,
              curve: _revealFor(i, fields.length),
              child: fields[i],
            ),
          ],
        ],
      ),
    );
  }
}

/// Reveals its [child] over the slice of [animation] described by [curve]: the
/// child fades in while sliding up into place. Used to stagger the modal's edit
/// fields — give each one a later [Interval] and they cascade.
class _StaggeredReveal extends StatelessWidget {
  const _StaggeredReveal({
    required this.animation,
    required this.curve,
    required this.child,
  });

  final Animation<double> animation;
  final Curve curve;
  final Widget child;

  /// How far below its resting spot the child starts, in logical pixels.
  static const double _rise = 12;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      // Built once; only the opacity/offset wrapper rebuilds each tick.
      child: child,
      builder: (BuildContext context, Widget? child) {
        final double t = curve.transform(animation.value).clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * _rise),
            child: child,
          ),
        );
      },
    );
  }
}

/// One text field in the modal's edit section: a borderless input sunk into the
/// glass. There is no caption — [hint] shows as placeholder text while the field
/// is empty. The dark, translucent fill plus a painted inset shadow (dark along
/// the top-left, a light catch along the bottom-right) make it read as a well
/// pressed into the surface.
class _EditField extends StatelessWidget {
  const _EditField({
    required this.hint,
    required this.controller,
    required this.onChanged,
    required this.style,
  });

  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final TextStyle style;

  static const double _radius = 12;
  static const Color _hintColor = Color(0xFF767E8B);

  /// Darker, translucent fill so the input reads as a recess in the glass.
  static const Color _fill = Color.fromARGB(82, 6, 8, 13);

  /// The recess walls: a near-black shadow catching the top-left and a faint
  /// cool highlight on the bottom-right, under a top-left light.
  static const Color _shadowDark = Color(0x80000000);
  static const Color _shadowLight = Color(0x1DFFFFFF);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_radius),
      child: CustomPaint(
        // Painted behind the field's text: the fill and the inset shadows.
        painter: _NeumorphicInset(
          radius: _radius,
          fill: _fill,
          shadowDark: _shadowDark,
          shadowLight: _shadowLight,
          blur: 2.5,
          offset: 1.5,
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: style,
          cursorColor: ReminderColors.teal,
          // Start the soft keyboard shifted, so the first letter is capitalised.
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: hint,
            hintStyle: style.copyWith(color: _hintColor),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a translucent fill plus a faked *inset* shadow, so a shape reads as
/// pressed into its surface. Flutter's [BoxShadow] only casts outward, so each
/// inset edge is drawn here instead: clip to the rounded rect, then fill the
/// area *outside* a copy of that rect nudged toward one corner — the blurred
/// edge of that fill bleeds inward as a soft shadow hugging the opposite walls.
/// A dark nudge down-right shadows the top-left; a light nudge up-left catches
/// the bottom-right, together giving the recessed look under a top-left light.
class _NeumorphicInset extends CustomPainter {
  _NeumorphicInset({
    required this.radius,
    required this.fill,
    required this.shadowDark,
    required this.shadowLight,
    required this.blur,
    required this.offset,
  });

  final double radius;
  final Color fill;
  final Color shadowDark;
  final Color shadowLight;
  final double blur;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRRect(rrect, Paint()..color = fill);

    canvas.save();
    canvas.clipRRect(rrect);
    _edge(canvas, size, rrect, shadowDark, Offset(offset, offset));
    _edge(canvas, size, rrect, shadowLight, Offset(-offset, -offset));
    canvas.restore();
  }

  /// Fills everything outside [rrect] shifted by [d] with a blurred [color];
  /// clipped to [rrect], only the soft inward bleed shows, as an inset shadow on
  /// the walls opposite the shift.
  void _edge(Canvas canvas, Size size, RRect rrect, Color color, Offset d) {
    final Paint paint = Paint()
      ..color = color
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    final Path path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(
        Rect.fromLTRB(
          -size.width,
          -size.height,
          size.width * 2,
          size.height * 2,
        ),
      )
      ..addRRect(rrect.shift(d));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_NeumorphicInset old) =>
      old.radius != radius ||
      old.fill != fill ||
      old.shadowDark != shadowDark ||
      old.shadowLight != shadowLight ||
      old.blur != blur ||
      old.offset != offset;
}
