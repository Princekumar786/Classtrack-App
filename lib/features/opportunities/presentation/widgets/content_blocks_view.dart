import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/content_blocks.dart';

/// Renders CMS free text as structured, scannable content:
///  • numbered lines  → a vertical step timeline (numbered circles + rail)
///  • bullet / emoji  → rows with a tinted leading chip
///  • prose           → comfortable paragraphs; long prose collapses behind
///                      "Read more" when [collapsible] is true.
class ContentBlocksView extends StatefulWidget {
  final String text;
  final Color accent;
  final bool collapsible;
  const ContentBlocksView({
    super.key,
    required this.text,
    this.accent = AppColors.primary,
    this.collapsible = false,
  });

  @override
  State<ContentBlocksView> createState() => _ContentBlocksViewState();
}

class _ContentBlocksViewState extends State<ContentBlocksView> {
  /// Prose longer than this collapses to [_collapsedLines] until expanded.
  static const _collapseThreshold = 320;
  static const _collapsedLines = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final blocks = parseContentBlocks(widget.text);
    if (blocks.isEmpty) return const SizedBox.shrink();

    final onlyProse = blocks.every((b) => b is ParagraphBlock);
    final canCollapse = widget.collapsible &&
        onlyProse &&
        widget.text.length > _collapseThreshold;

    if (canCollapse) return _collapsibleProse(context, blocks);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _block(context, blocks[i]),
        ],
      ],
    );
  }

  Widget _block(BuildContext context, ContentBlock b) => switch (b) {
        ParagraphBlock(:final text) => _Paragraph(text),
        StepsBlock(:final steps) => _Steps(steps: steps, accent: widget.accent),
        BulletsBlock(:final items) =>
          _Bullets(items: items, accent: widget.accent),
      };

  Widget _collapsibleProse(BuildContext context, List<ContentBlock> blocks) {
    final theme = Theme.of(context);
    final text = blocks.cast<ParagraphBlock>().map((p) => p.text).join('\n\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Text(
            text,
            maxLines: _expanded ? null : _collapsedLines,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.fade,
            style: _proseStyle(theme),
          ),
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(48, 40),
            foregroundColor: widget.accent,
          ),
          icon: Icon(_expanded
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded),
          label: Text(_expanded ? 'Show less' : 'Read more'),
        ),
      ],
    );
  }
}

TextStyle? _proseStyle(ThemeData theme) => theme.textTheme.bodyMedium
    ?.copyWith(height: 1.6, color: theme.textTheme.bodyMedium?.color);

class _Paragraph extends StatelessWidget {
  final String text;
  const _Paragraph(this.text);

  @override
  Widget build(BuildContext context) =>
      Text(text, style: _proseStyle(Theme.of(context)));
}

/// Numbered vertical timeline: circle badges joined by a thin rail.
class _Steps extends StatelessWidget {
  final List<String> steps;
  final Color accent;
  const _Steps({required this.steps, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Text('${i + 1}',
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: accent, fontWeight: FontWeight.w800)),
                      ),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            color: accent.withValues(alpha: 0.18),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        top: 4, bottom: i < steps.length - 1 ? 18 : 0),
                    child: Text(steps[i],
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(height: 1.5)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Bullet rows with a tinted leading chip (the author's emoji, or a check).
class _Bullets extends StatelessWidget {
  final List<BulletItem> items;
  final Color accent;
  const _Bullets({required this.items, required this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < items.length - 1 ? 12 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: items[i].leading != null
                      ? Text(items[i].leading!,
                          style: const TextStyle(fontSize: 16))
                      : Icon(Icons.check_rounded, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(items[i].text,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(height: 1.45)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
