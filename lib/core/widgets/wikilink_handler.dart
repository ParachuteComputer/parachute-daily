import 'package:flutter/material.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/screens/note_detail_screen.dart';
import 'package:parachute/core/services/graph_api_service.dart';

/// Resolves a wikilink target to a Note and navigates to it.
///
/// Searches by path first (exact match), then falls back to content search.
/// Shows a snackbar if no matching note is found.
Future<void> handleWikilinkTap({
  required BuildContext context,
  required GraphApiService api,
  required String target,
  VoidCallback? onChanged,
}) async {
  // Search for the note by its path/title
  final results = await api.searchNotes(target, limit: 10);
  if (results == null || results.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Note not found: $target'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return;
  }

  // Find exact path match first, then title-contains match
  final note = _findBestMatch(results, target);

  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => NoteDetailScreen(
        note: note,
        onChanged: onChanged,
      ),
    ),
  );
}

/// Find the best matching note for a wikilink target.
///
/// Priority: exact path match > case-insensitive path match > first result.
Note _findBestMatch(List<Note> results, String target) {
  final targetLower = target.toLowerCase();

  // Exact path match
  for (final note in results) {
    if (note.path == target) return note;
  }

  // Case-insensitive path match
  for (final note in results) {
    if (note.path?.toLowerCase() == targetLower) return note;
  }

  // Path contains target
  for (final note in results) {
    if (note.path?.toLowerCase().contains(targetLower) == true) return note;
  }

  // Fall back to first search result
  return results.first;
}
