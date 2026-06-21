import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../constants/app_durations.dart';

/// One option in a [PillSegmentedControl].
@immutable
class PillSegment<T> {
  const PillSegment({
    required this.value,
    required this.label,
    required this.icon,
    this.color,
  });

  /// The value reported through [PillSegmentedControl.onChanged] when picked.
  final T value;

  final String label;
  final IconData icon;

  /// Accent for this segment when active — tints the indicator and the segment's
  /// icon/label. Falls back to the theme's primary colour when null.
  final Color? color;
}

/// A controlled, pill-shaped segmented control.
///
/// The caller owns [value]; the active indicator — an accent-tinted, softly
/// glowing pill — marks the selection. It can be changed two ways:
///
/// * **Tapping** a segment reports its value and slides the indicator over.
/// * **Dragging** the indicator scrubs it freely across the track; on release
///   it snaps to the nearest segment and reports that one.
///
/// Both gestures animate the same continuous position, so the indicator's
/// slide, its accent, and each label's colour stay in lock-step throughout.
class PillSegmentedControl<T> extends StatefulWidget {
  const PillSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  }) : assert(segments.length > 0, 'Need at least one segment.');

  final List<PillSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// Key on the indicator's [Align], exposed so tests can read its position.
  @visibleForTesting
  static const Key indicatorKey = ValueKey<String>('pill-indicator');

  @override
  State<PillSegmentedControl<T>> createState() =>
      _PillSegmentedControlState<T>();
}

class _PillSegmentedControlState<T> extends State<PillSegmentedControl<T>>
    with SingleTickerProviderStateMixin {
  /// Outer height of the pill track.
  static const double _height = 46;

  /// Inset of the indicator from the track edge.
  static const double _pad = 4;

  static const Color _trackFill = Color(0x33000000);
  static const Color _trackBorder = Color(0x14FFFFFF);
  static const Color _mutedContent = Color(0xFF8A93A0);

  /// Drives the settle/slide between two integer positions.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.normal,
  );

  /// Endpoints of the current slide, in segment-index space.
  late double _from;
  late double _to;

  /// While a drag is active, the live (fractional) indicator position; null
  /// otherwise. Takes precedence over the controller-driven slide.
  double? _dragPos;

  /// Anchors for delta-based dragging, captured at drag start.
  double _dragBase = 0;
  double _dragStartDx = 0;

  int get _selectedIndex {
    final int index = widget.segments.indexWhere(
      (PillSegment<T> s) => s.value == widget.value,
    );
    return index < 0 ? 0 : index;
  }

  /// The continuous indicator position used for every visual derivation.
  double get _position {
    if (_dragPos != null) return _dragPos!;
    final double t = Curves.easeOutCubic.transform(_controller.value);
    return _from + (_to - _from) * t;
  }

  @override
  void initState() {
    super.initState();
    _from = _to = _selectedIndex.toDouble();
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(PillSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Slide to a newly committed selection — but not while dragging (the finger
    // owns the position then), and not if we are already heading there.
    final double target = _selectedIndex.toDouble();
    if (_dragPos == null && target != _to) _animateTo(target);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Animates the indicator from its current position to [target] (an index).
  void _animateTo(double target) {
    _from = _position;
    _to = target;
    _controller.forward(from: 0);
  }

  void _onDragStart(DragStartDetails details) {
    _controller.stop();
    setState(() {
      _dragBase = _position;
      _dragStartDx = details.localPosition.dx;
      _dragPos = _dragBase;
    });
  }

  void _onDragUpdate(DragUpdateDetails details, double segmentWidth) {
    final int maxIndex = widget.segments.length - 1;
    final double delta =
        (details.localPosition.dx - _dragStartDx) / segmentWidth;
    setState(() {
      _dragPos = (_dragBase + delta).clamp(0.0, maxIndex.toDouble());
    });
  }

  void _onDragEnd() {
    final int maxIndex = widget.segments.length - 1;
    final int target = _dragPos!.round().clamp(0, maxIndex);
    // Hand off from the finger to a controller-driven settle that starts exactly
    // where the drag released, so there is no jump.
    setState(() {
      _from = _dragPos!;
      _to = target.toDouble();
      _dragPos = null;
    });
    _controller.forward(from: 0);
    final T picked = widget.segments[target].value;
    if (picked != widget.value) widget.onChanged(picked);
  }

  /// Accent at the continuous position [pos], lerping between the two segments
  /// it falls between so a drag's tint tracks the slide.
  Color _accentAt(double pos, Color fallback) {
    final int lower = pos.floor().clamp(0, widget.segments.length - 1);
    final int upper = pos.ceil().clamp(0, widget.segments.length - 1);
    final Color low = widget.segments[lower].color ?? fallback;
    final Color high = widget.segments[upper].color ?? fallback;
    return Color.lerp(low, high, pos - lower) ?? low;
  }

  @override
  Widget build(BuildContext context) {
    final int count = widget.segments.length;
    final Color fallback = Theme.of(context).colorScheme.primary;
    final double innerRadius = (_height - 2 * _pad) / 2;

    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: _trackFill,
        borderRadius: BorderRadius.circular(_height / 2),
        border: Border.all(color: _trackBorder),
      ),
      // Pad only the sides: the track's full height stays tappable/draggable,
      // and the indicator is inset vertically instead (below) so the gesture
      // area reaches the very top and bottom of the pill.
      padding: const EdgeInsets.symmetric(horizontal: _pad),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double segmentWidth = constraints.maxWidth / count;
          return GestureDetector(
            // Track from the press point with no lost touch-slop, so the
            // indicator sits under the finger from the first move.
            dragStartBehavior: DragStartBehavior.down,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                _onDragUpdate(d, segmentWidth),
            onHorizontalDragEnd: (_) => _onDragEnd(),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, _) {
                final double pos = _position;
                final Color accent = _accentAt(pos, fallback);
                return Stack(
                  children: <Widget>[
                    // The active indicator: one segment wide, centred on [pos]
                    // and tinted with the accent at that position.
                    Align(
                      key: PillSegmentedControl.indicatorKey,
                      alignment: Alignment(
                        count == 1 ? 0 : -1 + 2 * pos / (count - 1),
                        0,
                      ),
                      child: FractionallySizedBox(
                        widthFactor: 1 / count,
                        heightFactor: 1,
                        // Inset the indicator vertically so the track's full
                        // height stays tappable while the pill keeps its margin.
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: _pad),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(innerRadius),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.45),
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.25),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Each segment stretches to full height so its icon+label
                    // centre vertically and the whole slot is tappable.
                    Positioned.fill(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (int i = 0; i < count; i++)
                            Expanded(
                              child: _SegmentButton<T>(
                                segment: widget.segments[i],
                                // Proximity of the indicator to this segment:
                                // 1 when centred on it, fading to 0 a slot away.
                                activation: (1 - (i - pos).abs()).clamp(
                                  0.0,
                                  1.0,
                                ),
                                accent: widget.segments[i].color ?? fallback,
                                mutedColor: _mutedContent,
                                onTap: () =>
                                    widget.onChanged(widget.segments[i].value),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// A single tappable segment: a centred icon + label whose colour eases between
/// muted (inactive) and the segment's accent (active) by [activation], so it
/// crossfades in step with the sliding indicator behind it.
class _SegmentButton<T> extends StatelessWidget {
  const _SegmentButton({
    required this.segment,
    required this.activation,
    required this.accent,
    required this.mutedColor,
    required this.onTap,
  });

  final PillSegment<T> segment;
  final double activation;
  final Color accent;
  final Color mutedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color content = Color.lerp(mutedColor, accent, activation)!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(segment.icon, size: 18, color: content),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              segment.label,
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
  }
}
