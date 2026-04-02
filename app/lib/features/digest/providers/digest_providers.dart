import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';

/// Trigger to refresh the digest list.
final digestRefreshTriggerProvider = StateProvider<int>((ref) => 0);

/// Fetches notes tagged #digest, excluding #archived.
/// Returns empty list on error or no results.
final digestNotesProvider = FutureProvider.autoDispose<List<Note>>((ref) async {
  ref.watch(digestRefreshTriggerProvider);
  final api = ref.watch(graphApiServiceProvider);
  final notes = await api.queryNotes(
    tag: 'digest',
    excludeTag: 'archived',
    sort: 'desc',
  );
  return notes ?? [];
});
