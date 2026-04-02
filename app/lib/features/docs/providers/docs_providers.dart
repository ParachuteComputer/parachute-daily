import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/providers/feature_flags_provider.dart'
    show aiServerUrlProvider;
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';

/// Trigger to refresh the docs list.
final docsRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Fetches notes tagged with doc (prefix match — includes doc/meeting, doc/draft, etc.).
/// Returns empty list on error or no results.
final docsNotesProvider = FutureProvider.autoDispose<List<Note>>((ref) async {
  ref.watch(docsRefreshTriggerProvider);
  // Ensure the server URL has resolved before querying.
  await ref.watch(aiServerUrlProvider.future);
  final api = ref.watch(graphApiServiceProvider);
  final notes = await api.queryNotes(tag: 'doc', sort: 'desc');
  return notes ?? [];
});

/// Search query for the docs tab.
final docsSearchQueryProvider = StateProvider<String>((ref) => '');

/// Searches notes with the doc tag scope.
/// Returns null when query is empty (use docsNotesProvider instead).
final docsSearchProvider = FutureProvider.autoDispose<List<Note>?>((ref) async {
  final query = ref.watch(docsSearchQueryProvider);
  if (query.trim().isEmpty) return null;
  // Ensure the server URL has resolved before querying.
  await ref.watch(aiServerUrlProvider.future);
  final api = ref.watch(graphApiServiceProvider);
  return api.searchNotes(query, tag: 'doc');
});
