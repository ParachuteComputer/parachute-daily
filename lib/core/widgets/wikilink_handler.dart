import 'package:flutter/material.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/screens/note_detail_screen.dart';
import 'package:parachute/core/services/graph_api_service.dart';
import 'package:parachute/core/theme/design_tokens.dart';

/// Resolves a wikilink target to a Note and navigates to it.
///
/// Searches by path first (exact match), then falls back to content search.
/// When multiple notes match with similar relevance, shows a disambiguation
/// bottom sheet so the user can pick the right one.
/// If no note is found, offers to create one with the target as its path.
///
/// Set [replaceCurrentRoute] to true when navigating from within a detail
/// screen — this uses pushReplacement to avoid unbounded stack growth.
Future<void> handleWikilinkTap({
  required BuildContext context,
  required GraphApiService api,
  required String target,
  VoidCallback? onChanged,
  bool replaceCurrentRoute = false,
}) async {
  // Search for the note by its path/title
  final results = await api.searchNotes(target, limit: 10);
  if (results == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not search — check connection')),
      );
    }
    return;
  }
  if (results.isEmpty) {
    if (!context.mounted) return;
    // Offer to create the note
    final shouldCreate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Create "$target"?'),
        content: const Text('No matching note found. Create a new one?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (shouldCreate != true || !context.mounted) return;

    final created = await api.createNote('', path: target);
    if (created == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create note — check connection')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    _navigateToNote(context, created, onChanged,
        replace: replaceCurrentRoute);
    return;
  }

  // Find matches ranked by relevance
  final ranked = _rankMatches(results, target);

  if (!context.mounted) return;

  // Single strong match → navigate directly
  if (ranked.length == 1 || _isClearWinner(ranked, target)) {
    _navigateToNote(context, ranked.first, onChanged,
        replace: replaceCurrentRoute);
    return;
  }

  // Multiple ambiguous matches → show picker
  final chosen = await _showDisambiguationSheet(context, target, ranked);
  if (chosen != null && context.mounted) {
    _navigateToNote(context, chosen, onChanged,
        replace: replaceCurrentRoute);
  }
}

void _navigateToNote(
  BuildContext context,
  Note note,
  VoidCallback? onChanged, {
  bool replace = false,
}) {
  final route = MaterialPageRoute(
    builder: (_) => NoteDetailScreen(
      note: note,
      onChanged: onChanged,
    ),
  );
  if (replace) {
    Navigator.of(context).pushReplacement(route);
  } else {
    Navigator.of(context).push(route);
  }
}

/// Score how well a note matches a wikilink target.
///
/// Lower is better: 0 = exact path, 4 = content match only.
int _matchScore(Note note, String target) {
  final path = note.path ?? '';
  final pathLower = path.toLowerCase();
  final targetLower = target.toLowerCase();
  if (path == target) return 0; // exact
  if (pathLower == targetLower) return 1; // case-insensitive exact
  if (pathLower.endsWith('/$targetLower')) return 2; // path suffix
  if (pathLower.contains(targetLower)) return 3; // contains
  return 4; // content match only
}

/// Rank search results by match quality against the target.
List<Note> _rankMatches(List<Note> results, String target) {
  final sorted = List<Note>.from(results)
    ..sort((a, b) => _matchScore(a, target).compareTo(_matchScore(b, target)));
  return sorted;
}

/// Returns true if the top result is clearly better than the rest.
bool _isClearWinner(List<Note> ranked, String target) {
  if (ranked.length < 2) return true;
  return _matchScore(ranked[0], target) < _matchScore(ranked[1], target);
}

/// Shows a bottom sheet with disambiguation options.
Future<Note?> _showDisambiguationSheet(
  BuildContext context,
  String target,
  List<Note> options,
) {
  return showModalBottomSheet<Note>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final isDark = theme.brightness == Brightness.dark;

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outline.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Multiple matches for "$target"',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...options.take(8).map((note) {
                final path = note.path ?? '';
                final snippet = _snippetFromContent(note.content);
                final hasPath = path.isNotEmpty;
                final tags = note.tags.where((t) => t != 'captured').take(3).toList();

                return ListTile(
                  leading: Icon(
                    Icons.description_outlined,
                    color: isDark
                        ? BrandColors.turquoiseLight
                        : BrandColors.turquoiseDeep,
                    size: 20,
                  ),
                  title: Text(
                    hasPath ? path : snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasPath && note.content.isNotEmpty)
                        Text(
                          snippet,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      if (tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            tags.map((t) => '#$t').join('  '),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isDark
                                  ? BrandColors.forest.withValues(alpha: 0.7)
                                  : BrandColors.forest.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                    ],
                  ),
                  onTap: () => Navigator.of(ctx).pop(note),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

String _snippetFromContent(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return 'Untitled note';
  final firstLine = trimmed.split('\n').first.replaceFirst(RegExp(r'^#+\s*'), '');
  if (firstLine.length > 80) return '${firstLine.substring(0, 80)}...';
  return firstLine;
}
