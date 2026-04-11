import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/core/widgets/note_audio_player.dart';
import 'package:parachute/core/widgets/note_links_section.dart';
import 'package:parachute/core/widgets/note_metadata_section.dart';
import 'package:parachute/core/widgets/wikilink_handler.dart';
import 'package:parachute/core/widgets/wikilink_syntax.dart';
import 'package:parachute/core/widgets/tag_picker.dart';
import 'package:parachute/core/widgets/tag_picker_sheet.dart';
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';
import 'package:parachute/features/vault/providers/vault_providers.dart';

/// Detail screen for viewing/editing a Note.
///
/// Used by Digest and Docs tabs. Supports markdown rendering in read mode,
/// inline editing, and tag management.
class NoteDetailScreen extends ConsumerStatefulWidget {
  final Note note;

  /// Called after a successful save so the parent can refresh.
  final VoidCallback? onChanged;

  const NoteDetailScreen({
    super.key,
    required this.note,
    this.onChanged,
  });

  @override
  ConsumerState<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends ConsumerState<NoteDetailScreen> {
  late bool _isEditing;
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late List<String> _tags;
  final FocusNode _contentFocusNode = FocusNode();

  late Note _note;
  late String _originalTitle;
  late String _originalContent;
  late List<String> _originalTags;
  late String _currentPath;

  bool _saving = false;

  bool get _hasChanges =>
      _titleController.text != _originalTitle ||
      _contentController.text != _originalContent ||
      !listEquals(_tags, _originalTags);

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _isEditing = false;
    _originalTitle = _note.path ?? '';
    _originalContent = _note.content;
    _originalTags = List<String>.from(_note.tags);
    _currentPath = _originalTitle;
    _titleController = TextEditingController(text: _originalTitle);
    _contentController = TextEditingController(text: _originalContent);
    _tags = List<String>.from(_note.tags);
  }

  Future<void> _refreshNote() async {
    final api = ref.read(graphApiServiceProvider);
    final refreshed = await api.getNote(_note.id);
    if (!mounted || refreshed == null) return;
    setState(() {
      _note = refreshed;
      _originalTitle = refreshed.path ?? '';
      _originalContent = refreshed.content;
      _originalTags = List<String>.from(refreshed.tags);
      _currentPath = _originalTitle;
      if (!_isEditing) {
        _titleController.text = _originalTitle;
        _contentController.text = _originalContent;
        _tags = List<String>.from(refreshed.tags);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_hasChanges || _saving) return;
    setState(() => _saving = true);

    final api = ref.read(graphApiServiceProvider);

    // Update content/path if changed
    final contentChanged = _contentController.text != _originalContent;
    final titleChanged = _titleController.text != _originalTitle;
    if (contentChanged || titleChanged) {
      await api.updateNote(
        widget.note.id,
        content: contentChanged ? _contentController.text : null,
        path: titleChanged ? _titleController.text : null,
      );
    }

    // Sync tags: add new, remove old
    final newTags = _tags.where((t) => !_originalTags.contains(t)).toList();
    final removedTags = _originalTags.where((t) => !_tags.contains(t)).toList();
    bool tagFailed = false;
    if (newTags.isNotEmpty) {
      final result = await api.tagNote(widget.note.id, newTags);
      if (result == null) tagFailed = true;
    }
    if (removedTags.isNotEmpty) {
      final result = await api.untagNote(widget.note.id, removedTags);
      if (result == null) tagFailed = true;
    }

    if (newTags.isNotEmpty || removedTags.isNotEmpty) {
      ref.invalidate(vaultTagsProvider);
    }

    _originalTitle = _titleController.text;
    _originalContent = _contentController.text;
    _originalTags = List<String>.from(_tags);

    setState(() {
      _saving = false;
      _isEditing = false;
    });

    if (tagFailed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Some tag changes may not have saved')),
      );
    }

    widget.onChanged?.call();
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isEditing
        ? _titleController.text
        : (_note.path ?? '');

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isEditing
              ? null
              : Text(
                  title.isNotEmpty ? title : 'Note',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          actions: [
            if (_isEditing)
              TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              )
            else
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => setState(() {
                  _isEditing = true;
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _contentFocusNode.requestFocus();
                  });
                }),
              ),
          ],
        ),
        body: _isEditing ? _buildEditor(theme) : _buildReader(theme),
      ),
    );
  }

  Widget _buildReader(ThemeData theme) {
    final title = _currentPath;
    return RefreshIndicator(
      onRefresh: _refreshNote,
      color: BrandColors.forest,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (title.isNotEmpty) ...[
            GestureDetector(
              onLongPress: () => _showRenameDialog(title),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: theme.textTheme.headlineSmall),
                  ),
                  GestureDetector(
                    onTap: () => _showRenameDialog(title),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.drive_file_rename_outline,
                        size: 18,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_note.tags.isNotEmpty) ...[
            GestureDetector(
              onTap: () => _openTagSheet(),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ..._note.tags.map((t) => _ReadOnlyTagChip(tag: t)),
                  Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          NoteAudioPlayer(note: _note),
          MarkdownBody(
            data: _note.content,
            selectable: true,
            inlineSyntaxes: [WikilinkSyntax()],
            builders: {
              'wikilink': WikilinkBuilder(
                onTap: (target) => handleWikilinkTap(
                  context: context,
                  api: ref.read(graphApiServiceProvider),
                  target: target,
                  onChanged: widget.onChanged,
                  replaceCurrentRoute: true,
                ),
              ),
            },
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyLarge,
            ),
          ),
          NoteMetadataSection(
            note: _note,
            onChanged: widget.onChanged,
          ),
          NoteLinksSection(
            noteId: _note.id,
            onChanged: widget.onChanged,
          ),
          const SizedBox(height: 16),
          Text(
            _formatTimestamp(_note.createdAt, _note.updatedAt),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _titleController,
          style: theme.textTheme.headlineSmall,
          decoration: const InputDecoration(
            hintText: 'Title (optional)',
            border: InputBorder.none,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const Divider(),
        _TagPickerInline(
          tags: _tags,
          onChanged: (tags) => setState(() => _tags = tags),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _contentController,
          focusNode: _contentFocusNode,
          maxLines: null,
          minLines: 12,
          style: theme.textTheme.bodyLarge,
          decoration: const InputDecoration(
            hintText: 'Write something...',
            border: InputBorder.none,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Future<void> _openTagSheet() async {
    final result = await showTagPickerSheet(
      context: context,
      ref: ref,
      currentTags: List<String>.from(_isEditing ? _tags : _note.tags),
    );
    if (result != null && mounted) {
      setState(() => _tags = result);
      if (!_isEditing) {
        // Save immediately when editing tags from read mode
        await _save();
      }
    }
  }

  Future<void> _showRenameDialog(String currentPath) async {
    final controller = TextEditingController(text: currentPath);
    String? newPath;
    try {
      newPath = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            title: const Text('Rename note'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Links in other notes will update automatically.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Path',
                    hintText: 'e.g. People/Atlas',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Rename'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }

    if (newPath == null || newPath.isEmpty || newPath == currentPath) return;
    if (!mounted) return;

    final api = ref.read(graphApiServiceProvider);
    final result = await api.updateNote(widget.note.id, path: newPath);

    if (!mounted) return;
    if (result != null) {
      _originalTitle = newPath;
      _currentPath = newPath;
      _titleController.text = newPath;
      setState(() {});
      widget.onChanged?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Renamed to $newPath')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rename failed — check connection')),
      );
    }
  }

  String _formatTimestamp(DateTime created, DateTime? updated) {
    final fmt = _fmtDate(created);
    if (updated != null && updated.isAfter(created)) {
      return 'Created $fmt  ·  Updated ${_fmtDate(updated)}';
    }
    return 'Created $fmt';
  }

  String _fmtDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

/// Inline TagPicker that fetches vault tags for suggestions.
class _TagPickerInline extends ConsumerWidget {
  final List<String> tags;
  final void Function(List<String>) onChanged;

  const _TagPickerInline({required this.tags, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(vaultTagsProvider);
    final available = tagsAsync.valueOrNull
            ?.map((t) => TagPickerItem(name: t.tag, count: t.count))
            .toList() ??
        [];
    return TagPicker(
      selectedTags: tags,
      onChanged: onChanged,
      availableTags: available,
      compact: true,
    );
  }
}

/// Read-only tag chip with hierarchy-aware display.
class _ReadOnlyTagChip extends StatelessWidget {
  final String tag;
  const _ReadOnlyTagChip({required this.tag});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final parts = tag.split('/');
    final isHierarchical = parts.length > 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isDark
            ? BrandColors.forest.withValues(alpha: 0.15)
            : BrandColors.forestMist.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: isHierarchical
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '#${parts.first}/',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
                Text(
                  parts.sublist(1).join('/'),
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? BrandColors.nightText
                        : BrandColors.forest,
                  ),
                ),
              ],
            )
          : Text(
              '#$tag',
              style: TextStyle(
                fontSize: TypographyTokens.labelSmall,
                fontWeight: FontWeight.w500,
                color: isDark ? BrandColors.nightText : BrandColors.forest,
              ),
            ),
    );
  }
}
