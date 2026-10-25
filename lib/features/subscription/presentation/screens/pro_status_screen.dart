import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/url_launcher_util.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/subscription_service.dart';
import '../providers/subscription_providers.dart';

/// Shows the signed-in user their ClassTrack Pro status: where it came from,
/// when it was purchased, when it renews/expires, plus Restore and Manage
/// actions. Reached from the "Pro active" tile in Settings.
///
/// Two sources of truth are merged:
///  • [proDetailsProvider] — real store-purchase details from RevenueCat
///    (dates, renewal state, management URL). Null for non-purchase grants.
///  • [proEntitlementProvider] — the server-trusted entitlement, which also
///    covers referral/promo gifts (a `proUntil` expiry) and comps (`pro:true`).
class ProStatusScreen extends ConsumerStatefulWidget {
  const ProStatusScreen({super.key});

  @override
  ConsumerState<ProStatusScreen> createState() => _ProStatusScreenState();
}

class _ProStatusScreenState extends ConsumerState<ProStatusScreen> {
  bool _restoring = false;

  static final _dateFmt = DateFormat('d MMM yyyy');

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final result = await ref.read(subscriptionServiceProvider).restore();
    // Refresh the details snapshot so any newly-restored purchase shows up.
    ref.invalidate(proDetailsProvider);
    if (!mounted) return;
    setState(() => _restoring = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _manage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final launched = await safeLaunchUri(uri);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open subscription settings.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailsAsync = ref.watch(proDetailsProvider);
    final entitlement =
        ref.watch(proEntitlementProvider).valueOrNull ?? const ProEntitlement();

    return Scaffold(
      appBar: AppBar(title: const Text('ClassTrack Pro')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusHeader(theme, detailsAsync.valueOrNull, entitlement),
          const SizedBox(height: 16),
          detailsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) =>
                _detailsCard(theme, null, entitlement),
            data: (details) => _detailsCard(theme, details, entitlement),
          ),
          const SizedBox(height: 16),
          _actions(theme, detailsAsync.valueOrNull),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Changed device or reinstalled? Tap Restore to bring your Pro '
              'subscription back. Manage or cancel anytime from the store.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero status banner ─────────────────────────────────────────────────
  Widget _statusHeader(
    ThemeData theme,
    ProDetails? details,
    ProEntitlement entitlement,
  ) {
    final source = _sourceLabel(details, entitlement);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: Colors.white, size: 30),
              const SizedBox(width: 10),
              Text(
                'Pro active',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (details?.inTrial ?? false) _pill('Free trial'),
              if (details?.isSandbox ?? false) _pill('Test'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            source,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  // ── Details rows ───────────────────────────────────────────────────────
  Widget _detailsCard(
    ThemeData theme,
    ProDetails? details,
    ProEntitlement entitlement,
  ) {
    final rows = <Widget>[];

    // Source / store.
    rows.add(_row(theme, Icons.storefront_rounded, 'Source',
        _sourceLabel(details, entitlement)));

    if (details != null) {
      if (details.purchaseDate != null) {
        rows.add(_divider());
        rows.add(_row(theme, Icons.event_available_rounded, 'Purchased on',
            _dateFmt.format(details.purchaseDate!)));
      }
      if (details.latestRenewalDate != null &&
          details.latestRenewalDate != details.purchaseDate) {
        rows.add(_divider());
        rows.add(_row(theme, Icons.autorenew_rounded, 'Last renewed',
            _dateFmt.format(details.latestRenewalDate!)));
      }
      rows.add(_divider());
      rows.add(_expiryRow(theme, details));
      rows.add(_divider());
      rows.add(_row(theme, Icons.card_membership_rounded, 'Plan',
          details.productIdentifier));
    } else {
      // Server-granted Pro (referral / promo / comp): no store purchase.
      rows.add(_divider());
      if (entitlement.permanent) {
        rows.add(_row(theme, Icons.all_inclusive_rounded, 'Access',
            'Lifetime — granted to your account'));
      } else if (entitlement.until != null) {
        final left = entitlement.daysLeft;
        rows.add(_row(
          theme,
          Icons.hourglass_bottom_rounded,
          'Access until',
          '${_dateFmt.format(entitlement.until!)}'
              '${left > 0 ? '  ($left day${left == 1 ? '' : 's'} left)' : ''}',
        ));
      }
    }

    // Warnings.
    final warnings = <Widget>[];
    if (details?.hasBillingIssue ?? false) {
      warnings.add(_banner(
        theme,
        AppColors.warning,
        Icons.error_outline_rounded,
        'There\'s a billing problem with your subscription. Update your '
        'payment method in the store to keep Pro.',
      ));
    }
    if ((details?.cancelled ?? false) && !(details?.willRenew ?? true)) {
      warnings.add(_banner(
        theme,
        AppColors.info,
        Icons.info_outline_rounded,
        'Auto-renew is off. You\'ll keep Pro until the date above, then return '
        'to the free plan.',
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(theme, child: Column(children: rows)),
        for (final w in warnings) ...[const SizedBox(height: 12), w],
      ],
    );
  }

  Widget _expiryRow(ThemeData theme, ProDetails d) {
    if (d.expirationDate == null) {
      return _row(theme, Icons.all_inclusive_rounded, 'Access',
          'Lifetime — never expires');
    }
    final label = (d.willRenew && !d.cancelled) ? 'Renews on' : 'Access until';
    final icon = (d.willRenew && !d.cancelled)
        ? Icons.autorenew_rounded
        : Icons.hourglass_bottom_rounded;
    return _row(theme, icon, label, _dateFmt.format(d.expirationDate!));
  }

  Widget _row(ThemeData theme, IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Text(label, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _divider() => const Divider(height: 1);

  Widget _banner(
          ThemeData theme, Color color, IconData icon, String text) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text, style: theme.textTheme.bodySmall)),
          ],
        ),
      );

  // ── Actions ────────────────────────────────────────────────────────────
  Widget _actions(ThemeData theme, ProDetails? details) {
    final manageUrl = details?.managementUrl;
    return Column(
      children: [
        if (manageUrl != null && manageUrl.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _manage(manageUrl),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Manage subscription'),
            ),
          ),
        if (manageUrl != null && manageUrl.isNotEmpty)
          const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _restoring ? null : _restore,
            icon: _restoring
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restore_rounded),
            label: Text(_restoring ? 'Restoring…' : 'Restore purchases'),
          ),
        ),
      ],
    );
  }

  Widget _card(ThemeData theme, {required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
        child: child,
      );

  // ── Helpers ────────────────────────────────────────────────────────────
  String _sourceLabel(ProDetails? details, ProEntitlement entitlement) {
    if (details != null) {
      final store = details.storeLabel;
      if (details.inTrial) return 'Free trial via $store';
      return 'Subscribed via $store';
    }
    if (entitlement.permanent) return 'Granted to your account';
    if (entitlement.until != null) return 'Free Pro from referrals & promos';
    return 'Thanks for supporting ClassTrack 💜';
  }
}
