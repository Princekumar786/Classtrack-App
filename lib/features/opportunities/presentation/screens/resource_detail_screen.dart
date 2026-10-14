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
import '../../../subscription/presentation/providers/subscription_providers.dart';
import '../../data/resource_repository.dart';
import '../../domain/resource.dart';
import '../../domain/resource_status.dart';
import '../providers/opportunities_providers.dart';
import '../widgets/content_blocks_view.dart';
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
    final country = ref.read(effectiveCountryProvider);
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
        r.effectiveOffer(ref.watch(effectiveCountryProvider));

    return Scaffold(
      appBar: AppBar(
        // No title: with three actions it truncated ("Student discou…"), and
        // the hero card below already shows the type pill.
        scrolledUnderElevation: 0,
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
          // ── Hero identity card ──────────────────────────────────────────
          // Groups the logo, title, brand and status pills into one cohesive
          // header so the "what/who/state" reads at a glance.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: softCard(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: ResourceThumb(
                          resource: r, size: 72, preferLogo: true),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800, height: 1.2)),
                          if (_showBrand) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(r.brandName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              color: theme.hintColor,
                                              fontWeight: FontWeight.w600)),
                                ),
                                if (r.verified) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.verified_rounded,
                                      size: 16, color: AppColors.info),
                                ],
                              ],
                            ),
                          ] else if (r.verified) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.verified_rounded,
                                    size: 16, color: AppColors.info),
                                const SizedBox(width: 4),
                                Text('Verified partner',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: AppColors.info,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
                      const ResourcePill(
                          label: 'Sponsored', color: AppColors.accent),
                    if (r.remote == true)
                      const ResourcePill(
                          label: 'Remote', color: AppColors.primary),
                    if (r.paid == true)
                      const ResourcePill(
                          label: 'Paid', color: AppColors.success),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (isDiscount &&
              (resolvedOffer.discountText?.isNotEmpty ?? false)) ...[
            _discountBanner(theme, resolvedOffer.discountText!),
          ],
          if (r.deadline != null) _deadlineCard(theme),
          if (r.description.isNotEmpty)
            _sectionCard(theme, 'About', Icons.info_outline_rounded,
                ContentBlocksView(text: r.description, collapsible: true)),
          if (!isDiscount && r.benefits != null && r.benefits!.isNotEmpty)
            _sectionCard(theme, 'Benefits', Icons.emoji_events_outlined,
                ContentBlocksView(
                    text: r.benefits!, accent: AppColors.success)),
          if (r.eligibility != null && r.eligibility!.isNotEmpty)
            _sectionCard(theme, 'Eligibility', Icons.how_to_reg_outlined,
                ContentBlocksView(text: r.eligibility!)),
          if (!isDiscount &&
              r.howToApply != null &&
              r.howToApply!.isNotEmpty)
            _sectionCard(theme, 'How to apply', Icons.route_rounded,
                ContentBlocksView(text: r.howToApply!)),
          if (isDiscount &&
              r.redemptionInstructions != null &&
              r.redemptionInstructions!.isNotEmpty)
            _sectionCard(theme, 'How to redeem', Icons.route_rounded,
                ContentBlocksView(text: r.redemptionInstructions!)),
          if (isDiscount && r.verificationRequired) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: softCard(context,
                  color: AppColors.info.withValues(alpha: 0.08), shadow: false),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined,
                      size: 18, color: AppColors.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Student verification is handled by the partner on their '
                      'site when you redeem.',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (r.tags.isNotEmpty) ...[
            const SizedBox(height: 20),
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
            const SizedBox(height: 20),
            _section(theme, 'Terms'),
            Text(r.terms!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor, height: 1.5)),
          ],
          if (related.isNotEmpty) ...[
            const SizedBox(height: 26),
            _section(theme,
                isDiscount ? 'Related deals' : 'Related opportunities'),
            const SizedBox(height: 4),
            for (final rel in related)
              ResourceCard(
                resource: rel,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    settings: const RouteSettings(name: 'Resource Detail'),
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
    final icon = r.type.isDiscount
        ? Icons.redeem_rounded
        : Icons.open_in_new_rounded;

    if (!canAct) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            onPressed: null,
            icon: Icon(icon),
            label: Text(status.label),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [AppColors.primaryLight, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: AppColors.softShadow(opacity: 0.28, blur: 18),
          ),
          child: FilledButton.icon(
            onPressed: _open,
            icon: Icon(icon),
            label: Text(label),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _discountBanner(ThemeData theme, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryLight, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.softShadow(opacity: 0.22, blur: 18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Student offer',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(text,
                    style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_offer_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _deadlineCard(ThemeData theme) {
    final days = r.daysUntilDeadline;
    final closed = days != null && days < 0;
    final accent = closed ? AppColors.danger : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: softCard(context),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.event_rounded, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(closed ? 'Applications closed' : 'Deadline',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.hintColor)),
                  const SizedBox(height: 2),
                  Text(
                    '${DateUtilsX.prettyDate(r.deadline!)}'
                    '${days != null && days >= 0 ? ' · in $days days' : ''}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hide the brand line when it just repeats the title ("Wix" / "Wix").
  bool get _showBrand {
    final brand = r.brandName.trim().toLowerCase();
    return brand.isNotEmpty && brand != r.title.trim().toLowerCase();
  }

  /// A content section grouped in its own card: tinted icon + title header,
  /// then the structured body. Cards give each section a clear boundary so
  /// long pages scan as distinct chunks instead of one text stream.
  Widget _sectionCard(
      ThemeData theme, String title, IconData icon, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: softCard(context, radius: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Semantics(
                  header: true,
                  child: Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _section(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Text(text,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  /// Related = same type, feed-visible, excluding this resource. Powers the
  /// "no dead ends" behaviour when an opportunity expires/discontinues.
  ///
  /// Free members only see related items that are inside their free window
  /// (the latest [kFreeResourceLimit] of the matching feed), computed exactly
  /// like the Opportunities / Perks screens. A post opened from a push is
  /// always viewable, but it must not become a side door into the locked
  /// catalogue via this list.
  List<Resource> _related(WidgetRef ref) {
    final all = ref.watch(visibleResourcesProvider).valueOrNull ?? const [];
    final related = ResourceQueries.related(r, all);
    final isPro = ref.watch(isProProvider);
    if (isPro) return related;

    final country = ref.watch(effectiveCountryProvider);
    final hidden =
        ref.watch(hiddenResourceIdsProvider).valueOrNull ?? const <String>{};
    final feed = all
        .where((x) => x.type.isDiscount == r.type.isDiscount)
        .where((x) => x.isInActiveFeed)
        .where((x) => x.targetsCountry(country))
        .where((x) => !hidden.contains(x.id))
        .toList();
    final allowed = freeAllowedIds(feed, isPro: false);
    if (allowed == null) return related;
    return related.where((x) => allowed.contains(x.id)).toList();
  }
}
