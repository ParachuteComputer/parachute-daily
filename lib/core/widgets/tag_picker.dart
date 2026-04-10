import 'package:flutter/material.dart';
import 'package:parachute/core/theme/design_tokens.dart';

/// Tag info with optional count, for display in the picker.
class TagPickerItem {
  final String name;
  final int count;

  const TagPickerItem({required this.name, this.count = 0});
}

/// Unified tag picker with hierarchy grouping, counts, and search.
///
/// Shows selected tags as removable chips, a search field that filters
/// available tags, and groups hierarchical tags (e.g. reader/summary)
/// under collapsible parent headers.
class TagPicker extends StatefulWidget {
  /// Currently selected tags.
  final List<String> selectedTags;

  /// Called when tags change (add or remove).
  final void Function(List<String> tags) onChanged;

  /// All available tags from the vault (with counts).
  final List<TagPickerItem> availableTags;

  /// Whether to show in compact inline mode (for editors) vs full mode (sheets).
  final bool compact;

  const TagPicker({
    super.key,
    required this.selectedTags,
    required this.onChanged,
    this.availableTags = const [],
    this.compact = false,
  });

  @override
  State<TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends State<TagPicker> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _expandedGroups = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    if (widget.selectedTags.contains(tag)) return;
    widget.onChanged([...widget.selectedTags, tag]);
    _searchController.clear();
    setState(() {});
  }

  void _removeTag(String tag) {
    widget.onChanged(widget.selectedTags.where((t) => t != tag).toList());
  }

  void _addCustomTag() {
    final raw = _searchController.text.trim();
    if (raw.isEmpty) return;
    final tag = raw.toLowerCase().replaceAll(' ', '-');
    if (!RegExp(r'^[a-z0-9](?:[a-z0-9\-/]{0,46}[a-z0-9])?$').hasMatch(tag)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tags: lowercase letters, numbers, hyphens, slashes'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    _addTag(tag);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final query = _searchController.text.toLowerCase();

    // Filter available tags by search query, exclude already selected
    final unselected = widget.availableTags
        .where((t) => !widget.selectedTags.contains(t.name))
        .where((t) => query.isEmpty || t.name.contains(query))
        .toList();

    // Group by prefix (before /)
    final grouped = _groupTags(unselected);
    final ungrouped = unselected.where((t) => !t.name.contains('/')).toList();

    // Check if query matches any existing tag exactly
    final exactMatch = widget.availableTags.any((t) => t.name == query) ||
        widget.selectedTags.contains(query);
    final showCreateOption =
        query.isNotEmpty && !exactMatch && query.length >= 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Selected tags as removable chips
        if (widget.selectedTags.isNotEmpty) ...[
          _buildSelectedChips(theme, isDark),
          SizedBox(height: widget.compact ? 8 : 12),
        ],

        // Search field
        _buildSearchField(theme, isDark),

        // Tag suggestions / browser
        if (query.isNotEmpty || !widget.compact) ...[
          SizedBox(height: widget.compact ? 4 : 8),
          if (showCreateOption) _buildCreateOption(theme, isDark, query),
          if (ungrouped.isNotEmpty) _buildFlatTags(theme, isDark, ungrouped),
          ...grouped.entries.map(
            (e) => _buildTagGroup(theme, isDark, e.key, e.value),
          ),
          if (unselected.isEmpty && query.isNotEmpty && !showCreateOption)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No matching tags',
                style: TextStyle(
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                  fontSize: TypographyTokens.bodySmall,
                ),
              ),
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Selected chips
  // ---------------------------------------------------------------------------

  Widget _buildSelectedChips(ThemeData theme, bool isDark) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: widget.selectedTags.map((tag) {
        final parts = tag.split('/');
        final isHierarchical = parts.length > 1;

        return AnimatedSize(
          duration: const Duration(milliseconds: 150),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Container(
            padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? BrandColors.forest.withValues(alpha: 0.2)
                  : BrandColors.forestMist.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(
                color: isDark
                    ? BrandColors.forest.withValues(alpha: 0.3)
                    : BrandColors.forest.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isHierarchical) ...[
                  Text(
                    '${parts.first}/',
                    style: TextStyle(
                      fontSize: TypographyTokens.labelSmall,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      parts.sublist(1).join('/'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TypographyTokens.labelMedium,
                        fontWeight: FontWeight.w500,
                        color: isDark ? BrandColors.nightText : BrandColors.forest,
                      ),
                    ),
                  ),
                ] else
                  Flexible(
                    child: Text(
                      tag,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TypographyTokens.labelMedium,
                        fontWeight: FontWeight.w500,
                        color: isDark ? BrandColors.nightText : BrandColors.forest,
                      ),
                    ),
                  ),
                const SizedBox(width: 2),
                GestureDetector(
                  onTap: () => _removeTag(tag),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
              ],
            ),
          ),
          ),
        );
      }).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Search field
  // ---------------------------------------------------------------------------

  Widget _buildSearchField(ThemeData theme, bool isDark) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      style: TextStyle(
        fontSize: TypographyTokens.bodySmall,
        color: isDark ? BrandColors.nightText : BrandColors.ink,
      ),
      decoration: InputDecoration(
        hintText: 'Search or create tag...',
        hintStyle: TextStyle(
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
        ),
        prefixIcon: Icon(
          Icons.tag_rounded,
          size: 18,
          color: isDark ? BrandColors.nightTextSecondary : BrandColors.driftwood,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide(
            color: isDark ? BrandColors.charcoal : BrandColors.stone,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide(
            color: isDark ? BrandColors.charcoal : BrandColors.stone,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
          borderSide: BorderSide(color: BrandColors.turquoise, width: 1.5),
        ),
      ),
      onSubmitted: (_) => _addCustomTag(),
      onChanged: (_) => setState(() {}),
    );
  }

  // ---------------------------------------------------------------------------
  // Create new tag option
  // ---------------------------------------------------------------------------

  Widget _buildCreateOption(ThemeData theme, bool isDark, String query) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: _addCustomTag,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.add_circle_outline_rounded,
                size: 18,
                color: BrandColors.turquoise,
              ),
              const SizedBox(width: 8),
              Text(
                'Create ',
                style: TextStyle(
                  fontSize: TypographyTokens.bodySmall,
                  color: isDark
                      ? BrandColors.nightTextSecondary
                      : BrandColors.driftwood,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: BrandColors.turquoise.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#$query',
                  style: TextStyle(
                    fontSize: TypographyTokens.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? BrandColors.nightTurquoise
                        : BrandColors.turquoiseDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Flat (non-hierarchical) tags
  // ---------------------------------------------------------------------------

  Widget _buildFlatTags(
      ThemeData theme, bool isDark, List<TagPickerItem> tags) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags.map((t) => _buildTagChip(theme, isDark, t)).toList(),
    );
  }

  // ---------------------------------------------------------------------------
  // Hierarchical tag group
  // ---------------------------------------------------------------------------

  Map<String, List<TagPickerItem>> _groupTags(List<TagPickerItem> tags) {
    final groups = <String, List<TagPickerItem>>{};
    for (final tag in tags) {
      final slashIndex = tag.name.indexOf('/');
      if (slashIndex == -1) continue;
      final prefix = tag.name.substring(0, slashIndex);
      groups.putIfAbsent(prefix, () => []).add(tag);
    }
    return groups;
  }

  Widget _buildTagGroup(ThemeData theme, bool isDark, String prefix,
      List<TagPickerItem> children) {
    final isExpanded = _expandedGroups.contains(prefix);
    final totalCount = children.fold<int>(0, (sum, t) => sum + t.count);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedGroups.remove(prefix);
                } else {
                  _expandedGroups.add(prefix);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.driftwood,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$prefix/',
                    style: TextStyle(
                      fontSize: TypographyTokens.labelMedium,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? BrandColors.nightTextSecondary
                          : BrandColors.charcoal,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${children.length}',
                    style: TextStyle(
                      fontSize: TypographyTokens.labelSmall,
                      color: isDark
                          ? BrandColors.nightTextSecondary.withValues(alpha: 0.6)
                          : BrandColors.driftwood.withValues(alpha: 0.6),
                    ),
                  ),
                  if (totalCount > 0) ...[
                    Text(
                      ' · $totalCount notes',
                      style: TextStyle(
                        fontSize: TypographyTokens.labelSmall,
                        color: isDark
                            ? BrandColors.nightTextSecondary
                                .withValues(alpha: 0.5)
                            : BrandColors.driftwood.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Children — always show when searching, otherwise respect expand state
          if (isExpanded || _searchController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: children
                    .map((t) => _buildTagChip(theme, isDark, t,
                        hidePrefix: prefix))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Individual tag chip (in suggestions list)
  // ---------------------------------------------------------------------------

  Widget _buildTagChip(ThemeData theme, bool isDark, TagPickerItem tag,
      {String? hidePrefix}) {
    // Show just the suffix when nested under a group header
    final displayName = hidePrefix != null && tag.name.startsWith('$hidePrefix/')
        ? tag.name.substring(hidePrefix.length + 1)
        : tag.name;

    return GestureDetector(
      onTap: () => _addTag(tag.name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? BrandColors.charcoal.withValues(alpha: 0.6)
              : BrandColors.stone.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#$displayName',
              style: TextStyle(
                fontSize: TypographyTokens.labelMedium,
                fontWeight: FontWeight.w500,
                color: isDark ? BrandColors.nightText : BrandColors.charcoal,
              ),
            ),
            if (tag.count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isDark
                      ? BrandColors.nightSurfaceElevated
                      : BrandColors.stone.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${tag.count}',
                  style: TextStyle(
                    fontSize: TypographyTokens.labelSmall - 1,
                    color: isDark
                        ? BrandColors.nightTextSecondary
                        : BrandColors.driftwood,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
