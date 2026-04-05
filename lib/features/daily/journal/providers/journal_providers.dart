import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/config/app_config.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/providers/feature_flags_provider.dart'
    show aiServerUrlProvider;
import 'package:parachute/core/providers/app_state_provider.dart'
    show apiKeyProvider, vaultNameProvider;
import 'package:parachute/core/providers/backend_health_provider.dart'
    show periodicServerHealthProvider;
import 'package:parachute/core/providers/connectivity_provider.dart'
    show isServerAvailableProvider, serverReachableOverrideProvider;
import 'package:parachute/core/services/graph_api_service.dart';
import 'package:parachute/core/services/note_local_cache.dart';
import '../models/journal_entry.dart';
import '../models/journal_day.dart';
import '../services/daily_api_service.dart' show DailyApiService, nextDate;

// ============================================================================
// Daily API Service Providers (server-backed)
// ============================================================================

/// Provider for DailyApiService — mirrors chatServiceProvider pattern
final dailyApiServiceProvider = Provider<DailyApiService>((ref) {
  final urlAsync = ref.watch(aiServerUrlProvider);
  final baseUrl = urlAsync.valueOrNull ?? AppConfig.defaultServerUrl;
  final apiKeyAsync = ref.watch(apiKeyProvider);
  final apiKey = apiKeyAsync.valueOrNull;
  final vaultName = ref.watch(vaultNameProvider).valueOrNull;

  final service = DailyApiService(
    baseUrl: baseUrl,
    vaultName: vaultName,
    apiKey: apiKey,
    onReachabilityChanged: (reachable) {
      ref.read(serverReachableOverrideProvider.notifier).state = reachable;
    },
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Provider for GraphApiService — v3 graph API client.
///
/// Used by Digest/Docs providers for direct note operations.
final graphApiServiceProvider = Provider<GraphApiService>((ref) {
  final urlAsync = ref.watch(aiServerUrlProvider);
  final baseUrl = urlAsync.valueOrNull ?? AppConfig.defaultServerUrl;
  final apiKeyAsync = ref.watch(apiKeyProvider);
  final apiKey = apiKeyAsync.valueOrNull;
  final vaultName = ref.watch(vaultNameProvider).valueOrNull;

  return GraphApiService(
    baseUrl: baseUrl,
    vaultName: vaultName,
    apiKey: apiKey,
    onReachabilityChanged: (reachable) {
      ref.read(serverReachableOverrideProvider.notifier).state = reachable;
    },
  );
});

/// Provider for the local Note cache — offline fallback.
///
/// Opens once per app session; disposed when no longer referenced.
/// Falls back to in-memory database if documents directory is unavailable.
final noteLocalCacheProvider = FutureProvider<NoteLocalCache>((ref) async {
  final cache = await NoteLocalCache.open();
  ref.onDispose(cache.dispose);
  return cache;
});

/// Provider for tracking the currently selected date
final selectedJournalDateProvider = StateProvider<DateTime>((ref) {
  return DateTime.now();
});

/// Provider for triggering journal refresh
final journalRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Formats a DateTime as YYYY-MM-DD for API calls.
String _formatDateForApi(DateTime date) {
  final y = date.year.toString();
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Provider for today's journal — cache-first, then server.
///
/// Phase 1: emits cached notes immediately (instant display, works offline).
/// Phase 2: fetches from server, updates cache, emits fresh data.
final todayJournalProvider =
    AsyncNotifierProvider.autoDispose<_TodayJournalNotifier, JournalDay>(
      _TodayJournalNotifier.new,
    );

class _TodayJournalNotifier extends AutoDisposeAsyncNotifier<JournalDay> {
  @override
  Future<JournalDay> build() async {
    ref.watch(journalRefreshTriggerProvider);

    // Flush pending ops when connectivity restores (offline → online transition).
    ref.listen(periodicServerHealthProvider, (previous, next) {
      if (previous == null) return;
      final wasHealthy = previous.valueOrNull?.isHealthy ?? false;
      final isHealthy = next.valueOrNull?.isHealthy ?? false;
      if (!wasHealthy && isHealthy) {
        Future(() async {
          try {
            final api = ref.read(dailyApiServiceProvider);
            final cache = await ref.read(noteLocalCacheProvider.future);
            await _flushPendingOps(api, cache);
          } catch (e) {
            debugPrint('[_TodayJournalNotifier] Error flushing on reconnect: $e');
          }
        });
      }
    });

    return _loadJournal(ref, DateTime.now(), (day) => state = AsyncData(day));
  }
}

/// Provider for a specific date's journal — cache-first, then server.
final selectedJournalProvider =
    AsyncNotifierProvider.autoDispose<_SelectedJournalNotifier, JournalDay>(
      _SelectedJournalNotifier.new,
    );

class _SelectedJournalNotifier extends AutoDisposeAsyncNotifier<JournalDay> {
  @override
  Future<JournalDay> build() async {
    final date = ref.watch(selectedJournalDateProvider);
    ref.watch(journalRefreshTriggerProvider);
    return _loadJournal(ref, date, (day) => state = AsyncData(day));
  }
}

/// Convert a Note to a JournalEntry for display.
///
/// This is the boundary between the v3 data model (Note + tags) and the
/// Daily tab's specialized view model (JournalEntry with type, audio, etc.).
JournalEntry _noteToEntry(Note note, {String? audioPath, bool isPending = false}) {
  final isVoice = audioPath != null;
  return JournalEntry(
    id: note.id,
    title: note.path ?? '',
    content: note.content,
    type: isVoice ? JournalEntryType.voice : JournalEntryType.text,
    createdAt: note.createdAt,
    audioPath: audioPath,
    isPending: isPending,
    tags: note.tags,
  );
}

/// Two-phase journal load: cache first, then server.
Future<JournalDay> _loadJournal(
  Ref ref,
  DateTime date,
  void Function(JournalDay) onCacheHit,
) async {
  final dateStr = _formatDateForApi(date);
  final nextDateStr = _nextDate(dateStr);
  final api = ref.read(dailyApiServiceProvider);
  final cache = await ref.watch(noteLocalCacheProvider.future);

  // Phase 1 — serve from cache immediately (excludes pending_delete).
  final cachedNotes = cache.getNotesForDate(dateStr, nextDateStr, tags: [DailyApiService.captureTag]);
  if (cachedNotes.isNotEmpty) {
    final entries = cachedNotes.map((note) {
      final audioPath = cache.getAudioPath(note.id);
      return _noteToEntry(note, audioPath: audioPath);
    }).toList();
    onCacheHit(JournalDay.fromEntries(date, entries));
  }

  // Phase 2 — flush pending ops and fetch from server (only when online).
  final isAvailable = ref.watch(isServerAvailableProvider);
  if (!isAvailable) {
    final freshNotes = cache.getNotesForDate(dateStr, nextDateStr, tags: [DailyApiService.captureTag]);
    final entries = freshNotes.map((note) {
      final audioPath = cache.getAudioPath(note.id);
      return _noteToEntry(note, audioPath: audioPath);
    }).toList();
    return JournalDay.fromEntries(date, entries);
  }

  await _flushPendingOps(api, cache);

  // Fetch from server — returns Note objects directly.
  final serverNotes = await api.getNotes(date: dateStr);

  if (serverNotes != null) {
    if (serverNotes.isEmpty) {
      cache.clearDateRange(dateStr, nextDateStr);
    } else {
      cache.putNotes(serverNotes);
      cache.removeStaleNotes(
        dateStr, nextDateStr, serverNotes.map((n) => n.id).toSet(),
      );
      // Fetch and cache audio paths for voice notes (parallel).
      final voiceNotes = serverNotes.where((n) => n.isCaptured).toList();
      if (voiceNotes.isNotEmpty) {
        final audioPaths = await Future.wait(
          voiceNotes.map((n) => api.getAudioPath(n.id)),
        );
        for (var i = 0; i < voiceNotes.length; i++) {
          if (audioPaths[i] != null) {
            cache.putAttachment(voiceNotes[i].id, audioPaths[i]!, 'audio/wav');
          }
        }
      }
    }
  }

  // Re-read cache: merged truth.
  final freshNotes = cache.getNotesForDate(dateStr, nextDateStr, tags: [DailyApiService.captureTag]);
  final entries = freshNotes.map((note) {
    final audioPath = cache.getAudioPath(note.id);
    return _noteToEntry(note, audioPath: audioPath);
  }).toList();
  return JournalDay.fromEntries(date, entries);
}

/// Re-entrancy guard for [_flushPendingOps].
bool _flushPendingOpsActive = false;

/// Flush all pending operations: creates, edits, and deletes.
Future<void> _flushPendingOps(
  DailyApiService api,
  NoteLocalCache cache,
) async {
  if (_flushPendingOpsActive) return;
  _flushPendingOpsActive = true;
  try {
    // Flush pending creates
    final pendingCreates = cache.getPendingCreates();
    for (final note in pendingCreates) {
      final audioPath = cache.getAudioPath(note.id);
      // Voice notes with local audio: use ingest endpoint (atomic)
      if (audioPath != null && audioPath.startsWith('/')) {
        final audioFile = File(audioPath);
        if (!await audioFile.exists()) {
          debugPrint('[FlushOps] Audio file missing for ${note.id}, skipping');
          continue;
        }

        final serverNote = await api.ingestVoiceMemo(
          audioFile: audioFile,
          createdAt: note.createdAt,
          durationSeconds: 0, // Duration not stored in pending note
          transcribe: note.content.isEmpty, // Transcribe if no content yet
        );

        if (serverNote != null) {
          cache.removeNote(note.id);
          cache.putNotes([serverNote]);
          try { await audioFile.delete(); } catch (_) {}
          debugPrint('[FlushOps] Ingested ${note.id} → ${serverNote.id}');
        } else {
          debugPrint('[FlushOps] Ingest pending for ${note.id}');
        }
        continue;
      }

      // Non-voice notes or notes with server audio paths: create directly
      final tags = note.tags.isNotEmpty ? note.tags : ['captured'];
      final serverNote = await api.createNote(
        content: note.content,
        tags: tags,
        createdAt: note.createdAt,
      );
      if (serverNote != null) {
        if (audioPath != null && !audioPath.startsWith('/')) {
          // Already a server path — just link the attachment
          await api.addAttachment(serverNote.id, audioPath, 'audio/wav');
        }
        cache.removeNote(note.id);
        cache.putNotes([serverNote]);
        debugPrint('[FlushOps] Flushed create ${note.id} → ${serverNote.id}');
      }
    }

    // Flush pending deletes
    final deleteIds = cache.getPendingDeletes();
    for (final id in deleteIds) {
      final ok = await api.deleteNote(id);
      if (ok) {
        cache.removeNote(id);
      }
    }

    // Flush pending edits
    final editNotes = cache.getPendingEdits();
    for (final note in editNotes) {
      final updated = await api.updateNote(note.id, content: note.content);
      if (updated != null) {
        cache.markSynced(note.id, content: updated.content);
      }
    }
  } finally {
    _flushPendingOpsActive = false;
  }
}

String _nextDate(String date) => nextDate(date);

// ============================================================================
// Sync Status Providers
// ============================================================================

/// Count of notes pending sync (creates + edits + deletes).
final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  try {
    final cache = await ref.watch(noteLocalCacheProvider.future);
    return cache.getPendingCount();
  } catch (e) {
    return 0;
  }
});
