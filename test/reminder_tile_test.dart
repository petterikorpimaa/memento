// Verifies the tile's title is vertically centered when it has no subtitle, and
// sits above centre (leading the subtitle) when it has one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memento/models/reminder_item.dart';
import 'package:memento/widgets/reminder_tile.dart';

Future<void> _pumpContent(WidgetTester tester, ReminderItem item) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: ReminderTileContent(
              item: item,
              enabled: true,
              onBellTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

ReminderItem _alarm(String subtitle) => ReminderItem(
  title: 'Solo',
  subtitle: subtitle,
  type: ReminderType.alarm,
  date: DateTime(2026, 6, 18, 9),
);

void main() {
  testWidgets('the title is vertically centered when the subtitle is empty', (
    WidgetTester tester,
  ) async {
    await _pumpContent(tester, _alarm(''));

    final double titleCenter = tester.getCenter(find.text('Solo')).dy;
    final double bellCenter = tester
        .getCenter(find.byIcon(Icons.notifications_none_rounded))
        .dy;
    expect((titleCenter - bellCenter).abs(), lessThan(2.0));
  });

  testWidgets('the title leads (sits above centre) when a subtitle is set', (
    WidgetTester tester,
  ) async {
    await _pumpContent(tester, _alarm('Detail'));

    final double titleCenter = tester.getCenter(find.text('Solo')).dy;
    final double bellCenter = tester
        .getCenter(find.byIcon(Icons.notifications_none_rounded))
        .dy;
    expect(find.text('Detail'), findsOneWidget);
    expect(titleCenter, lessThan(bellCenter - 5));
  });
}
