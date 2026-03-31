import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:parachute/core/theme/design_tokens.dart';

import 'helpers/test_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Launch', () {
    testWidgets('App renders with correct theme', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Design tokens are valid', (WidgetTester tester) async {
      expect(BrandColors.forest, isNotNull);
      expect(BrandColors.forest, isA<Color>());
      expect(BrandColors.nightForest, isA<Color>());
      expect(BrandColors.turquoise, isA<Color>());
      expect(BrandColors.nightTurquoise, isA<Color>());

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();
    });
  });

  group('Navigation — Daily Only', () {
    testWidgets('Daily-only layout has no navigation bar',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // No navigation bar (single screen, no tabs)
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationDestination), findsNothing);
    });

    testWidgets('Daily content is displayed', (WidgetTester tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      expect(find.text('Daily Tab Content'), findsOneWidget);
    });
  });

  group('Dark Mode', () {
    testWidgets('App renders in dark mode without crash',
        (WidgetTester tester) async {
      await tester.pumpWidget(createTestAppDark());
      await tester.pumpAndSettle();

      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
