import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/screens/note_detail_screen.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';
import '../providers/digest_providers.dart';

/// Digest tab — inbox of AI-surfaced content.
///
/// Shows notes tagged #digest (excluding #archived). Swipe to archive.
class DigestScreen extends ConsumerWidget {
  const DigestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(digestNotesProvider);

    return notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (notes) {
        if (notes.isEmpty) {
          return _buildEmpty(context);
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.read(digestRefreshTriggerProvider.notifier).state++;
            await ref.read(digestNotesProvider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notes.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, index) => _DigestNoteItem(
              note: notes[index],
              onArchived: () {
                ref.read(digestRefreshTriggerProvider.notifier).state++;
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No digests yet', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'AI-surfaced content will appear here as agents create digest notes.',
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

class _DigestNoteItem extends ConsumerWidget {
  final Note note;
  final VoidCallback onArchived;

  const _DigestNoteItem({required this.note, required this.onArchived});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final title = note.path ?? '';
    final preview = note.content.length > 120
        ? '${note.content.substring(0, 120)}...'
        : note.content;

    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: BrandColors.forest,
        child: const Icon(Icons.archive_outlined, color: Colors.white),
      ),
      onDismissed: (_) async {
        final api = ref.read(graphApiServiceProvider);
        await api.tagNote(note.id, ['archived']);
        onArchived();
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title.isNotEmpty ? title : preview,
          maxLines: title.isNotEmpty ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: title.isNotEmpty ? theme.textTheme.titleMedium : null,
        ),
        subtitle: title.isNotEmpty
            ? Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis)
            : null,
        trailing: Text(
          _relativeDate(note.createdAt),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => NoteDetailScreen(
                note: note,
                onChanged: onArchived,
              ),
            ),
          );
        },
      ),
    );
  }

  String _relativeDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}
