import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../domain/referral_info.dart';
import '../providers/referral_providers.dart';

/// "Invite friends & earn Pro" — a shareable, reward-driven referral screen.
class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoAsync = ref.watch(referralInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Invite friends')),
      body: infoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => _ErrorState(
          error: e,
          onRetry: () => ref.invalidate(referralInfoProvider),
        ),
        data: (info) => _ReferralBody(info: info),
      ),
    );
  }
}

class _ReferralBody extends ConsumerStatefulWidget {
  final ReferralInfo info;
  const _ReferralBody({required this.info});

  @override
  ConsumerState<_ReferralBody> createState() => _ReferralBodyState();
}

class _ReferralBodyState extends ConsumerState<_ReferralBody> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  ReferralInfo get info => widget.info;

  String _inviteMessage(String code, int welcomeDays) =>
      '🎓 I\'m using ClassTrack to stay on top of my attendance, grades and '
      'study streaks — you should try it!\n\n'
      'Use my invite code $code when you sign up and get '
      '$welcomeDays days of ClassTrack Pro free. 💜\n\n'
      'Download: ${AppConstants.playStoreUrl}';

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite code copied ✓')),
    );
  }

  Future<void> _share(String code, int rewardDays) async {
    await Share.share(
      _inviteMessage(code, rewardDays),
      subject: 'Join me on ClassTrack',
    );
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid invite code.')),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final days = await ref.read(redeemControllerProvider.notifier).redeem(code);
    if (!mounted) return;
    if (days != null) {
      _codeController.clear();
      showDialog<void>(
        context: context,
        builder: (_) => _RewardDialog(days: days),
      );
    } else {
      final err = ref.read(redeemControllerProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err?.toString() ?? 'Could not redeem code.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Prefer the live profile count (updates in real time) over the fetched
    // snapshot so the screen reflects new joins immediately.
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final count = profile?.referralCount ?? info.referralCount;
    final rewardDays = info.rewardDays;
    final pro = ref.watch(proEntitlementProvider).valueOrNull ??
        const ProEntitlement();
    final redeemState = ref.watch(redeemControllerProvider);
    final alreadyRedeemed = info.hasRedeemed || (profile?.referredBy != null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        _RewardHero(info: info)
            .animate()
            .fadeIn(duration: 350.ms)
            .slideY(begin: 0.06, curve: Curves.easeOut),
        const SizedBox(height: 22),
        Text('Your invite code', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        _CodeCard(
          code: info.code,
          onCopy: () => _copyCode(info.code),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _share(info.code, rewardDays),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Share invite'),
          ),
        ),
        const SizedBox(height: 24),
        _ProgressCard(info: info.copyWith(referralCount: count), pro: pro),
        const SizedBox(height: 24),
        Text('How it works', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        _HowItWorks(info: info),
        const SizedBox(height: 24),
        if (alreadyRedeemed)
          _RedeemedBanner(rewardDays: rewardDays)
        else
          _RedeemSection(
            controller: _codeController,
            loading: redeemState.isLoading,
            onRedeem: _redeem,
          ),
      ],
    );
  }
}

/// Big gradient hero explaining the reward.
class _RewardHero extends StatelessWidget {
  final ReferralInfo info;
  const _RewardHero({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.card_giftcard_rounded,
                color: Colors.white, size: 34),
          ),
          const SizedBox(height: 16),
          Text(
            'Invite ${info.milestoneSize} friends,\nget ${info.milestoneDays} days of Pro',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Every ${info.milestoneSize} friends who join with your code unlock '
            '${info.milestoneDays} days of ClassTrack Pro for you. Each friend '
            'gets ${info.rewardDays} days free too.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: Colors.white.withValues(alpha: 0.92)),
          ),
        ],
      ),
    );
  }
}

/// The invite code, presented as a tappable dashed-style pill with a copy icon.
class _CodeCard extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;
  const _CodeCard({required this.code, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.lavenderSoft,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35), width: 1.4),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  code,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const Icon(Icons.copy_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 6),
              Text('Copy',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: AppColors.primary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows invites so far, the user's real Pro status, and progress toward the
/// next "5 friends → 7 days" reward.
class _ProgressCard extends StatelessWidget {
  final ReferralInfo info;
  final ProEntitlement pro;
  const _ProgressCard({required this.info, required this.pro});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = info.referralCount;
    final size = info.milestoneSize;
    final inCycle = info.inCurrentCycle;
    final toNext = info.friendsToNextReward;

    // Real, server-trusted Pro status (not a cosmetic count × days).
    final String proValue;
    final String proLabel;
    if (pro.permanent) {
      proValue = 'Active';
      proLabel = 'ClassTrack Pro';
    } else if (pro.active) {
      proValue = '${pro.daysLeft}';
      proLabel = pro.daysLeft == 1 ? 'Pro day left' : 'Pro days left';
    } else {
      proValue = '0';
      proLabel = 'Pro days left';
    }

    final String statusLine;
    if (pro.permanent) {
      statusLine = 'ClassTrack Pro is active on your account.';
    } else if (pro.active && pro.until != null) {
      statusLine =
          'Pro active until ${DateFormat.yMMMd().format(pro.until!)}.';
    } else {
      statusLine = 'Invite $size friends to unlock ${info.milestoneDays} '
          'days of ClassTrack Pro.';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: theme.brightness == Brightness.light
            ? AppColors.softShadow(opacity: 0.06, blur: 22)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatBlock(
                  value: '$count',
                  label: count == 1 ? 'friend joined' : 'friends joined',
                ),
              ),
              Container(
                width: 1,
                height: 42,
                margin: const EdgeInsets.symmetric(horizontal: 18),
                color: theme.dividerColor,
              ),
              Expanded(
                child: _StatBlock(
                  value: proValue,
                  label: proLabel,
                  color: pro.active ? AppColors.success : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                pro.active
                    ? Icons.workspace_premium_rounded
                    : Icons.lock_open_rounded,
                size: 16,
                color: pro.active ? AppColors.success : theme.hintColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(statusLine, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Next reward', style: theme.textTheme.labelLarge),
          const SizedBox(height: 10),
          // One slot per friend in the current group of [size].
          Semantics(
            label: '$inCycle of $size friends towards '
                '${info.milestoneDays} days of Pro',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < size; i++) ...[
                    Expanded(
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          color: i < inCycle
                              ? AppColors.primary
                              : AppColors.lavenderTint,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          i < inCycle
                              ? Icons.person_rounded
                              : Icons.person_outline_rounded,
                          size: 18,
                          color: i < inCycle
                              ? Colors.white
                              : AppColors.primary.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    if (i < size - 1) const SizedBox(width: 6),
                  ],
                  const SizedBox(width: 8),
                  const Icon(Icons.card_giftcard_rounded,
                      color: AppColors.accent),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.stars_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Invite $toNext more friend${toNext == 1 ? '' : 's'} to '
                  'get ${info.milestoneDays} days of Pro.'
                  '${info.earnedDays > 0 ? ' You\'ve earned ${info.earnedDays} days so far 🎉' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  const _StatBlock({required this.value, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color ?? theme.textTheme.headlineSmall?.color,
              )),
        ),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _HowItWorks extends StatelessWidget {
  final ReferralInfo info;
  const _HowItWorks({required this.info});

  @override
  Widget build(BuildContext context) {
    final steps = <(IconData, String, String)>[
      (
        Icons.ios_share_rounded,
        'Share your code',
        'Send your invite code to friends and classmates.',
      ),
      (
        Icons.person_add_alt_1_rounded,
        'They join ClassTrack',
        'Your friend signs up, enters your code and gets '
            '${info.rewardDays} days of Pro free.',
      ),
      (
        Icons.workspace_premium_rounded,
        'Every ${info.milestoneSize} friends = ${info.milestoneDays} days',
        'When ${info.milestoneSize} friends have joined, you unlock '
            '${info.milestoneDays} days of ClassTrack Pro. It keeps stacking: '
            '${info.milestoneSize * 2} friends = ${info.milestoneDays * 2} days.',
      ),
    ];
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(steps[i].$1, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(steps[i].$2, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(steps[i].$3, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Field to enter a friend's code (shown only if the user hasn't redeemed).
class _RedeemSection extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final VoidCallback onRedeem;
  const _RedeemSection({
    required this.controller,
    required this.loading,
    required this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: theme.brightness == Brightness.light
            ? AppColors.softShadow(opacity: 0.05, blur: 18)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Have an invite code?', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('Enter a friend\'s code to claim your free Pro days.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onRedeem(),
                  decoration: const InputDecoration(
                    hintText: 'e.g. K7P2QM9',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 116,
                height: 52,
                child: FilledButton(
                  // Force a finite minimum size: the app theme's default
                  // FilledButton minimumSize is Size.fromHeight(52), whose
                  // minWidth is double.infinity. As a non-flex child of this
                  // Row, the button is measured with unbounded width, and that
                  // infinite minWidth throws "BoxConstraints forces an infinite
                  // width". A fixed width + finite minimumSize avoids it.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 52),
                  ),
                  onPressed: loading ? null : onRedeem,
                  child: loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Redeem'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RedeemedBanner extends StatelessWidget {
  final int rewardDays;
  const _RedeemedBanner({required this.rewardDays});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.success),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'You joined with a friend\'s invite — enjoy your $rewardDays days of Pro! '
              'Now share your own code to earn more.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardDialog extends StatelessWidget {
  final int days;
  const _RewardDialog({required this.days});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎉', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 12),
          Text('Code redeemed!',
              style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'You just unlocked $days days of ClassTrack Pro. Your friend is '
            'one step closer to their own Pro reward too.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Awesome'),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  final Object? error;
  const _ErrorState({required this.onRetry, this.error});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail =
        error?.toString().replaceFirst('Exception: ', '').trim() ?? '';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: AppColors.primary),
            const SizedBox(height: 16),
            Text("Couldn't load your invite code",
                style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Check your connection and try again.',
                style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(detail,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
