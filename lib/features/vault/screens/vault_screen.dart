import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/screens/note_detail_screen.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import '../providers/vault_providers.dart';

/// Vault tab — dashboard, search, browse by tag.
///
/// Three modes:
/// - Dashboard (default): summary stats, tag cards, recent notes
/// - Search: full-text search results
/// - Tag drill-down: notes filtered by a specific tag
class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;
  String? _selectedTag;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(vaultSearchQueryProvider.notifier).state = query;
  }

  void _openSearch() {
    setState(() => _showSearch = true);
  }

  void _closeSearch() {
    _searchController.clear();
    _onSearchChanged('');
    setState(() => _showSearch = false);
  }

  void _selectTag(String tag) {
    setState(() => _selectedTag = tag);
  }

  void _clearTag() {
    setState(() => _selectedTag = null);
  }

  void _refresh() {
    ref.read(vaultRefreshTriggerProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchQuery = ref.watch(vaultSearchQueryProvider);
    final isSearching = searchQuery.trim().isNotEmpty;

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: _buildHeader(theme),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: isSearching
              ? _buildSearchResults()
              : _selectedTag != null
                  ? _buildTagDrillDown(_selectedTag!)
                  : _buildDashboard(),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    if (_showSearch) {
      return Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search notes...',
                border: InputBorder.none,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: _closeSearch,
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
        ],
      );
    }

    if (_selectedTag != null) {
      return Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: _clearTag,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('#$_selectedTag', style: theme.textTheme.headlineSmall),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text('Vault', style: theme.textTheme.headlineSmall),
        ),
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: _openSearch,
        ),
      ],
    );
  }

  // ===========================================================================
  // Dashboard
  // ===========================================================================

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        await ref.read(vaultRecentNotesProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _buildSummaryStats(),
          const SizedBox(height: 16),
          _buildTagCards(),
          const SizedBox(height: 20),
          _buildRecentNotes(),
        ],
      ),
    );
  }

  Widget _buildSummaryStats() {
    final tagsAsync = ref.watch(vaultTagsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return tagsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (tags) {
        final totalNotes = tags.fold<int>(0, (sum, t) => sum + t.count);
        final tagCount = tags.where((t) => t.count > 0).length;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '$totalNotes notes · $tagCount tags',
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagCards() {
    final tagsAsync = ref.watch(vaultTagsProvider);

    return tagsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Could not load tags: $e'),
      ),
      data: (tags) {
        final activeTags = tags.where((t) =>
            t.count > 0 &&
            t.tag != 'pinned' &&
            t.tag != 'archived' &&
            t.tag != 'view'
        ).toList();

        if (activeTags.isEmpty) return const SizedBox.shrink();

        // Split into primary (captured, reader) and topic tags
        const primaryNames = {'captured', 'reader'};
        final primary = activeTags.where((t) => primaryNames.contains(t.tag)).toList();
        final topics = activeTags.where((t) => !primaryNames.contains(t.tag)).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Primary tag cards — large
            if (primary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: primary.map((tag) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: tag == primary.last ? 0 : 8,
                      ),
                      child: _TagCard(
                        tag: tag,
                        isPrimary: true,
                        onTap: () => _selectTag(tag.tag),
                      ),
                    ),
                  )).toList(),
                ),
              ),

            // Topic tags — smaller chips
            if (topics.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: topics.map((tag) => _TagChip(
                    tag: tag,
                    onTap: () => _selectTag(tag.tag),
                  )).toList(),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRecentNotes() {
    final notesAsync = ref.watch(vaultRecentNotesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Recent',
            style: TextStyle(
              fontSize: TypographyTokens.bodySmall,
              fontWeight: FontWeight.w600,
              color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        notesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: $e'),
          ),
          data: (notes) {
            if (notes.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No notes yet',
                    style: TextStyle(
                      color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                    ),
                  ),
                ),
              );
            }
            return Column(
              children: notes.map((note) => _VaultNoteItem(
                note: note,
                onChanged: _refresh,
              )).toList(),
            );
          },
        ),
      ],
    );
  }

  // ===========================================================================
  // Search
  // ===========================================================================

  Widget _buildSearchResults() {
    final resultsAsync = ref.watch(vaultSearchProvider);
    final theme = Theme.of(context);

    return resultsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (results) {
        if (results == null || results.isEmpty) {
          return Center(
            child: Text(
              results == null ? '' : 'No results found',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          );
        }
        return ListView(
          children: results.map((note) => _VaultNoteItem(
            note: note,
            onChanged: _refresh,
          )).toList(),
        );
      },
    );
  }

  // ===========================================================================
  // Tag drill-down
  // ===========================================================================

  Widget _buildTagDrillDown(String tag) {
    final notesAsync = ref.watch(vaultTagNotesProvider(tag));

    return notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (notes) {
        if (notes.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.label_outline, size: 48, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('No #$tag notes', style: Theme.of(context).textTheme.headlineSmall),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            _refresh();
            await ref.read(vaultTagNotesProvider(tag).future);
          },
          child: ListView(
            children: notes.map((note) => _VaultNoteItem(
              note: note,
              onChanged: _refresh,
            )).toList(),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Tag Card (primary tags — captured, reader)
// =============================================================================

class _TagCard extends StatelessWidget {
  final dynamic tag; // TagInfo
  final bool isPrimary;
  final VoidCallback onTap;

  const _TagCard({required this.tag, this.isPrimary = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? BrandColors.nightTurquoise : BrandColors.turquoise;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '#${tag.tag}',
              style: TextStyle(
                fontSize: TypographyTokens.bodyMedium,
                fontWeight: FontWeight.w600,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${tag.count} notes',
              style: TextStyle(
                fontSize: TypographyTokens.bodySmall,
                color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Tag Chip (topic tags)
// =============================================================================

class _TagChip extends StatelessWidget {
  final dynamic tag; // TagInfo
  final VoidCallback onTap;

  const _TagChip({required this.tag, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: BrandColors.forest.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Text(
          '#${tag.tag} (${tag.count})',
          style: TextStyle(
            fontSize: TypographyTokens.labelSmall,
            fontWeight: FontWeight.w500,
            color: isDark ? BrandColors.nightText : BrandColors.forest,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Note Item
// =============================================================================

class _VaultNoteItem extends StatelessWidget {
  final Note note;
  final VoidCallback onChanged;

  const _VaultNoteItem({required this.note, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final title = note.path ?? '';
    final content = note.content;
    final isShort = content.length < 200;
    final preview = isShort ? content : _smartTruncate(content, 200);
    final date = note.updatedAt ?? note.createdAt;

    return InkWell(
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + date row
            Row(
              children: [
                Expanded(
                  child: title.isNotEmpty
                      ? Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark ? BrandColors.nightText : BrandColors.charcoal,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Text(
                  _relativeDate(date),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  ),
                ),
              ],
            ),
            if (preview.isNotEmpty) ...[
              SizedBox(height: title.isNotEmpty ? 2 : 0),
              Text(
                _stripMarkdown(preview),
                maxLines: isShort ? 6 : 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
                  height: 1.4,
                ),
              ),
            ],
            // Tag chips
            if (note.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: note.tags
                    .where((t) => t != 'pinned' && t != 'archived')
                    .map((t) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: BrandColors.forest.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '#$t',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: BrandColors.forest,
                              fontSize: 10,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _smartTruncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    final truncated = text.substring(0, maxLength);
    final lastSpace = truncated.lastIndexOf(' ');
    if (lastSpace > maxLength * 0.6) {
      return '${truncated.substring(0, lastSpace)}...';
    }
    return '$truncated...';
  }

  static String _stripMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\*\*(.+?)\*\*'), r'$1')
        .replaceAll(RegExp(r'\*(.+?)\*'), r'$1')
        .replaceAll(RegExp(r'`(.+?)`'), r'$1')
        .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'\[(.+?)\]\(.+?\)'), r'$1')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
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
