import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/models/thing.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/features/daily/journal/providers/journal_providers.dart';

// ─── Tag schemas ──────────────────────────────────────────────────────────────
// Hardcoded for now; can be made dynamic via GET /api/tag-schemas later.

class _FieldDef {
  final String key;
  final String label;
  final _FieldType type;
  final List<String>? options; // for dropdown type

  const _FieldDef(this.key, this.label, this.type, [this.options]);
}

enum _FieldType { text, dropdown, toggle }

const _tagSchemas = <String, List<_FieldDef>>{
  'person': [
    _FieldDef('first_appeared', 'First appeared', _FieldType.text),
    _FieldDef('relationship', 'Relationship', _FieldType.text),
  ],
  'project': [
    _FieldDef('status', 'Status', _FieldType.dropdown,
        ['idea', 'active', 'paused', 'completed', 'abandoned']),
    _FieldDef('started', 'Started', _FieldType.text),
  ],
  'thread': [
    _FieldDef('first_appeared', 'First appeared', _FieldType.text),
    _FieldDef('active', 'Active', _FieldType.toggle),
  ],
  'event': [
    _FieldDef('date', 'Date', _FieldType.text),
  ],
};

/// Internal/system metadata keys to hide from the UI.
const _hiddenKeys = {
  'audio_rendered_at',
  'audio_pending_at',
  'transcript_pending_at',
  'transcript_rendered_at',
  'audio_url',
  'type', // shown structurally via tag, not as raw field
};

// ─── Widget ───────────────────────────────────────────────────────────────────

/// Displays note metadata as structured fields (schema-aware) or raw key-value
/// pairs, with inline editing.
class NoteMetadataSection extends ConsumerStatefulWidget {
  final Note note;
  final VoidCallback? onChanged;

  const NoteMetadataSection({super.key, required this.note, this.onChanged});

  @override
  ConsumerState<NoteMetadataSection> createState() => _NoteMetadataSectionState();
}

class _NoteMetadataSectionState extends ConsumerState<NoteMetadataSection> {
  late Map<String, dynamic> _metadata;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _metadata = Map<String, dynamic>.from(widget.note.metadata);
  }

  /// Find the schema that applies to this note (first matching tag).
  List<_FieldDef>? get _schema {
    for (final tag in widget.note.tags) {
      if (_tagSchemas.containsKey(tag)) return _tagSchemas[tag];
    }
    return null;
  }

  /// Keys already covered by the schema.
  Set<String> get _schemaKeys =>
      _schema?.map((f) => f.key).toSet() ?? const {};

  /// Extra metadata keys not covered by schema and not hidden.
  List<String> get _extraKeys {
    final covered = _schemaKeys;
    return _metadata.keys
        .where((k) => !covered.contains(k) && !_hiddenKeys.contains(k))
        .toList()
      ..sort();
  }

  bool get _hasVisibleContent {
    if (_schema != null) return true;
    return _extraKeys.isNotEmpty;
  }

  Future<void> _saveMetadata(Map<String, dynamic> updated) async {
    if (_saving) return;
    setState(() => _saving = true);

    final api = ref.read(graphApiServiceProvider);
    final result = await api.updateNote(widget.note.id, metadata: updated);

    if (!mounted) return;
    setState(() => _saving = false);

    if (result != null) {
      _metadata = Map<String, dynamic>.from(updated);
      widget.onChanged?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save — check connection')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasVisibleContent) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final schema = _schema;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),
        // Schema fields (structured)
        if (schema != null)
          ...schema.map((field) => _buildSchemaField(theme, isDark, field)),
        // Extra non-schema fields
        ..._extraKeys.map((key) => _buildRawField(theme, isDark, key)),
        if (_saving)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  Widget _buildSchemaField(ThemeData theme, bool isDark, _FieldDef field) {
    final value = _metadata[field.key];

    switch (field.type) {
      case _FieldType.dropdown:
        return _DropdownField(
          label: field.label,
          value: value?.toString() ?? '',
          options: field.options!,
          isDark: isDark,
          onChanged: (newVal) {
            final updated = Map<String, dynamic>.from(_metadata);
            updated[field.key] = newVal;
            _saveMetadata(updated);
          },
        );
      case _FieldType.toggle:
        final boolVal = value == true || value == 'true';
        return _ToggleField(
          label: field.label,
          value: boolVal,
          isDark: isDark,
          onChanged: (newVal) {
            final updated = Map<String, dynamic>.from(_metadata);
            updated[field.key] = newVal;
            _saveMetadata(updated);
          },
        );
      case _FieldType.text:
        return _TextField(
          label: field.label,
          value: value?.toString() ?? '',
          placeholder: 'Add ${field.label.toLowerCase()}...',
          isDark: isDark,
          onSaved: (newVal) {
            final updated = Map<String, dynamic>.from(_metadata);
            updated[field.key] = newVal;
            _saveMetadata(updated);
          },
        );
    }
  }

  Widget _buildRawField(ThemeData theme, bool isDark, String key) {
    final value = _metadata[key];
    final label = _formatKey(key);
    return _TextField(
      label: label,
      value: value?.toString() ?? '',
      placeholder: 'Add value...',
      isDark: isDark,
      onSaved: (newVal) {
        final updated = Map<String, dynamic>.from(_metadata);
        updated[key] = newVal;
        _saveMetadata(updated);
      },
    );
  }

  String _formatKey(String key) {
    return key
        .replaceAll('_', ' ')
        .replaceFirst(key[0], key[0].toUpperCase());
  }
}

// ─── Field widgets ────────────────────────────────────────────────────────────

class _TextField extends StatefulWidget {
  final String label;
  final String value;
  final String placeholder;
  final bool isDark;
  final void Function(String) onSaved;

  const _TextField({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.isDark,
    required this.onSaved,
  });

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  bool _editing = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextField old) {
    super.didUpdateWidget(old);
    if (!_editing && old.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final trimmed = _controller.text.trim();
    setState(() => _editing = false);
    if (trimmed != widget.value) {
      widget.onSaved(trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = widget.isDark
        ? BrandColors.nightTextSecondary
        : BrandColors.driftwood;
    final valueColor = widget.isDark
        ? BrandColors.nightText
        : BrandColors.charcoal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              widget.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: labelColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: _editing
                ? SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: valueColor,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _save(),
                      onTapOutside: (_) => _save(),
                    ),
                  )
                : GestureDetector(
                    onTap: () => setState(() => _editing = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 8),
                      child: Text(
                        widget.value.isNotEmpty
                            ? widget.value
                            : widget.placeholder,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: widget.value.isNotEmpty
                              ? valueColor
                              : labelColor.withValues(alpha: 0.6),
                          fontStyle: widget.value.isEmpty
                              ? FontStyle.italic
                              : null,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final bool isDark;
  final void Function(String) onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = isDark
        ? BrandColors.nightTextSecondary
        : BrandColors.driftwood;
    final valueColor = isDark
        ? BrandColors.nightText
        : BrandColors.charcoal;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: labelColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 32,
              child: DropdownButtonFormField<String>(
                initialValue: options.contains(value) ? value : null,
                isDense: true,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(),
                ),
                hint: Text(
                  'Select...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: labelColor.withValues(alpha: 0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
                items: options
                    .map((o) => DropdownMenuItem(
                          value: o,
                          child: Text(
                            o,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: valueColor,
                            ),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleField extends StatelessWidget {
  final String label;
  final bool value;
  final bool isDark;
  final void Function(bool) onChanged;

  const _ToggleField({
    required this.label,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = isDark
        ? BrandColors.nightTextSecondary
        : BrandColors.driftwood;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: labelColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: Switch.adaptive(
              value: value,
              activeTrackColor: BrandColors.forest,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
