import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ai_mascot.dart';
import '../../domain/learning_plan.dart';

/// Maps a topic difficulty to a palette colour used consistently everywhere.
Color difficultyColor(TopicDifficulty d) {
  switch (d) {
    case TopicDifficulty.easy:
      return AppColors.success;
    case TopicDifficulty.medium:
      return AppColors.primary;
    case TopicDifficulty.hard:
      return AppColors.coral;
  }
}

/// A small pill showing a topic's difficulty (or a "Review" badge).
class DifficultyChip extends StatelessWidget {
  final TopicDifficulty difficulty;
  final bool review;
  const DifficultyChip(
      {super.key, required this.difficulty, this.review = false});

  @override
  Widget build(BuildContext context) {
    final color = review ? AppColors.accent : difficultyColor(difficulty);
    final label = review ? 'Review' : difficulty.label;
    final icon = review
        ? Icons.replay_rounded
        : (difficulty == TopicDifficulty.hard
            ? Icons.local_fire_department_rounded
            : difficulty == TopicDifficulty.medium
                ? Icons.trending_up_rounded
                : Icons.spa_rounded);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              )),
        ],
      ),
    );
  }
}

/// A horizontal segmented step progress bar ("Step 2 of 5").
class StepProgressBar extends StatelessWidget {
  final int step; // 1-based
  final int total;
  const StepProgressBar({super.key, required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= total; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              height: 6,
              decoration: BoxDecoration(
                color: i <= step
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          if (i != total) const SizedBox(width: 7),
        ],
      ],
    );
  }
}

/// A large, tappable option card with a title + subtitle and a selected state.
/// Used across the level, goal and time steps.
class SelectableOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const SelectableOptionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? AppColors.lavenderSoft : theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.primary : theme.dividerColor,
          width: selected ? 1.8 : 1.2,
        ),
        boxShadow: selected ? AppColors.softShadow(opacity: 0.06, blur: 16) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.14)
                          : theme.scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon,
                        size: 21,
                        color: selected
                            ? AppColors.primary
                            : theme.textTheme.bodyMedium?.color),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: selected ? AppColors.primary : null,
                          )),
                      const SizedBox(height: 3),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _RadioDot(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;
  const _RadioDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.transparent,
        border: Border.all(
          color: selected
              ? AppColors.primary
              : Theme.of(context).dividerColor,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}

/// A pinned bottom bar hosting a single primary action button.
class PlannerBottomBar extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? trailingIcon;
  final Widget? secondary;

  const PlannerBottomBar({
    super.key,
    required this.label,
    required this.onTap,
    this.trailingIcon = Icons.arrow_forward_rounded,
    this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (secondary != null) ...[
                secondary!,
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: onTap == null
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          onTap!();
                        },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                      if (trailingIcon != null) ...[
                        const SizedBox(width: 8),
                        Icon(trailingIcon, size: 20, color: Colors.white),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin rounded progress bar (0..1).
class ThinProgressBar extends StatelessWidget {
  final double value; // 0..1
  final Color? color;
  final double height;
  const ThinProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: c.withValues(alpha: 0.14),
          valueColor: AlwaysStoppedAnimation<Color>(c),
        ),
      ),
    );
  }
}

/// Small labelled stat used in the plan overview stat grid.
class PlanStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const PlanStat(
      {super.key, required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 15)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// A checkbox-style circular tick used in day/topic lists.
class TopicTick extends StatelessWidget {
  final TopicStatus status;
  final VoidCallback? onTap;
  const TopicTick({super.key, required this.status, this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = status == TopicStatus.completed;
    final learning = status == TopicStatus.learning;
    Color border;
    Color fill;
    if (done) {
      border = AppColors.success;
      fill = AppColors.success;
    } else if (learning) {
      border = AppColors.warning;
      fill = Colors.transparent;
    } else {
      border = Theme.of(context).dividerColor;
      fill = Colors.transparent;
    }
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              onTap!.call();
            },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: border, width: 2),
        ),
        child: done
            ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
            : learning
                ? const Icon(Icons.more_horiz_rounded,
                    size: 15, color: AppColors.warning)
                : null,
      ),
    );
  }
}

/// The small purple "AI" sparkle chip / button used in headers and hero cards.
class AiSparkleBadge extends StatelessWidget {
  final double size;
  const AiSparkleBadge({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.14),
        child: AiMascot(size: size * 0.72, animate: false),
      ),
    );
  }
}

/// A soft informational AI card (used on the progress/adaptation screen).
class AiInsightCard extends StatelessWidget {
  final String message;
  const AiInsightCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lavenderSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.18), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }
}
