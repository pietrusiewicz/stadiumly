import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stadiumly/main.dart';

void main() {
  Future<void> pumpStadiumlyApp(WidgetTester tester) async {
    await tester.pumpWidget(const StadiumlyApp());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('draws local county boundary after selecting an object', (
    WidgetTester tester,
  ) async {
    await pumpStadiumlyApp(tester);

    await tester.tap(find.text('National Stadium'));
    await tester.pumpAndSettle();

    expect(find.text('Warszawa - 52.2394, 21.0458'), findsOneWidget);
    expect(find.textContaining('przyblizenie'), findsNothing);
  });

  testWidgets('shows the waypoint map shell', (WidgetTester tester) async {
    await pumpStadiumlyApp(tester);

    expect(find.text('Mazowieckie'), findsOneWidget);
    expect(find.text('Visited in Wojewodztwo'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('Woj'), findsOneWidget);
    expect(find.text('Powiat'), findsOneWidget);
    expect(find.text('Gmina'), findsOneWidget);
    expect(find.text('Waypoints'), findsOneWidget);
    expect(find.text('National Stadium'), findsOneWidget);
    expect(find.text('2.5 km'), findsOneWidget);
    expect(find.text('Match day - 52.2394, 21.0458'), findsNothing);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('User'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name'), findsNothing);
    expect(find.byTooltip('Selected location'), findsNothing);
  });

  testWidgets('switches visited counter scope', (WidgetTester tester) async {
    await pumpStadiumlyApp(tester);

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

  testWidgets('updates the header after selecting an object', (
    WidgetTester tester,
  ) async {
    await pumpStadiumlyApp(tester);

    await tester.tap(find.text('National Stadium'));
    await tester.pumpAndSettle();

    expect(find.text('National Stadium'), findsWidgets);
    expect(find.text('Match day - visited'), findsOneWidget);
    expect(find.text('Warszawa - 52.2394, 21.0458'), findsOneWidget);
    expect(find.text('1/3'), findsNothing);
    expect(find.text('Woj'), findsOneWidget);
    expect(find.text('Powiat'), findsOneWidget);
    expect(find.text('Gmina'), findsOneWidget);
    expect(find.byTooltip('Clear selected object'), findsOneWidget);

    await tester.tap(find.text('Gmina'));
    await tester.pumpAndSettle();

    expect(find.text('Visited in Gmina'), findsOneWidget);
    expect(find.text('Warszawa'), findsOneWidget);
    expect(find.text('National Stadium'), findsOneWidget);
    expect(find.byTooltip('Clear selected object'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Gdansk waterfront gate'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Gdansk waterfront gate'));
    await tester.pump();

    expect(find.text('Gdansk waterfront gate'), findsWidgets);
    expect(find.text('Away trip - not visited'), findsOneWidget);
    expect(find.text('Gdansk - 54.3520, 18.6466'), findsOneWidget);
    expect(find.text('0/1'), findsNothing);

    await tester.tap(find.byTooltip('Clear selected object'));
    await tester.pump();

    expect(find.text('Gdansk'), findsOneWidget);
    expect(find.text('0/1'), findsOneWidget);
    expect(find.text('Woj'), findsOneWidget);
    expect(find.text('Powiat'), findsOneWidget);
    expect(find.text('Gmina'), findsOneWidget);
  });

  testWidgets('keeps the selected object context when switching to province', (
    WidgetTester tester,
  ) async {
    await pumpStadiumlyApp(tester);

    await tester.scrollUntilVisible(
      find.text('Gdansk waterfront gate'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Gdansk waterfront gate'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Woj'));
    await tester.pumpAndSettle();

    expect(find.text('Visited in Wojewodztwo'), findsOneWidget);
    expect(find.text('Pomorskie'), findsOneWidget);
    expect(find.text('Mazowieckie'), findsNothing);
    expect(find.byTooltip('Clear selected object'), findsNothing);
  });

  testWidgets('creates an object from manual coordinates', (
    WidgetTester tester,
  ) async {
    await pumpStadiumlyApp(tester);

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

    expect(find.text('5 objects'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Manual Gate'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Manual Gate'), findsOneWidget);
  });
}
