import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:parachute/core/theme/design_tokens.dart';

/// Inline syntax that parses `[[target]]` and `[[target|display text]]`.
///
/// Produces an `md.Element` with tag 'wikilink', textContent = display text,
/// and attribute 'target' = the link target path.
class WikilinkSyntax extends md.InlineSyntax {
  // Match [[ ... ]] with optional | for display text.
  // Lazy match inside to handle [[a]] [[b]] correctly.
  WikilinkSyntax() : super(r'\[\[([^\]]+?)\]\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final raw = match[1]!;
    final pipeIndex = raw.indexOf('|');

    String target;
    String display;
    if (pipeIndex != -1) {
      target = raw.substring(0, pipeIndex).trim();
      display = raw.substring(pipeIndex + 1).trim();
    } else {
      target = raw.trim();
      display = target;
    }

    final el = md.Element.text('wikilink', display);
    el.attributes['target'] = target;
    parser.addNode(el);
    return true;
  }
}

/// Builder that renders wikilink elements as tappable styled text spans.
class WikilinkBuilder extends MarkdownElementBuilder {
  /// Called when a wikilink is tapped. Receives the target path.
  final void Function(String target) onTap;

  /// Set of known note paths (lowercase) for resolved/unresolved styling.
  /// If null, all links render as resolved (optimistic).
  final Set<String>? knownPaths;

  WikilinkBuilder({required this.onTap, this.knownPaths});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final target = element.attributes['target'] ?? '';
    final display = element.textContent;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check if this link resolves to a known note
    final isResolved = knownPaths == null ||
        knownPaths!.contains(target.toLowerCase());

    final color = isResolved
        ? (isDark ? BrandColors.nightTurquoise : BrandColors.turquoiseDeep)
        : (isDark
            ? BrandColors.nightTextSecondary.withValues(alpha: 0.6)
            : BrandColors.driftwood);

    return RichText(
      text: TextSpan(
        text: display,
        style: (preferredStyle ?? parentStyle)?.copyWith(
              color: color,
              decoration:
                  isResolved ? TextDecoration.underline : TextDecoration.none,
              decorationColor: color.withValues(alpha: 0.4),
              decorationStyle: TextDecorationStyle.solid,
              fontStyle: isResolved ? null : FontStyle.italic,
            ) ??
            TextStyle(color: color),
        recognizer: TapGestureRecognizer()..onTap = () => onTap(target),
      ),
    );
  }
}
