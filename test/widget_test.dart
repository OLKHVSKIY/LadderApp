// Smoke-тест: приложение собирается и показывает стартовый экран.

import 'package:flutter_test/flutter_test.dart';

import 'package:ladder/main.dart';
import 'package:ladder/pages/login_page.dart';

void main() {
  testWidgets('App builds and shows login page', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(LoginPage), findsOneWidget);
  });
}
