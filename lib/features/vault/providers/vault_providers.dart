import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/providers/feature_flags_provider.dart'
    show aiServerUrlProvider;
import 'package:parachute/core/services/tag_service.dart';
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';

/// Trigger to refresh vault data.
final vaultRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Search query for the vault tab.
final vaultSearchQueryProvider = StateProvider<String>((ref) => '');

/// Fetch all tags with counts from the server.
final vaultTagsProvider = FutureProvider.autoDispose<List<TagInfo>>((ref) async {
  ref.watch(vaultRefreshTriggerProvider);
  await ref.watch(aiServerUrlProvider.future);
  final tagService = ref.watch(tagServiceProvider);
  return tagService.listTags();
});

/// Search notes across the full vault.
final vaultSearchProvider = FutureProvider.autoDispose<List<Note>?>((ref) async {
  final query = ref.watch(vaultSearchQueryProvider);
  if (query.trim().isEmpty) return null;
  await ref.watch(aiServerUrlProvider.future);
  final api = ref.watch(graphApiServiceProvider);
  return api.searchNotes(query);
});

/// Recent notes across all tags (dashboard view).
final vaultRecentNotesProvider = FutureProvider.autoDispose<List<Note>>((ref) async {
  ref.watch(vaultRefreshTriggerProvider);
  await ref.watch(aiServerUrlProvider.future);
  final api = ref.watch(graphApiServiceProvider);
  final notes = await api.queryNotes(sort: 'desc', limit: 15);

  if (notes != null) {
    try {
      final cache = await ref.read(noteLocalCacheProvider.future);
      cache.putNotes(notes);
    } catch (e) {
      debugPrint('[VaultProviders] Cache write failed: $e');
    }
    return notes;
  }

  return [];
});

/// Notes filtered by a specific tag.
final vaultTagNotesProvider =
    FutureProvider.autoDispose.family<List<Note>, String>((ref, tag) async {
  ref.watch(vaultRefreshTriggerProvider);
  await ref.watch(aiServerUrlProvider.future);
  final api = ref.watch(graphApiServiceProvider);
  final notes = await api.queryNotes(tag: tag, sort: 'desc', limit: 100);
  return notes ?? [];
});

/// Total note count (sum of all tag counts).
final vaultTotalCountProvider = Provider<int>((ref) {
  final tagsAsync = ref.watch(vaultTagsProvider);
  final tags = tagsAsync.valueOrNull;
  if (tags == null) return 0;
  // Use max of any single tag count as a lower bound
  // (notes can have multiple tags, so summing overcounts)
  return tags.fold<int>(0, (max, t) => t.count > max ? t.count : max);
});
