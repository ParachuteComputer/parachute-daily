import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/screens/note_detail_screen.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';

/// Displays backlinks ("Mentioned in") and forward links ("Links to") for a note.
///
/// Fetches links from the vault API, resolves each linked note's path/title,
/// and renders tappable items that navigate to the linked note.
class NoteLinksSection extends ConsumerStatefulWidget {
  final String noteId;
  final VoidCallback? onChanged;

  const NoteLinksSection({super.key, required this.noteId, this.onChanged});

  @override
  ConsumerState<NoteLinksSection> createState() => _NoteLinksSectionState();
}

class _NoteLinksSectionState extends ConsumerState<NoteLinksSection> {
  List<Note>? _backlinks;
  List<Note>? _forwardLinks;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _fetchLinks();
  }

  Future<void> _fetchLinks() async {
    final api = ref.read(graphApiServiceProvider);
    final links = await api.getLinks(widget.noteId);
    if (!mounted) return;

    if (links == null) {
      setState(() {
        _loading = false;
        _error = true;
      });
      return;
    }

    // Separate backlinks (other → this) from forward links (this → other)
    final backlinkIds = <String>[];
    final forwardIds = <String>[];
    for (final link in links) {
      if (link.targetId == widget.noteId && link.sourceId != widget.noteId) {
        backlinkIds.add(link.sourceId);
      } else if (link.sourceId == widget.noteId && link.targetId != widget.noteId) {
        forwardIds.add(link.targetId);
      }
    }

    // Deduplicate
    final uniqueBacklinkIds = backlinkIds.toSet().toList();
    final uniqueForwardIds = forwardIds.toSet().toList();

    // Fetch note details in parallel
    final backFutures = uniqueBacklinkIds.map((id) => api.getNote(id));
    final fwdFutures = uniqueForwardIds.map((id) => api.getNote(id));
    final backResults = await Future.wait(backFutures);
    final fwdResults = await Future.wait(fwdFutures);

    if (!mounted) return;
    setState(() {
      _backlinks = backResults.whereType<Note>().toList()
        ..sort((a, b) => (a.path ?? '').compareTo(b.path ?? ''));
      _forwardLinks = fwdResults.whereType<Note>().toList()
        ..sort((a, b) => (a.path ?? '').compareTo(b.path ?? ''));
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      );
    }

    if (_error) return const SizedBox.shrink();

    final hasBacklinks = _backlinks != null && _backlinks!.isNotEmpty;
    final hasForward = _forwardLinks != null && _forwardLinks!.isNotEmpty;

    if (!hasBacklinks && !hasForward) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Divider(),
        if (hasBacklinks) ...[
          const SizedBox(height: 12),
          _LinkGroup(
            label: 'Mentioned in',
            icon: Icons.arrow_back_rounded,
            notes: _backlinks!,
            onTap: _navigateToNote,
          ),
        ],
        if (hasForward) ...[
          const SizedBox(height: 12),
          _LinkGroup(
            label: 'Links to',
            icon: Icons.arrow_forward_rounded,
            notes: _forwardLinks!,
            onTap: _navigateToNote,
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  void _navigateToNote(Note note) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteDetailScreen(
          note: note,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

/// A labeled group of linked notes.
class _LinkGroup extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Note> notes;
  final void Function(Note) onTap;

  const _LinkGroup({
    required this.label,
    required this.icon,
    required this.notes,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.outline),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
                fontWeight: FontWeight.w600,
                letterSpacing: TypographyTokens.letterSpacingWide,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${notes.length}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...notes.map((note) => _LinkTile(
          note: note,
          isDark: isDark,
          onTap: () => onTap(note),
        )),
      ],
    );
  }
}

/// A single tappable linked note.
class _LinkTile extends StatelessWidget {
  final Note note;
  final bool isDark;
  final VoidCallback onTap;

  const _LinkTile({
    required this.note,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final path = note.path ?? '';
    final display = path.isNotEmpty ? path : _snippetFromContent(note.content);
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 16,
              color: isDark
                  ? BrandColors.turquoiseLight
                  : BrandColors.turquoiseDeep,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                display,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark
                      ? BrandColors.turquoiseLight
                      : BrandColors.turquoiseDeep,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  String _snippetFromContent(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return 'Untitled note';
    // Take first line, strip markdown headers
    final firstLine = trimmed.split('\n').first.replaceFirst(RegExp(r'^#+\s*'), '');
    if (firstLine.length > 60) return '${firstLine.substring(0, 60)}...';
    return firstLine;
  }
}
