import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:anchor_alarm/main.dart';

void main() {
  testWidgets('Anchor Alarm app loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: AnchorAlarmApp(),
      ),
    );

    // Verify that the app title is displayed
    expect(find.text('Anchor Alarm'), findsWidgets);
    expect(find.text('Monitor your anchor position and get alerts'), findsOneWidget);
    expect(find.byIcon(Icons.anchor), findsOneWidget);
  });
}
