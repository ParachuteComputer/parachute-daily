import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/providers/feature_flags_provider.dart'
    show aiServerUrlProvider;
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';

/// Trigger to refresh the digest list.
final digestRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Whether to show archived digest notes.
final digestShowArchivedProvider = StateProvider<bool>((ref) => false);

/// Fetches digest notes from server, falling back to local cache.
///
/// Respects [digestShowArchivedProvider] — when false (default), excludes #archived.
/// When true, fetches all digest notes including archived.
final digestNotesProvider = FutureProvider.autoDispose<List<Note>>((ref) async {
  ref.watch(digestRefreshTriggerProvider);
  final showArchived = ref.watch(digestShowArchivedProvider);

  // Ensure the server URL has resolved before querying.
  await ref.watch(aiServerUrlProvider.future);
  final api = ref.watch(graphApiServiceProvider);

  final notes = await api.queryNotes(
    tag: 'reader',
    excludeTag: showArchived ? null : 'archived',
    sort: 'desc',
  );

  if (notes != null) {
    // Cache notes locally for offline use
    try {
      final cache = await ref.read(noteLocalCacheProvider.future);
      cache.putNotes(notes);
    } catch (e) {
      debugPrint('[DigestProviders] Cache write failed: $e');
    }
    return _sortDigestNotes(notes);
  }

  // Server unreachable — fall back to local cache
  try {
    final cache = await ref.read(noteLocalCacheProvider.future);
    final cached = cache.getNotesWithTag(
      'reader',
      excludeTag: showArchived ? null : 'archived',
    );
    return _sortDigestNotes(cached);
  } catch (e) {
    debugPrint('[DigestProviders] Cache read failed: $e');
    return [];
  }
});

/// Sort digest notes: pinned first, then by date descending.
List<Note> _sortDigestNotes(List<Note> notes) {
  final pinned = notes.where((n) => n.isPinned).toList();
  final unpinned = notes.where((n) => !n.isPinned).toList();

  // Each group sorted by most recent activity
  int byDate(Note a, Note b) {
    final aDate = a.updatedAt ?? a.createdAt;
    final bDate = b.updatedAt ?? b.createdAt;
    return bDate.compareTo(aDate);
  }
  pinned.sort(byDate);
  unpinned.sort(byDate);

  return [...pinned, ...unpinned];
}

/// Count of active (non-archived) digest notes.
final digestCountProvider = Provider<int>((ref) {
  final notesAsync = ref.watch(digestNotesProvider);
  return notesAsync.valueOrNull?.length ?? 0;
});

/// Group digest notes by sub-tag for section display.
///
/// Returns a map of display label → notes. Notes with only `#digest`
/// go into an empty-string key (no section header). Sub-tags like
/// `digest/summary` get a label like "Summary".
Map<String, List<Note>> groupReaderBySubTag(List<Note> notes) {
  final grouped = <String, List<Note>>{};

  for (final note in notes) {
    final readerTag = note.tags.firstWhere(
      (t) => t.startsWith('reader/'),
      orElse: () => 'reader',
    );

    final label = readerTag == 'reader'
        ? ''
        : _formatSubTagLabel(readerTag.substring('reader/'.length));

    grouped.putIfAbsent(label, () => []).add(note);
  }

  return grouped;
}

/// Format a sub-tag slug into a display label.
/// e.g. "action-item" → "Action Item", "summary" → "Summary"
String _formatSubTagLabel(String slug) {
  return slug
      .split(RegExp(r'[-_]'))
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
