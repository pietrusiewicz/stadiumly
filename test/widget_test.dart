import 'package:flutter_test/flutter_test.dart';

import 'package:stadiumly/main.dart';

void main() {
  testWidgets('shows the waypoint map shell', (WidgetTester tester) async {
    await tester.pumpWidget(const StadiumlyApp());

    expect(find.text('Stadiumly'), findsOneWidget);
    expect(find.text('Waypoints'), findsOneWidget);
    expect(find.text('National Stadium'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
  });
}
