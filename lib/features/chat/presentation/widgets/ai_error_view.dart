import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';
import '../../domain/ai_errors.dart';

/// Error state for one-shot AI cards (Insights, Daily agenda).
///
/// A free user who has used this month's AI messages is asked to upgrade
/// (with a button straight to the paywall) instead of seeing a misleading
/// "check your connection" message. Other failures keep the Retry action.
class AiErrorView extends ConsumerWidget {
  const AiErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.onDark = false,
  });

  final Object error;
  final VoidCallback onRetry;

  /// True when rendered on a dark/gradient card (white text + white button).
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final kind = classifyChatError(error, isPro: ref.watch(isProProvider));
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: onDark ? Colors.white : null,
    );
    final buttonStyle = onDark
        ? FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: theme.colorScheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          )
        : null;

    final (String message, Widget action) = switch (kind) {
      ChatErrorKind.freeLimit => (
          freeChatLimitMessage,
          FilledButton.icon(
            style: buttonStyle,
            onPressed: () =>
                showUpgradePrompt(context, UpgradeReason.aiChat),
            icon: const Icon(Icons.workspace_premium_rounded, size: 18),
            label: const Text('Upgrade to Pro', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ChatErrorKind.proDailyCap => (
          "You've reached today's AI usage limit. Please try again tomorrow.",
          const SizedBox.shrink(),
        ),
      ChatErrorKind.emailUnverified => (
          'Please verify your email address to use AI features.',
          const SizedBox.shrink(),
        ),
      ChatErrorKind.other => (
          "Couldn't reach the assistant. Check your connection and try again.",
          FilledButton.icon(
            style: buttonStyle,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: textStyle),
        if (action is! SizedBox) ...[const SizedBox(height: 12), action],
      ],
    );
  }
}
