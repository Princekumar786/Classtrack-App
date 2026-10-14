import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../domain/learning_plan.dart';
import '../providers/learning_planner_providers.dart';
import 'planner_widgets.dart';

/// One topic with its subtopics as a tickable checklist.
///
///  • The round tick toggles the whole topic.
///  • "2/5" + a thin bar show subtopic progress at a glance.
///  • Tapping the row expands the subtopics so each can be ticked on its own;
///    ticking the last one completes the topic automatically.
///  • [onOpen] (the arrow) opens Topic detail.
class TopicChecklistCard extends ConsumerStatefulWidget {
  final String planId;
  final LearningTopic topic;
  final VoidCallback? onOpen;
  final bool initiallyExpanded;

  /// Flat (no card) for nesting inside another card.
  final bool dense;

  const TopicChecklistCard({
    super.key,
    required this.planId,
    required this.topic,
    this.onOpen,
    this.initiallyExpanded = false,
    this.dense = false,
  });

  @override
  ConsumerState<TopicChecklistCard> createState() => _TopicChecklistCardState();
}

class _TopicChecklistCardState extends ConsumerState<TopicChecklistCard> {
  late bool _open = widget.initiallyExpanded;

  void _toggleTopic() {
    final t = widget.topic;
    final next = t.isDone ? TopicStatus.notStarted : TopicStatus.completed;
    ref.read(learningPlansProvider.notifier).setTopicStatus(widget.planId, t.id, next);
    if (next == TopicStatus.completed) {
      ref.read(analyticsProvider).plannerTopicCompleted();
    }
  }

  void _toggleSub(String key, bool done) {
    HapticFeedback.selectionClick();
    final t = widget.topic;
    final completesTopic = done && !t.isDone && t.subtopicsDone == t.subtopicTotal - 1;
    ref.read(learningPlansProvider.notifier).setSubtopicDone(widget.planId, t.id, key, done);
    if (completesTopic) {
      HapticFeedback.mediumImpact();
      ref.read(analyticsProvider).plannerTopicCompleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = widget.topic;
    final subs = t.subtopics;
    final doneCount = t.subtopicsDone;
    final hasSubs = subs.isNotEmpty;
    final muted = theme.textTheme.bodySmall?.color;

    final header = InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: hasSubs ? () => setState(() => _open = !_open) : widget.onOpen,
      child: Padding(
        padding: EdgeInsets.fromLTRB(widget.dense ? 0 : 6, 6, 4, 6),
        child: Row(
          children: [
            Semantics(
              button: true,
              checked: t.isDone,
              label: t.isDone ? 'Mark ${t.title} not done' : 'Mark ${t.title} done',
              excludeSemantics: true,
              child: Padding(
                // 48dp touch target around the 26dp tick.
                padding: const EdgeInsets.all(11),
                child: TopicTick(status: t.status, onTap: _toggleTopic),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 15,
                        decoration: t.isDone ? TextDecoration.lineThrough : null,
                        color: t.isDone ? muted : null,
                      )),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('~${formatEstMinutes(t.estMinutes)}',
                          style: theme.textTheme.bodySmall),
                      if (t.isReview)
                        const DifficultyChip(difficulty: TopicDifficulty.easy, review: true),
                      if (hasSubs)
                        Text('$doneCount/${subs.length} subtopics',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: doneCount == subs.length
                                  ? AppColors.success
                                  : doneCount > 0
                                      ? AppColors.primary
                                      : null,
                              fontWeight: doneCount > 0 ? FontWeight.w700 : null,
                            )),
                    ],
                  ),
                  if (hasSubs && doneCount > 0 && !t.isDone) ...[
                    const SizedBox(height: 6),
                    ThinProgressBar(value: t.progress, height: 4),
                  ],
                ],
              ),
            ),
            if (hasSubs)
              IconButton(
                tooltip: _open ? 'Hide subtopics' : 'Show subtopics',
                onPressed: () => setState(() => _open = !_open),
                icon: AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded, color: muted),
                ),
              ),
            if (widget.onOpen != null)
              IconButton(
                tooltip: 'Open topic',
                onPressed: widget.onOpen,
                icon: Icon(Icons.chevron_right_rounded, color: muted),
              ),
          ],
        ),
      ),
    );

    final body = AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !_open || !hasSubs
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: EdgeInsets.fromLTRB(widget.dense ? 8 : 14, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < subs.length; i++) ...[
                    if (i == 0 || subs[i].section != subs[i - 1].section)
                      Padding(
                        padding: EdgeInsets.fromLTRB(8, i == 0 ? 0 : 8, 0, 2),
                        child: Text(subs[i].section.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            )),
                      ),
                    SubtopicRow(
                      text: subs[i].text,
                      done: t.isDone || t.doneSubtopics.contains(subs[i].key),
                      onChanged: (v) => _toggleSub(subs[i].key, v),
                    ),
                  ],
                ],
              ),
            ),
    );

    final content = Column(children: [header, body]);
    if (widget.dense) return content;
    return Container(
      decoration: softCardDecoration(context, done: t.isDone),
      child: Material(color: Colors.transparent, child: content),
    );
  }
}

/// A single tickable subtopic line (≥48dp tall for easy tapping).
class SubtopicRow extends StatelessWidget {
  final String text;
  final bool done;
  final ValueChanged<bool> onChanged;
  const SubtopicRow({super.key, required this.text, required this.done, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      checked: done,
      label: text,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!done),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: done ? AppColors.success : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: done ? AppColors.success : theme.dividerColor, width: 2),
                  ),
                  child: done
                      ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? theme.textTheme.bodySmall?.color : null,
                      )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Card decoration for a topic: a soft green wash once it's done.
BoxDecoration softCardDecoration(BuildContext context, {bool done = false}) {
  final theme = Theme.of(context);
  return BoxDecoration(
    color: done ? AppColors.success.withValues(alpha: 0.06) : theme.cardColor,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(
        color: done
            ? AppColors.success.withValues(alpha: 0.25)
            : theme.dividerColor.withValues(alpha: 0.5)),
  );
}
