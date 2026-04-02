import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/screens/note_detail_screen.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import '../providers/docs_providers.dart';

/// Docs tab — searchable list of persistent notes tagged #doc*.
class DocsScreen extends ConsumerStatefulWidget {
  const DocsScreen({super.key});

  @override
  ConsumerState<DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends ConsumerState<DocsScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(docsSearchQueryProvider.notifier).state = query;
  }

  void _refresh() {
    ref.read(docsRefreshTriggerProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchQuery = ref.watch(docsSearchQueryProvider);
    final isSearching = searchQuery.trim().isNotEmpty;

    return Column(
      children: [
        // Header with search
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                if (!_showSearch)
                  Expanded(
                    child: Text('Docs', style: theme.textTheme.headlineSmall),
                  ),
                if (_showSearch)
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search docs...',
                        border: InputBorder.none,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                            setState(() => _showSearch = false);
                          },
                        ),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                if (!_showSearch)
                  IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() => _showSearch = true),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        // Content
        Expanded(
          child: isSearching ? _buildSearchResults() : _buildDocsList(),
        ),
      ],
    );
  }

  Widget _buildDocsList() {
    final notesAsync = ref.watch(docsNotesProvider);

    return notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (notes) {
        if (notes.isEmpty) return _buildEmpty();
        return RefreshIndicator(
          onRefresh: () async {
            _refresh();
            await ref.read(docsNotesProvider.future);
          },
          child: _buildNotesList(notes),
        );
      },
    );
  }

  Widget _buildSearchResults() {
    final resultsAsync = ref.watch(docsSearchProvider);

    return resultsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (results) {
        if (results == null || results.isEmpty) {
          return Center(
            child: Text(
              results == null ? '' : 'No results found',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          );
        }
        return _buildNotesList(results);
      },
    );
  }

  Widget _buildNotesList(List<Note> notes) {
    // Group by sub-tag (doc, doc/meeting, doc/draft, etc.)
    final grouped = <String, List<Note>>{};
    for (final note in notes) {
      final docTag = note.tags.firstWhere(
        (t) => t.startsWith('doc'),
        orElse: () => 'doc',
      );
      grouped.putIfAbsent(docTag, () => []).add(note);
    }

    final sortedKeys = grouped.keys.toList()..sort();
    final theme = Theme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: sortedKeys.length,
      itemBuilder: (context, sectionIndex) {
        final tag = sortedKeys[sectionIndex];
        final sectionNotes = grouped[tag]!;
        final showHeader = sortedKeys.length > 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  '#$tag',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: BrandColors.forest,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ...sectionNotes.map((note) => _DocNoteItem(
                  note: note,
                  onChanged: _refresh,
                )),
          ],
        );
      },
    );
  }

  Widget _buildEmpty() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('No docs yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Tag a note with #doc to see it here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocNoteItem extends StatelessWidget {
  final Note note;
  final VoidCallback onChanged;

  const _DocNoteItem({required this.note, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = note.path ?? '';
    final preview = note.content.length > 100
        ? '${note.content.substring(0, 100)}...'
        : note.content;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(
        title.isNotEmpty ? title : preview,
        maxLines: title.isNotEmpty ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: title.isNotEmpty ? theme.textTheme.titleMedium : null,
      ),
      subtitle: title.isNotEmpty
          ? Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Text(
        _shortDate(note.updatedAt ?? note.createdAt),
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
      ),
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
    );
  }

  String _shortDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
