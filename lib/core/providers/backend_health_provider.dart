import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/backend_health_service.dart';
import '../services/transcription_api_service.dart';
import 'feature_flags_provider.dart';
import '../../features/daily/recorder/providers/service_providers.dart'
    show transcriptionServiceUrlProvider, transcriptionServiceApiKeyProvider;

/// Provider for backend health service
final backendHealthServiceProvider = Provider.family<BackendHealthService, String>((ref, baseUrl) {
  final service = BackendHealthService(baseUrl: baseUrl);
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

  final service = ref.watch(backendHealthServiceProvider(url));
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

  final service = ref.watch(backendHealthServiceProvider(url));

  // Initial check
  yield await service.checkHealth();

  // Periodic checks every 30 seconds
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    yield await service.checkHealth();
  }
});

/// Whether an external transcription service is configured and reachable.
///
/// Checks the transcription service URL (Whisper-compatible endpoint).
/// Used by the recording flow to decide server vs local transcription path.
final serverTranscriptionAvailableProvider = Provider<bool>((ref) {
  final urlAsync = ref.watch(transcriptionServiceUrlProvider);
  final url = urlAsync.valueOrNull;
  return url != null && url.isNotEmpty;
});

/// Provider for a TranscriptionApiService instance built from current settings.
final transcriptionApiServiceProvider = Provider<TranscriptionApiService?>((ref) {
  final url = ref.watch(transcriptionServiceUrlProvider).valueOrNull;
  if (url == null || url.isEmpty) return null;

  final apiKey = ref.watch(transcriptionServiceApiKeyProvider).valueOrNull;
  final service = TranscriptionApiService(baseUrl: url, apiKey: apiKey);
  ref.onDispose(() => service.dispose());
  return service;
});

