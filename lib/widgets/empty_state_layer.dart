import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../constants/app_durations.dart';
import '../models/reminder_item.dart';
import 'emerging_reminder_tile.dart';
import 'empty_reminders_state.dart';
import 'reminder_tile.dart';

/// The "all clear" empty state, crossfaded in over the (now contentless) list
/// whenever every reminder has been removed and out again the moment one is
/// added. It only exists in the tree while empty, so its continuous float/pulse
/// animations never run behind a populated list.
///
/// It also hosts the add-from-empty tile on its "New reminder" button: stage 1
/// ([EmergingReminderTile]) morphs the "+" into a tile; stage 2 is a real
/// [ReminderTile] that plays the "closer" lean and hands off into the modal
/// (keyed via [addOriginKey] so the modal grows from that exact spot). The
/// `host*` fields describe that reminder and are null/unused when no add is in
/// flight ([hostId] == null).
class EmptyStateLayer extends StatelessWidget {
  const EmptyStateLayer({
    super.key,
    required this.isEmpty,
    required this.hostId,
    required this.addingId,
    required this.addAnimation,
    required this.hostItem,
    required this.hostEnabled,
    required this.hostExpanded,
    required this.hostChipRemaining,
    required this.addOriginKey,
    required this.addTileWidth,
    required this.addTileHeight,
    required this.firstLaunch,
    required this.compact,
    required this.onAdd,
    required this.onToggleHost,
    required this.onExpandHost,
    required this.onExpandHostComplete,
  });

  /// Whether the list is currently empty — drives the crossfade.
  final bool isEmpty;

  /// The id of a reminder being added from the empty state, or null.
  final int? hostId;

  /// The id mid-add (used to pick the morph vs the settled tile), or null.
  final int? addingId;

  /// Drives the add morph.
  final Animation<double> addAnimation;

  /// The host reminder's data, present only while [hostId] is non-null.
  final ReminderItem? hostItem;
  final bool hostEnabled;
  final bool hostExpanded;
  final ValueListenable<Duration>? hostChipRemaining;

  /// Keys the settled add-origin tile so the modal can grow from it.
  final GlobalKey addOriginKey;
  final double addTileWidth;
  final double addTileHeight;

  /// Whether no reminder has ever been created (a richer first-launch message).
  final bool firstLaunch;
  final bool compact;

  final VoidCallback onAdd;
  final VoidCallback onToggleHost;
  final VoidCallback onExpandHost;
  final VoidCallback onExpandHostComplete;

  @override
  Widget build(BuildContext context) {
    final ReminderItem? item = hostItem;
    Widget? addingTile;
    if (hostId != null && item != null) {
      addingTile = addingId == hostId
          ? EmergingReminderTile(
              animation: addAnimation,
              item: item,
              enabled: hostEnabled,
              height: addTileHeight,
              fullWidth: addTileWidth,
              compact: compact,
              // No dashed "+" glyph on the empty state — its pill is a different
              // shape, so the tile just grows and fades in.
              showGlyph: false,
            )
          : SizedBox(
              key: addOriginKey,
              width: addTileWidth,
              height: addTileHeight,
              child: ReminderTile(
                item: item,
                enabled: hostEnabled,
                expanded: hostExpanded,
                onToggle: onToggleHost,
                onExpandTap: onExpandHost,
                onExpandComplete: onExpandHostComplete,
                compact: compact,
                chipRemaining: hostChipRemaining,
              ),
            );
    }
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: AppDurations.slow,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (Widget child, Animation<double> animation) =>
            FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
                child: child,
              ),
            ),
        child: isEmpty
            ? EmptyRemindersState(
                key: const ValueKey<String>('empty'),
                onAdd: onAdd,
                addingTile: addingTile,
                // Reserve the real row height for the add slot so the
                // pill -> morph swap doesn't shift the block.
                addSlotHeight: addTileHeight,
                firstLaunch: firstLaunch,
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
