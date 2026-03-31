import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/providers/app_state_provider.dart';
import 'package:parachute/core/providers/feature_flags_provider.dart';
import 'package:parachute/core/theme/app_theme.dart';

/// Creates a test app with provider overrides.
///
/// Boots a minimal widget tree that mirrors the Daily-only shell
/// but stubs out providers that depend on native plugins or network.
Widget createTestApp({
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      // Skip onboarding in tests
      onboardingCompleteProvider.overrideWith(OnboardingNotifier.new),

      // Provide a fake server URL
      serverUrlProvider.overrideWith(ServerUrlNotifier.new),

      // Provide a fake AI server URL for screens that watch it
      aiServerUrlProvider.overrideWith(
        (ref) async => 'http://localhost:9999',
      ),

      // User-provided overrides
      ...extraOverrides,
    ],
    child: MaterialApp(
      title: 'Parachute Test',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const _TestShell(),
    ),
  );
}

/// Creates a test app in dark mode.
Widget createTestAppDark({
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      onboardingCompleteProvider.overrideWith(OnboardingNotifier.new),
      serverUrlProvider.overrideWith(ServerUrlNotifier.new),
      aiServerUrlProvider.overrideWith(
        (ref) async => 'http://localhost:9999',
      ),
      ...extraOverrides,
    ],
    child: MaterialApp(
      title: 'Parachute Test',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: const _TestShell(),
    ),
  );
}

/// Minimal shell that mirrors _DailyShell but skips heavy initState work.
class _TestShell extends ConsumerWidget {
  const _TestShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      key: const ValueKey('daily_tab'),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.today_outlined, size: 48),
            SizedBox(height: 16),
            Text('Daily Tab Content', style: TextStyle(fontSize: 20)),
          ],
        ),
      ),
    );
  }
}
