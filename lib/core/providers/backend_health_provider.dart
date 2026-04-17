import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/backend_health_service.dart';
import '../services/transcription_api_service.dart';
import '../services/tts_api_service.dart';
import 'app_state_provider.dart' show apiKeyProvider, vaultNameProvider;
import 'feature_flags_provider.dart';
import '../../features/daily/recorder/providers/service_providers.dart'
    show transcriptionServiceUrlProvider, transcriptionServiceApiKeyProvider,
         ttsServiceUrlProvider, ttsServiceApiKeyProvider;

/// Provider for backend health service (includes API key for authenticated endpoints).
///
/// Health checks route through the vault-scoped prefix (`/vaults/<name>/api`)
/// when a vault is selected, so the periodic reachability indicator reflects
/// the path the app actually uses to read/write notes.
final backendHealthServiceProvider = Provider<BackendHealthService>((ref) {
  final url = ref.watch(aiServerUrlProvider).valueOrNull ?? '';
  final key = ref.watch(apiKeyProvider).valueOrNull;
  final vault = ref.watch(vaultNameProvider).valueOrNull;
  final service = BackendHealthService(
    baseUrl: url,
    apiKey: key,
    vaultName: vault,
  );
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for server health status
final serverHealthProvider = FutureProvider<ServerHealthStatus?>((ref) async {
  final urlAsync = ref.watch(aiServerUrlProvider);
  final url = urlAsync.valueOrNull;

  if (url == null || url.isEmpty) {
    return null; // No server configured
  }

  final service = ref.watch(backendHealthServiceProvider);
  return service.checkHealth();
});

/// Provider for periodic server health checks
final periodicServerHealthProvider = StreamProvider<ServerHealthStatus?>((ref) async* {
  final urlAsync = ref.watch(aiServerUrlProvider);
  final url = urlAsync.valueOrNull;

  if (url == null || url.isEmpty) {
    yield null;
    return;
  }

  final service = ref.watch(backendHealthServiceProvider);

  // Initial check
  yield await service.checkHealth();

  // Periodic checks every 30 seconds
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    yield await service.checkHealth();
  }
});

/// Whether transcription is available (custom endpoint or vault with scribe).
///
/// Periodically checks reachability of whichever transcription endpoint is active.
/// Used by the recording flow to decide server vs local transcription path.
final serverTranscriptionAvailableProvider = Provider<bool>((ref) {
  final reachable = ref.watch(transcriptionServiceReachableProvider);
  return reachable.valueOrNull ?? false;
});

/// Periodic reachability check for the transcription service.
final transcriptionServiceReachableProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(transcriptionApiServiceProvider);
  if (service == null) {
    yield false;
    return;
  }

  // Initial check
  final result = await service.checkConnection();
  yield result.reachable;

  // Re-check every 30 seconds
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    final r = await service.checkConnection();
    yield r.reachable;
  }
});

/// Provider for a TranscriptionApiService instance built from current settings.
///
/// Uses the custom transcription URL if configured, otherwise falls back to
/// the vault server URL (vault can host transcription via scribe).
final transcriptionApiServiceProvider = Provider<TranscriptionApiService?>((ref) {
  // Try custom transcription URL first
  final customUrl = ref.watch(transcriptionServiceUrlProvider).valueOrNull;
  if (customUrl != null && customUrl.isNotEmpty) {
    final apiKey = ref.watch(transcriptionServiceApiKeyProvider).valueOrNull;
    final service = TranscriptionApiService(baseUrl: customUrl, apiKey: apiKey);
    ref.onDispose(() => service.dispose());
    return service;
  }

  // Fall back to vault URL (vault can serve /v1/audio/transcriptions via scribe)
  final vaultUrl = ref.watch(aiServerUrlProvider).valueOrNull;
  if (vaultUrl == null || vaultUrl.isEmpty) return null;

  final vaultApiKey = ref.watch(apiKeyProvider).valueOrNull;
  final service = TranscriptionApiService(baseUrl: vaultUrl, apiKey: vaultApiKey);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for a TtsApiService instance built from current settings.
///
/// Uses the custom TTS URL if configured, otherwise falls back to
/// the vault server URL (vault can proxy to narrate).
final ttsApiServiceProvider = Provider<TtsApiService?>((ref) {
  // Try custom TTS URL first
  final customUrl = ref.watch(ttsServiceUrlProvider).valueOrNull;
  if (customUrl != null && customUrl.isNotEmpty) {
    final apiKey = ref.watch(ttsServiceApiKeyProvider).valueOrNull;
    final service = TtsApiService(baseUrl: customUrl, apiKey: apiKey);
    ref.onDispose(() => service.dispose());
    return service;
  }

  // Fall back to vault URL
  final vaultUrl = ref.watch(aiServerUrlProvider).valueOrNull;
  if (vaultUrl == null || vaultUrl.isEmpty) return null;

  final vaultApiKey = ref.watch(apiKeyProvider).valueOrNull;
  final service = TtsApiService(baseUrl: vaultUrl, apiKey: vaultApiKey);
  ref.onDispose(() => service.dispose());
  return service;
});

