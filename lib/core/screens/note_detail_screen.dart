import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/widgets/tag_input.dart';
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';

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

  late String _originalTitle;
  late String _originalContent;
  late List<String> _originalTags;

  bool _saving = false;

  bool get _hasChanges =>
      _titleController.text != _originalTitle ||
      _contentController.text != _originalContent ||
      !listEquals(_tags, _originalTags);

  @override
  void initState() {
    super.initState();
    _isEditing = false;
    _originalTitle = widget.note.path ?? '';
    _originalContent = widget.note.content;
    _originalTags = List<String>.from(widget.note.tags);
    _titleController = TextEditingController(text: _originalTitle);
    _contentController = TextEditingController(text: _originalContent);
    _tags = List<String>.from(widget.note.tags);
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
    if (newTags.isNotEmpty) await api.tagNote(widget.note.id, newTags);
    if (removedTags.isNotEmpty) await api.untagNote(widget.note.id, removedTags);

    _originalTitle = _titleController.text;
    _originalContent = _contentController.text;
    _originalTags = List<String>.from(_tags);

    setState(() {
      _saving = false;
      _isEditing = false;
    });

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
        : (widget.note.path ?? '');

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
    final title = widget.note.path ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (title.isNotEmpty) ...[
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
        ],
        if (widget.note.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: widget.note.tags.map((t) => Chip(
              label: Text('#$t', style: theme.textTheme.labelSmall),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            )).toList(),
          ),
          const SizedBox(height: 12),
        ],
        MarkdownBody(
          data: widget.note.content,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
            p: theme.textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _formatTimestamp(widget.note.createdAt, widget.note.updatedAt),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
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
        TagInput(
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
