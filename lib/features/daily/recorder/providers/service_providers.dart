import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:parachute/core/services/transcription/audio_service.dart';
import 'package:parachute/core/providers/app_state_provider.dart' show apiKeyProvider;
import 'package:parachute/core/providers/voice_input_providers.dart';
import 'package:parachute/features/daily/recorder/services/live_transcription_service_v3.dart';
import 'package:parachute/features/daily/recorder/services/recording_post_processing_service.dart';

// Settings keys
const String _autoEnhanceKey = 'auto_enhance';
const String _transcriptionModeKey = 'transcription_mode';
const String _transcriptionServiceUrlKey = 'transcription_service_url';
const String _transcriptionServiceApiKeyKey = 'transcription_service_api_key';

/// Transcription mode: where voice entries get transcribed.
///
/// - [auto]: Use server when connected and capable, fall back to local (default)
/// - [server]: Always use server transcription (fail if unavailable)
/// - [local]: Always transcribe on-device
enum TranscriptionMode {
  auto,
  server,
  local,
}

/// Provider for auto-enhance setting
/// When enabled, automatically cleans up transcripts and generates titles
final autoEnhanceProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_autoEnhanceKey) ?? false; // Default: OFF
});

/// Set auto-enhance preference
Future<void> setAutoEnhance(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_autoEnhanceKey, enabled);
}

/// Provider for transcription mode setting
final transcriptionModeProvider = FutureProvider<TranscriptionMode>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(_transcriptionModeKey);
  return TranscriptionMode.values.firstWhere(
    (m) => m.name == value,
    orElse: () => TranscriptionMode.auto,
  );
});

/// Set transcription mode preference
Future<void> setTranscriptionMode(TranscriptionMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_transcriptionModeKey, mode.name);
}

/// Provider for transcription service URL (external Whisper-compatible endpoint)
final transcriptionServiceUrlProvider = FutureProvider<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_transcriptionServiceUrlKey);
});

/// Set transcription service URL
Future<void> setTranscriptionServiceUrl(String? url) async {
  final prefs = await SharedPreferences.getInstance();
  if (url != null && url.isNotEmpty) {
    await prefs.setString(_transcriptionServiceUrlKey, url);
  } else {
    await prefs.remove(_transcriptionServiceUrlKey);
  }
}

/// Provider for transcription service API key
final transcriptionServiceApiKeyProvider = FutureProvider<String?>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_transcriptionServiceApiKeyKey);
});

/// Set transcription service API key
Future<void> setTranscriptionServiceApiKey(String? key) async {
  final prefs = await SharedPreferences.getInstance();
  if (key != null && key.isNotEmpty) {
    await prefs.setString(_transcriptionServiceApiKeyKey, key);
  } else {
    await prefs.remove(_transcriptionServiceApiKeyKey);
  }
}

/// Whether a transcription service URL is configured (non-empty)
final isTranscriptionServiceConfiguredProvider = Provider<bool>((ref) {
  final urlAsync = ref.watch(transcriptionServiceUrlProvider);
  final url = urlAsync.valueOrNull;
  return url != null && url.isNotEmpty;
});

/// Provider for AudioService
///
/// This manages audio recording and playback functionality.
/// The service is initialized on first access and kept alive for the app lifetime.
///
/// IMPORTANT: The service initializes asynchronously. Callers should use
/// `await audioService.ensureInitialized()` before using the service if they
/// need to guarantee initialization is complete.
final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  // Initialize the service when first accessed
  service.initialize().catchError((e) {
    debugPrint('[AudioServiceProvider] Initialization error: $e');
  });

  // Pass API key for authenticated audio downloads
  final apiKey = ref.watch(apiKeyProvider).valueOrNull;
  service.apiKey = apiKey;

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

/// Provider for TranscriptionServiceAdapter
///
/// Re-exports from voice_input_providers for consistency.
/// Uses the same singleton instance across the app.
///
/// Platform-adaptive transcription using Parakeet v3:
/// - iOS/macOS: FluidAudio (CoreML + Apple Neural Engine)
/// - Android: Sherpa-ONNX (ONNX Runtime)
final transcriptionServiceAdapterProvider = transcriptionServiceProvider;

/// Provider for RecordingPostProcessingService
///
/// Pipeline for processing recordings:
/// - Transcription (Parakeet v3 via FluidAudio or Sherpa-ONNX)
final recordingPostProcessingProvider =
    Provider<RecordingPostProcessingService>((ref) {
      final transcriptionService = ref.watch(
        transcriptionServiceAdapterProvider,
      );

      return RecordingPostProcessingService(
        transcriptionService: transcriptionService,
      );
    });

/// State notifier for managing active recording session
///
/// This holds the current recording state and transcription service,
/// allowing it to persist across navigation (recording screen → detail screen).
class ActiveRecordingState {
  final AutoPauseTranscriptionService? service;
  final String? audioFilePath;
  final DateTime? startTime;
  final bool isTranscribing;

  ActiveRecordingState({
    this.service,
    this.audioFilePath,
    this.startTime,
    this.isTranscribing = false,
  });

  ActiveRecordingState copyWith({
    AutoPauseTranscriptionService? service,
    String? audioFilePath,
    DateTime? startTime,
    bool? isTranscribing,
  }) {
    return ActiveRecordingState(
      service: service ?? this.service,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      startTime: startTime ?? this.startTime,
      isTranscribing: isTranscribing ?? this.isTranscribing,
    );
  }
}

class ActiveRecordingNotifier extends StateNotifier<ActiveRecordingState> {
  ActiveRecordingNotifier() : super(ActiveRecordingState());

  /// Start a new recording session
  void startSession(AutoPauseTranscriptionService service, DateTime startTime) {
    state = ActiveRecordingState(
      service: service,
      startTime: startTime,
      isTranscribing: false,
    );
  }

  /// Stop recording and get audio file path
  Future<String?> stopRecording() async {
    if (state.service == null) return null;

    final audioPath = await state.service!.stopRecording();
    state = state.copyWith(audioFilePath: audioPath, isTranscribing: true);

    return audioPath;
  }

  /// Mark transcription as complete
  void completeTranscription() {
    state = state.copyWith(isTranscribing: false);
  }

  /// Clear the session (called after save is complete)
  void clearSession() {
    final oldService = state.service;
    state = ActiveRecordingState();

    // Dispose old service
    oldService?.dispose();
  }
}

/// Provider for active recording session
///
/// This keeps the transcription service alive across navigation,
/// allowing recording → detail screen transition while transcription continues.
final activeRecordingProvider =
    StateNotifierProvider<ActiveRecordingNotifier, ActiveRecordingState>((ref) {
      return ActiveRecordingNotifier();
    });
