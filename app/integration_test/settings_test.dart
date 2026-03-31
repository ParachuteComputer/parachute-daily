import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/providers/feature_flags_provider.dart';
import 'package:parachute/core/theme/app_theme.dart';
import 'package:parachute/features/settings/widgets/server_settings_section.dart';
import 'package:parachute/features/settings/widgets/transcription_settings_section.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Server Settings Section', () {
    testWidgets('ServerSettingsSection renders header',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiServerUrlProvider.overrideWith(
              (ref) async => 'http://localhost:9999',
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: ServerSettingsSection(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Parachute Computer'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
    });
  });

  group('Transcription Settings Section', () {
    testWidgets('TranscriptionSettingsSection renders header',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiServerUrlProvider.overrideWith(
              (ref) async => 'http://localhost:9999',
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: TranscriptionSettingsSection(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Transcription'), findsOneWidget);
    });
  });
}
