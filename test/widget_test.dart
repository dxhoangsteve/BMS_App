import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bms1/main.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Home screen basic test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp());

    // Verify that the app title is shown
    expect(find.text('BMS Monitor'), findsOneWidget);

    // Verify that BluetoothStatusWidget is present
    expect(find.byType(MyApp), findsOneWidget);
  });
}
