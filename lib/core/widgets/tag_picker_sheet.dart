import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parachute/core/theme/design_tokens.dart';
import 'package:parachute/core/widgets/tag_picker.dart';
import 'package:parachute/features/vault/providers/vault_providers.dart';

/// Show a bottom sheet tag picker that fetches available tags from the vault.
///
/// Returns the updated tag list when dismissed, or null if unchanged.
Future<List<String>?> showTagPickerSheet({
  required BuildContext context,
  required WidgetRef ref,
  required List<String> currentTags,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TagPickerSheetBody(
      ref: ref,
      initialTags: currentTags,
    ),
  );
}

class _TagPickerSheetBody extends StatefulWidget {
  final WidgetRef ref;
  final List<String> initialTags;

  const _TagPickerSheetBody({required this.ref, required this.initialTags});

  @override
  State<_TagPickerSheetBody> createState() => _TagPickerSheetBodyState();
}

class _TagPickerSheetBodyState extends State<_TagPickerSheetBody> {
  late List<String> _tags;

  @override
  void initState() {
    super.initState();
    _tags = List<String>.from(widget.initialTags);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;
    final tagsAsync = widget.ref.watch(vaultTagsProvider);
    final isLoading = tagsAsync.isLoading;

    final available = tagsAsync.valueOrNull
            ?.map((t) => TagPickerItem(name: t.tag, count: t.count))
            .toList() ??
        [];

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.7),
      decoration: BoxDecoration(
        color: isDark ? BrandColors.nightSurface : BrandColors.softWhite,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.xl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? BrandColors.charcoal
                    : BrandColors.stone,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Tags',
                    style: TextStyle(
                      fontSize: TypographyTokens.headlineSmall,
                      fontWeight: FontWeight.w600,
                      color: isDark ? BrandColors.nightText : BrandColors.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, _tags),
                  child: Text(
                    'Done',
                    style: TextStyle(
                      fontSize: TypographyTokens.bodyMedium,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? BrandColors.nightTurquoise
                          : BrandColors.turquoise,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 16),

          // Picker body (scrollable)
          Flexible(
            child: isLoading && available.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: TagPicker(
                      selectedTags: _tags,
                      onChanged: (tags) => setState(() => _tags = tags),
                      availableTags: available,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
