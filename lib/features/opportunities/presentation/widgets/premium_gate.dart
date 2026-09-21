import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../subscription/presentation/screens/paywall_screen.dart';

/// Upsell card shown at the end of a gated free-tier feed. Free members see
/// only the latest few items; this invites them to unlock the rest with
/// Premium and opens the paywall.
///
/// [noun] is the plural surface label, e.g. 'opportunities' or 'perks'.
/// Intentionally shows NO counts (e.g. "9 more" / "159 perks") — a vague,
/// aspirational "unlock everything" message converts better and never dates.
class PremiumUnlockCard extends StatelessWidget {
  final String noun;
  const PremiumUnlockCard({super.key, required this.noun});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.softShadow(opacity: 0.30, blur: 24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_open_rounded,
                    color: Colors.white, size: 24),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scaleXY(
                      begin: 1,
                      end: 1.08,
                      duration: 1600.ms,
                      curve: Curves.easeInOut),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Unlock all $noun with Premium',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "You're seeing just a preview. Go Premium to browse the full "
            'library — plus search, filters and every other Pro feature.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => showPaywall(context),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.workspace_premium_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('See everything with Premium',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.12, end: 0, curve: Curves.easeOut);
  }
}
