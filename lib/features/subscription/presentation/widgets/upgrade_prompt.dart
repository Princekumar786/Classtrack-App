import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../domain/upgrade_reason.dart';
import '../providers/subscription_providers.dart';
import '../screens/paywall_screen.dart';

export '../../domain/upgrade_reason.dart' show UpgradeReason;
export '../screens/paywall_screen.dart' show showPaywall;

/// THE single entry point for every free-tier limit and Pro gate.
///
/// Shows a polished bottom sheet explaining what limit was hit (with a usage
/// meter for allowances), and — when the student taps "See Pro plans" — opens
/// the pricing page tailored to [reason]. Returns true if they became Pro.
///
/// Pro users never see it (returns true immediately), so call sites can use it
/// as a guard: `if (!await requirePro(context, ref, UpgradeReason.export)) return;`
Future<bool> showUpgradePrompt(
  BuildContext context,
  UpgradeReason reason, {
  int? used,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(isProProvider)) return true;
  container.read(analyticsProvider).log('upgrade_prompt_shown', {'reason': reason.id});
  HapticFeedback.mediumImpact();

  final wantsPlans = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => UpgradePromptSheet(reason: reason, used: used),
  );
  if (wantsPlans != true || !context.mounted) {
    container.read(analyticsProvider).log('upgrade_prompt_dismissed', {'reason': reason.id});
    return false;
  }
  container.read(analyticsProvider).log('upgrade_prompt_accepted', {'reason': reason.id});
  return showPaywall(context, reason: reason);
}

/// Guard for Pro-only actions: true when the user is (or just became) Pro.
Future<bool> requirePro(BuildContext context, WidgetRef ref, UpgradeReason reason) async {
  if (ref.read(isProProvider)) return true;
  return showUpgradePrompt(context, reason);
}

/// The upgrade prompt itself. Public for widget tests.
class UpgradePromptSheet extends StatelessWidget {
  const UpgradePromptSheet({super.key, required this.reason, this.used});

  final UpgradeReason reason;

  /// How much of the allowance is used (defaults to all of it for limits).
  final int? used;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = reason.copy;
    final motion = !MediaQuery.of(context).disableAnimations;
    final reset = resetLabel(copy, DateTime.now());

    Widget badge = Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(copy.color, Colors.white, 0.25)!, copy.color],
        ),
        boxShadow: [BoxShadow(color: copy.color.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Icon(copy.icon, color: Colors.white, size: 36),
    );
    if (motion) {
      badge = badge.animate().scaleXY(begin: 0.6, duration: 480.ms, curve: Curves.easeOutBack).fadeIn(duration: 220.ms);
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 10, 24, 16 + MediaQuery.of(context).viewPadding.bottom),
      // Scrolls on short screens / large text instead of overflowing.
      child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 22),
          Semantics(label: copy.title, child: ExcludeSemantics(child: badge)),
          const SizedBox(height: 18),
          Semantics(
            header: true,
            child: Text(copy.title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: 8),
          Text(
            copy.message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color, height: 1.45),
          ),
          if (copy.isLimit) ...[
            const SizedBox(height: 18),
            _UsageMeter(
              used: (used ?? copy.limit!).clamp(0, copy.limit!),
              limit: copy.limit!,
              unit: copy.limitUnit ?? '',
              color: copy.color,
              footnote: reset,
            ),
          ],
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
            ),
            child: Row(children: [
              const Icon(Icons.workspace_premium_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'With Pro: ', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: copy.highlight),
                  ]),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('See Pro plans'),
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
        ],
      ),
      ),
    );
  }
}

class _UsageMeter extends StatelessWidget {
  const _UsageMeter({
    required this.used,
    required this.limit,
    required this.unit,
    required this.color,
    this.footnote,
  });

  final int used;
  final int limit;
  final String unit;
  final Color color;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$used of $limit free $unit used${footnote != null ? '. $footnote' : ''}',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Row(children: [
              Expanded(child: Text('Free plan', style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text('$used / $limit $unit used',
                  style: theme.textTheme.labelLarge?.copyWith(color: color)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: limit == 0 ? 1 : used / limit),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.14),
                ),
              ),
            ),
            if (footnote != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(footnote!, style: theme.textTheme.bodySmall),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
