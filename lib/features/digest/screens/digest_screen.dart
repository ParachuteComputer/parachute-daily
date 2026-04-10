import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/screens/note_detail_screen.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';
import 'package:parachute/features/vault/providers/vault_providers.dart';
import '../providers/digest_providers.dart';

/// Reader tab — inbox of content to process.
///
/// Shows notes tagged #reader. Pinned items float to top, grouped by sub-tag.
/// Archive toggle in header.
///
/// Gestures per card:
/// - Swipe left: archive (or unarchive) — with undo snackbar
/// - Swipe right: pin (or unpin) — in-place, no dismiss
/// - More menu (⋯): explicit Pin / Archive actions for discoverability
class DigestScreen extends ConsumerStatefulWidget {
  const DigestScreen({super.key});

  @override
  ConsumerState<DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends ConsumerState<DigestScreen> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.read(digestRefreshTriggerProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final notesAsync = ref.watch(digestNotesProvider);
    final showArchived = ref.watch(digestShowArchivedProvider);

    return Column(
      children: [
        // Header
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Reader', style: theme.textTheme.headlineSmall),
                ),
                // Count badge
                notesAsync.whenOrNull(
                      data: (notes) => notes.isNotEmpty
                          ? Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                '${notes.length}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark
                                      ? BrandColors.nightTextSecondary
                                      : BrandColors.driftwood,
                                ),
                              ),
                            )
                          : null,
                    ) ??
                    const SizedBox.shrink(),
                // Archive toggle
                IconButton(
                  icon: Icon(
                    showArchived ? Icons.inventory_2 : Icons.inventory_2_outlined,
                    size: 20,
                  ),
                  tooltip: showArchived ? 'Hide archived' : 'Show archived',
                  onPressed: () {
                    ref.read(digestShowArchivedProvider.notifier).state =
                        !showArchived;
                  },
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // Content
        Expanded(
          child: notesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _buildError(e),
            data: (notes) {
              if (notes.isEmpty) return _buildEmpty(showArchived);
              return RefreshIndicator(
                onRefresh: () async {
                  _refresh();
                  await ref.read(digestNotesProvider.future);
                },
                child: _buildNotesList(notes),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNotesList(List<Note> notes) {
    final grouped = groupReaderBySubTag(notes);
    final sortedKeys = grouped.keys.toList()..sort();
    final showHeaders = sortedKeys.length > 1 ||
        (sortedKeys.length == 1 && sortedKeys.first.isNotEmpty);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: sortedKeys.length,
      itemBuilder: (context, sectionIndex) {
        final label = sortedKeys[sectionIndex];
        final sectionNotes = grouped[label]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeaders && label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: BrandColors.forest,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ...sectionNotes.map((note) => _DigestCard(
                  note: note,
                  onChanged: _refresh,
                )),
          ],
        );
      },
    );
  }

  Widget _buildEmpty(bool showArchived) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              showArchived ? Icons.inventory_2_outlined : Icons.inbox_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              showArchived ? 'No archived items' : 'Inbox zero',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              showArchived
                  ? 'Archived reader items will appear here.'
                  : 'Content to read and process will show up here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(Object error) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: BrandColors.error),
            const SizedBox(height: 16),
            Text(
              'Could not load reader',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: BrandColors.turquoise,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Digest Card
// =============================================================================

class _DigestCard extends ConsumerWidget {
  final Note note;
  final VoidCallback onChanged;

  const _DigestCard({required this.note, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final title = note.path ?? '';
    final preview = _smartTruncate(note.content, 150);
    final date = note.updatedAt ?? note.createdAt;
    final isArchived = note.isArchived;
    final isPinned = note.isPinned;

    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.horizontal,
      // Swipe-left: archive (or unarchive). Swipe-right: pin toggle.
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        color: isPinned ? BrandColors.driftwood : BrandColors.turquoise,
        child: Icon(
          isPinned ? Icons.push_pin_outlined : Icons.push_pin,
          color: Colors.white,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: isArchived ? BrandColors.forestLight : BrandColors.forest,
        child: Icon(
          isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Pin/unpin — toggle in place, don't dismiss.
          await _togglePin(context, ref);
          return false;
        }
        // Archive/unarchive — dismiss and show undo.
        return true;
      },
      onDismissed: (_) async {
        await _toggleArchive(context, ref);
      },
      child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: note.isPinned
                ? Border.all(
                    color: (isDark ? BrandColors.nightTurquoise : BrandColors.turquoise)
                        .withValues(alpha: 0.5),
                    width: 1.5,
                  )
                : Border.all(
                    color: (isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood)
                        .withValues(alpha: 0.12),
                  ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteDetailScreen(
                      note: note,
                      onChanged: onChanged,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top row: pin indicator + date + archived badge
                    Row(
                      children: [
                        if (note.isPinned) ...[
                          Icon(
                            Icons.push_pin,
                            size: 14,
                            color: isDark
                                ? BrandColors.nightTurquoise
                                : BrandColors.turquoise,
                          ),
                          const SizedBox(width: 4),
                        ],
                        if (isArchived) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: BrandColors.driftwood.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'archived',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: BrandColors.driftwood,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        // Sub-tag chip
                        ..._buildSubTagChip(theme, isDark),
                        const Spacer(),
                        Text(
                          _relativeDate(date),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark
                                ? BrandColors.nightTextSecondary
                                : BrandColors.driftwood,
                          ),
                        ),
                        _buildMenuButton(context, ref, isDark),
                      ],
                    ),
                    // Title
                    if (title.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                        ),
                      ),
                    ],
                    // Content preview
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _stripMarkdown(preview),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? BrandColors.nightTextSecondary
                              : BrandColors.driftwood,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }

  /// Three-dot menu with explicit Pin and Archive actions.
  Widget _buildMenuButton(BuildContext context, WidgetRef ref, bool isDark) {
    final color = isDark
        ? BrandColors.nightTextSecondary
        : BrandColors.driftwood;
    return SizedBox(
      width: 28,
      height: 24,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(Icons.more_horiz, size: 18, color: color),
        tooltip: 'More actions',
        onSelected: (value) async {
          switch (value) {
            case 'pin':
              await _togglePin(context, ref);
            case 'archive':
              await _toggleArchive(context, ref);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'pin',
            child: Row(
              children: [
                Icon(
                  note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Text(note.isPinned ? 'Unpin' : 'Pin'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'archive',
            child: Row(
              children: [
                Icon(
                  note.isArchived
                      ? Icons.unarchive_outlined
                      : Icons.archive_outlined,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Text(note.isArchived ? 'Unarchive' : 'Archive'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSubTagChip(ThemeData theme, bool isDark) {
    final subTag = note.tags.firstWhere(
      (t) => t.startsWith('reader/'),
      orElse: () => '',
    );
    if (subTag.isEmpty) return [];

    final label = subTag.substring('reader/'.length);
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: BrandColors.forest.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: BrandColors.forest,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      const SizedBox(width: 4),
    ];
  }

  Future<void> _togglePin(BuildContext context, WidgetRef ref) async {
    final api = ref.read(graphApiServiceProvider);
    final result = note.isPinned
        ? await api.untagNote(note.id, ['pinned'])
        : await api.tagNote(note.id, ['pinned']);
    if (result == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update pin — check connection')),
      );
      return;
    }
    ref.invalidate(vaultTagsProvider);
    onChanged();
  }

  /// Toggle archive with an undo snackbar (primary path: swipe-left).
  Future<void> _toggleArchive(BuildContext context, WidgetRef ref) async {
    final api = ref.read(graphApiServiceProvider);
    final wasArchived = note.isArchived;

    final result = wasArchived
        ? await api.untagNote(note.id, ['archived'])
        : await api.tagNote(note.id, ['archived']);
    if (result == null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update archive — check connection')),
      );
      return;
    }
    ref.invalidate(vaultTagsProvider);
    onChanged();

    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(wasArchived ? 'Unarchived' : 'Archived'),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final undoResult = wasArchived
                ? await api.tagNote(note.id, ['archived'])
                : await api.untagNote(note.id, ['archived']);
            if (undoResult != null) {
              ref.invalidate(vaultTagsProvider);
            }
            onChanged();
          },
        ),
      ),
    );
  }

  /// Truncate at a word boundary.
  static String _smartTruncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    final truncated = text.substring(0, maxLength);
    final lastSpace = truncated.lastIndexOf(' ');
    if (lastSpace > maxLength * 0.6) {
      return '${truncated.substring(0, lastSpace)}...';
    }
    return '$truncated...';
  }

  /// Strip common markdown syntax for a cleaner preview.
  static String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '') // headings
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1') // bold
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1') // italic
        .replaceAll(RegExp(r'`(.+?)`'), r'$1') // inline code
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '') // list items
        .replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'$1') // links
        .replaceAll(RegExp(r'\n{2,}'), '\n') // collapse blank lines
        .trim();
  }

  static String _relativeDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
