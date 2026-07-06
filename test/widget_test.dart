import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stadiumly/main.dart';

void main() {
  testWidgets('shows the waypoint map shell', (WidgetTester tester) async {
    await tester.pumpWidget(const StadiumlyApp());

    expect(find.text('Mazowieckie'), findsOneWidget);
    expect(find.text('Visited in Wojewodztwo'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Woj'), findsOneWidget);
    expect(find.text('Powiat'), findsOneWidget);
    expect(find.text('Gmina'), findsOneWidget);
    expect(find.text('Waypoints'), findsOneWidget);
    expect(find.text('National Stadium'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);
    expect(find.byTooltip('Selected location'), findsNothing);
  });

  testWidgets('switches visited counter scope', (WidgetTester tester) async {
    await tester.pumpWidget(const StadiumlyApp());

    await tester.tap(find.text('Powiat'));
    await tester.pump();

    expect(find.text('Visited in Powiat'), findsOneWidget);
    expect(find.text('Warszawa'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.text('Gmina'));
    await tester.pump();

    expect(find.text('Visited in Gmina'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('creates an object from manual coordinates', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const StadiumlyApp());

    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);

    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Selected location'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Manual Gate',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Category'),
      'Entrance',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Latitude'),
      '52.240000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Longitude'),
      '21.040000',
    );
    await tester.scrollUntilVisible(
      find.text('Create'),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Create'));
    await tester.pump();

    expect(find.text('4 objects'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Manual Gate'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Manual Gate'), findsOneWidget);
  });
}
