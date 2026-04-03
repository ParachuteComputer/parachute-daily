import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/config/app_config.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/providers/feature_flags_provider.dart'
    show aiServerUrlProvider;
import 'package:parachute/core/providers/app_state_provider.dart'
    show apiKeyProvider;
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

  final service = DailyApiService(
    baseUrl: baseUrl,
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

  return GraphApiService(
    baseUrl: baseUrl,
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
  final isVoice = note.hasTag('voice');
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
  final cachedNotes = cache.getNotesForDate(dateStr, nextDateStr);
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
    final freshNotes = cache.getNotesForDate(dateStr, nextDateStr);
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
      final voiceNotes = serverNotes.where((n) => n.isVoice).toList();
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
  final freshNotes = cache.getNotesForDate(dateStr, nextDateStr);
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
      final tags = note.tags.isNotEmpty ? note.tags : ['daily'];
      final audioPath = cache.getAudioPath(note.id);

      // Upload audio if it's a local file path
      String? resolvedAudioPath = audioPath;
      if (audioPath != null && audioPath.startsWith('/')) {
        final serverPath = await api.uploadAudio(
          File(audioPath),
        );
        if (serverPath == null) {
          debugPrint('[FlushOps] Audio upload pending for ${note.id}');
          continue; // Keep in queue
        }
        resolvedAudioPath = serverPath;
      }

      final serverNote = await api.createNote(
        content: note.content,
        tags: tags,
      );
      if (serverNote != null) {
        if (resolvedAudioPath != null) {
          await api.addAttachment(serverNote.id, resolvedAudioPath, 'audio/wav');
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
// Backward-compatible aliases
// TODO(v3-cache): Remove once journal_screen.dart is migrated
// ============================================================================

/// Alias for [noteLocalCacheProvider] — old consumers use this name.
/// Returns a shim that delegates to NoteLocalCache.
final journalLocalCacheProvider = FutureProvider<_JournalCacheShim>((ref) async {
  final cache = await ref.watch(noteLocalCacheProvider.future);
  return _JournalCacheShim(cache);
});

/// Shim that wraps NoteLocalCache with the old JournalLocalCache interface.
class _JournalCacheShim {
  final NoteLocalCache _cache;
  _JournalCacheShim(this._cache);

  List<JournalEntry> getEntries(String date) {
    final nextDate = _nextDate(date);
    final notes = _cache.getNotesForDate(date, nextDate);
    return notes.map((note) {
      final audioPath = _cache.getAudioPath(note.id);
      return _noteToEntry(note, audioPath: audioPath);
    }).toList();
  }

  void putEntries(String date, List<JournalEntry> entries) {
    // Convert entries back to notes for caching.
    // This is lossy but preserves the important data.
    final notes = entries.map((e) => Note(
      id: e.id,
      content: e.content,
      path: e.title.isNotEmpty ? e.title : null,
      createdAt: e.createdAt,
      tags: e.tags ?? (e.type == JournalEntryType.voice ? ['daily', 'voice'] : ['daily']),
    )).toList();
    _cache.putNotes(notes);
    // Cache audio attachments
    for (final e in entries) {
      if (e.audioPath != null) {
        _cache.putAttachment(e.id, e.audioPath!, 'audio/wav');
      }
    }
  }

  void markForDelete(String entryId) => _cache.markForDelete(entryId);

  void markForEdit(String entryId, {required String content, required String title}) {
    _cache.markForEdit(entryId, content: content);
  }

  void markSynced(String entryId, {String? content, String? title}) {
    _cache.markSynced(entryId, content: content);
  }

  void removeEntry(String entryId) => _cache.removeNote(entryId);

  void clearDate(String date) {
    final nextDate = _nextDate(date);
    _cache.clearDateRange(date, nextDate);
  }

  void removeStaleEntries(String date, Set<String> serverIds) {
    final nextDate = _nextDate(date);
    _cache.removeStaleNotes(date, nextDate, serverIds);
  }

  List<String> getPendingDeletes() => _cache.getPendingDeletes();

  List<JournalEntry> getPendingEdits() {
    return _cache.getPendingEdits().map((note) => _noteToEntry(note)).toList();
  }
}

/// Old-style pending queue — now backed by NoteLocalCache's pending_create.
final pendingQueueProvider = FutureProvider<_PendingQueueShim>((ref) async {
  final cache = await ref.watch(noteLocalCacheProvider.future);
  return _PendingQueueShim(cache);
});

class _PendingQueueShim {
  final NoteLocalCache _cache;
  _PendingQueueShim(this._cache);

  List<JournalEntry> get entries {
    return _cache.getPendingCreates().map((note) {
      final audioPath = _cache.getAudioPath(note.id);
      return _noteToEntry(note, audioPath: audioPath, isPending: true);
    }).toList();
  }

  bool get isEmpty => _cache.getPendingCreates().isEmpty;
  int get length => _cache.getPendingCreates().length;

  Future<JournalEntry> enqueue({
    required String localId,
    required String content,
    String type = 'text',
    String? title,
    String? audioPath,
    String? imagePath,
    int? durationSeconds,
  }) async {
    final tags = <String>['daily'];
    if (type == 'voice') tags.add('voice');

    final note = Note(
      id: localId,
      content: content,
      path: title,
      createdAt: DateTime.now(),
      tags: tags,
    );
    _cache.insertPendingCreate(note, audioPath: audioPath);
    return _noteToEntry(note, audioPath: audioPath, isPending: true);
  }

  Future<void> remove(String localId) async {
    _cache.removeNote(localId);
  }

  Future<void> flush(DailyApiService api) async {
    // Flushing is now handled by _flushPendingOps in the provider
  }

  void dispose() {}
}

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
