import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../core/utils/url_launcher_util.dart';
import '../../../../services/analytics_service.dart';
import '../../../../services/metrics_service.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../cms/domain/content_report.dart';
import '../../../cms/presentation/providers/report_providers.dart';
import '../../data/resource_repository.dart';
import '../../domain/resource.dart';
import '../../domain/resource_status.dart';
import '../providers/opportunities_providers.dart';
import '../widgets/resource_card.dart';

/// Full detail page for a [Resource]. Handles save/share, external apply /
/// get-deal redirection, status display and related opportunities.
class ResourceDetailScreen extends ConsumerStatefulWidget {
  final Resource resource;
  const ResourceDetailScreen({super.key, required this.resource});

  @override
  ConsumerState<ResourceDetailScreen> createState() =>
      _ResourceDetailScreenState();
}

class _ResourceDetailScreenState extends ConsumerState<ResourceDetailScreen> {
  Resource get r => widget.resource;

  @override
  void initState() {
    super.initState();
    // Analytics: viewing an opportunity / discount (PRD §20).
    ref.read(analyticsProvider).log(
      r.type.isDiscount ? 'discount_viewed' : 'opportunity_viewed',
      {'id': r.id, 'type': r.type.key},
    );
    ref.read(metricsServiceProvider).record(
        resourceId: r.id, event: 'view', type: r.type.key, title: r.title);
  }

  Future<void> _open() async {
    // Safety net: never open the link while the resource is "Opening soon".
    if (r.effectiveStatus == ResourceStatus.openingSoon) return;
    // Discounts resolve to the viewer's country-specific link when one exists.
    final country = ref.read(userProfileProvider).valueOrNull?.country;
    final resolved = r.effectiveOffer(country);
    final url = r.type.isDiscount
        ? (resolved.url ?? r.affiliateUrl ?? r.applicationUrl)
        : (r.applicationUrl ?? r.affiliateUrl);
    ref.read(analyticsProvider).log(
      r.type.isDiscount ? 'discount_clicked' : 'opportunity_clicked',
      {'id': r.id, 'type': r.type.key},
    );
    if (!r.type.isDiscount) {
      ref
          .read(analyticsProvider)
          .log('opportunity_applied', {'id': r.id, 'type': r.type.key});
    }
    final m = ref.read(metricsServiceProvider);
    m.record(resourceId: r.id, event: 'click', type: r.type.key, title: r.title);
    if (!r.type.isDiscount) {
      m.record(resourceId: r.id, event: 'apply', type: r.type.key, title: r.title);
    }
    await openUrl(context, url);
  }

  Future<void> _share() async {
    ref.read(analyticsProvider).log(
      r.type.isDiscount ? 'discount_shared' : 'opportunity_shared',
      {'id': r.id, 'type': r.type.key},
    );
    final link = r.applicationUrl ?? r.affiliateUrl ?? '';
    ref.read(metricsServiceProvider).record(
        resourceId: r.id, event: 'share', type: r.type.key, title: r.title);
    await Share.share(
      '${r.title} — ${r.brandName}\n$link',
      subject: r.title,
    );
  }

  /// Lets a student flag a problem with this resource. Opens a reason sheet and
  /// files a report to the moderation queue.
  Future<void> _report() async {
    final reason = await showModalBottomSheet<ReportReason>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Report an issue',
                    style: theme.textTheme.titleLarge),
              ),
              for (final reason in ReportReason.values)
                ListTile(
                  title: Text(reason.label),
                  onTap: () => Navigator.pop(ctx, reason),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (reason == null || !mounted) return;

    final repo = ref.read(reportRepositoryProvider);
    // Capture ref-backed services BEFORE the await. Using `ref` again after the
    // network write below would throw "Cannot use ref after the widget was
    // disposed" if the user leaves this screen mid-request.
    final analytics = ref.read(analyticsProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (repo == null) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Sign in to report content.')));
      return;
    }
    try {
      await repo.create(
        resourceId: r.id,
        resourceTitle: r.title,
        reason: reason,
      );
      analytics.log(
          'resource_reported', {'id': r.id, 'reason': reason.key});
      messenger.showSnackBar(const SnackBar(
          content: Text('Thanks — reported. Our team will review it.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text("Couldn't submit your report. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = ref.watch(savedResourceIdsProvider).valueOrNull ?? const {};
    final isSaved = saved.contains(r.id);
    final status = r.effectiveStatus;
    final related = _related(ref);
    final isDiscount = r.type.isDiscount;
    final match = ref.watch(resourceScoreProvider(r));
    final resolvedOffer =
        r.effectiveOffer(ref.watch(userProfileProvider).valueOrNull?.country);

    return Scaffold(
      appBar: AppBar(
        title: Text(r.type.label),
        actions: [
          IconButton(
            icon: Icon(isSaved
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded),
            tooltip: isSaved ? 'Saved' : 'Save',
            onPressed: () {
              final ctrl = ref.read(savedResourceControllerProvider);
              if (!ctrl.isReady) return;
              ctrl.toggle(r, saved);
              ref
                  .read(analyticsProvider)
                  .log('opportunity_saved', {'id': r.id, 'type': r.type.key});
              if (!saved.contains(r.id)) {
                ref.read(metricsServiceProvider).record(
                    resourceId: r.id,
                    event: 'save',
                    type: r.type.key,
                    title: r.title);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Share',
            onPressed: _share,
          ),
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Report an issue',
            onPressed: _report,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ResourceThumb(resource: r, size: 64, preferLogo: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(r.brandName,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ResourcePill(
                  label: r.type.label,
                  color: r.type.color,
                  icon: r.type.icon),
              if (!isDiscount && match.personalized && match.score > 0)
                ResourcePill(
                  label: '${match.score}% · ${match.tier.label}',
                  color: AppColors.success,
                  icon: Icons.auto_awesome_rounded,
                ),
              ResourcePill(label: status.label, color: status.color),
              if (r.sponsored)
                const ResourcePill(label: 'Sponsored', color: AppColors.accent),
              if (r.verified)
                const ResourcePill(
                    label: 'Verified',
                    color: AppColors.info,
                    icon: Icons.verified_rounded),
              if (r.remote == true)
                const ResourcePill(label: 'Remote', color: AppColors.primary),
              if (r.paid == true)
                const ResourcePill(label: 'Paid', color: AppColors.success),
            ],
          ),
          const SizedBox(height: 16),
          if (isDiscount && (resolvedOffer.discountText?.isNotEmpty ?? false))
            _discountBanner(theme, resolvedOffer.discountText!),
          if (r.deadline != null) _deadlineCard(theme),
          if (r.description.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(theme, 'About'),
            Text(r.description, style: theme.textTheme.bodyMedium),
          ],
          if (!isDiscount && r.benefits != null && r.benefits!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(theme, 'Benefits'),
            Text(r.benefits!, style: theme.textTheme.bodyMedium),
          ],
          if (r.eligibility != null && r.eligibility!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(theme, 'Eligibility'),
            Text(r.eligibility!, style: theme.textTheme.bodyMedium),
          ],
          if (!isDiscount &&
              r.howToApply != null &&
              r.howToApply!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(theme, 'How to apply'),
            Text(r.howToApply!, style: theme.textTheme.bodyMedium),
          ],
          if (isDiscount &&
              r.redemptionInstructions != null &&
              r.redemptionInstructions!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(theme, 'How to redeem'),
            Text(r.redemptionInstructions!, style: theme.textTheme.bodyMedium),
          ],
          if (isDiscount && r.verificationRequired) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: softCard(context),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined,
                      size: 18, color: AppColors.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Student verification is handled by the partner on their '
                      'site when you redeem.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (r.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(theme, 'Tags'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in r.tags)
                  Chip(
                    label: Text(t),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          if (isDiscount && r.terms != null && r.terms!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _section(theme, 'Terms'),
            Text(r.terms!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ],
          if (related.isNotEmpty) ...[
            const SizedBox(height: 24),
            _section(theme, isDiscount ? 'Related deals' : 'Related opportunities'),
            const SizedBox(height: 4),
            for (final rel in related)
              ResourceCard(
                resource: rel,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ResourceDetailScreen(resource: rel))),
              ),
          ],
        ],
      ),
      bottomNavigationBar: _bottomBar(context, status),
    );
  }

  Widget _bottomBar(BuildContext context, ResourceStatus status) {
    // "Opening soon" is not yet available — the CTA is disabled and the link
    // must not open, for discounts and opportunities alike.
    final comingSoon = status == ResourceStatus.openingSoon;
    final canAct = !comingSoon && (status.isOpen || r.type.isDiscount);
    final label = r.type.isDiscount ? 'Redeem perk' : 'Apply now';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton.icon(
          onPressed: canAct ? _open : null,
          icon: Icon(r.type.isDiscount
              ? Icons.redeem_rounded
              : Icons.open_in_new_rounded),
          label: Text(canAct ? label : status.label),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _discountBanner(ThemeData theme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Student offer',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 4),
          Text(text,
              style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _deadlineCard(ThemeData theme) {
    final days = r.daysUntilDeadline;
    final closed = days != null && days < 0;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: softCard(context),
        child: Row(
          children: [
            Icon(Icons.event_rounded,
                color: closed ? AppColors.danger : AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(closed ? 'Applications closed' : 'Deadline',
                      style: theme.textTheme.labelMedium),
                  Text(
                    '${DateUtilsX.prettyDate(r.deadline!)}'
                    '${days != null && days >= 0 ? ' · in $days days' : ''}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: theme.textTheme.titleMedium),
      );

  /// Related = same type, feed-visible, excluding this resource. Powers the
  /// "no dead ends" behaviour when an opportunity expires/discontinues.
  List<Resource> _related(WidgetRef ref) {
    final all = ref.watch(visibleResourcesProvider).valueOrNull ?? const [];
    return ResourceQueries.related(r, all);
  }
}
