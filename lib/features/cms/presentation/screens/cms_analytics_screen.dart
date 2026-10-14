import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../opportunities/presentation/providers/opportunities_providers.dart';
import '../../domain/cms_analytics.dart';
import '../../domain/cms_role.dart';
import '../providers/cms_analytics_providers.dart';
import '../providers/cms_marketing_providers.dart';
import 'cms_sponsor_report_screen.dart';

/// CMS analytics: real student engagement (from the counter pipeline) plus
/// live content inventory. Engagement is derived from `metricsDaily` (windowed
/// funnel/totals) and `resourceMetrics` (all-time Top Content) — GA events are
/// not queryable from Firestore, so these backend counters are the source.
class CmsAnalyticsScreen extends ConsumerStatefulWidget {
  final CmsRole role;
  const CmsAnalyticsScreen({super.key, required this.role});

  @override
  ConsumerState<CmsAnalyticsScreen> createState() => _CmsAnalyticsScreenState();
}

class _CmsAnalyticsScreenState extends ConsumerState<CmsAnalyticsScreen> {
  int _windowDays = 30;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daily = ref.watch(cmsDailyMetricsProvider);
    final resMetrics = ref.watch(cmsResourceMetricsProvider);
    final inv = ref.watch(visibleResourcesProvider);

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text('Analytics', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Real student engagement + live content inventory.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 20),

        // ── Engagement (windowed) ──────────────────────────────────────────
        Row(
          children: [
            Text(
              'Engagement',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            for (final d in const [7, 30, 90])
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: Text('${d}d'),
                  selected: _windowDays == d,
                  onSelected: (_) => setState(() => _windowDays = d),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        daily.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, __) => Text('Failed to load engagement: $e'),
          data: (list) {
            final t = sumDailyWithinDays(list, _windowDays);
            final noData = t.isEmpty;
            if (noData) {
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: softCard(context),
                child: Text(
                  'No engagement recorded in the last $_windowDays days yet. '
                  'Events are collected as students view, click, apply, save and '
                  'share resources in the app.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _Metric(
                      'Impressions',
                      '${t.impressions}',
                      Icons.visibility_outlined,
                      AppColors.primary,
                    ),
                    _Metric(
                      'Views',
                      '${t.views}',
                      Icons.visibility_rounded,
                      AppColors.primary,
                    ),
                    _Metric(
                      'Feed CTR',
                      '${(t.feedCtr * 100).toStringAsFixed(1)}%',
                      Icons.percent_rounded,
                      AppColors.success,
                    ),
                    _Metric(
                      'Clicks',
                      '${t.clicks}',
                      Icons.ads_click_rounded,
                      AppColors.info,
                    ),
                    _Metric(
                      'Applies',
                      '${t.applies}',
                      Icons.task_alt_rounded,
                      AppColors.success,
                    ),
                    _Metric(
                      'Saves',
                      '${t.saves}',
                      Icons.bookmark_rounded,
                      AppColors.accent,
                    ),
                    _Metric(
                      'Shares',
                      '${t.shares}',
                      Icons.ios_share_rounded,
                      AppColors.coral,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Funnel(totals: t),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // ── Sponsor performance (all-time) ─────────────────────────────────
        _SponsorSection(metrics: resMetrics.valueOrNull ?? const []),
        const SizedBox(height: 24),

        // ── Banner performance (all-time) ──────────────────────────────────
        const _BannerSection(),
        const SizedBox(height: 24),

        // ── Top content (all-time) ─────────────────────────────────────────
        Text(
          'Top content (all-time)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        resMetrics.when(
          loading: () => const SizedBox.shrink(),
          error: (e, __) => Text('Failed to load top content: $e'),
          data: (list) {
            if (list.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: softCard(context),
                child: Text(
                  'No engagement data yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              );
            }
            return Column(
              children: [
                _TopList(
                  title: 'Most viewed',
                  items: topResourcesBy(list, (t) => t.views),
                  value: (t) => t.views,
                ),
                const SizedBox(height: 12),
                _TopList(
                  title: 'Most clicked',
                  items: topResourcesBy(list, (t) => t.clicks),
                  value: (t) => t.clicks,
                ),
                const SizedBox(height: 12),
                _TopList(
                  title: 'Most saved',
                  items: topResourcesBy(list, (t) => t.saves),
                  value: (t) => t.saves,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),

        // ── Inventory (live content DB) ────────────────────────────────────
        Text(
          'Content inventory',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        inv.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, __) => Text('Failed to load inventory.\n$e'),
          data: (all) {
            final opportunities = all.where((r) => !r.type.isDiscount).length;
            final discounts = all.where((r) => r.type.isDiscount).length;
            final sponsored = all.where((r) => r.sponsored).length;
            final active = all.where((r) => r.isInActiveFeed).length;
            final byStatus = <String, int>{};
            final byType = <String, int>{};
            for (final r in all) {
              byStatus.update(
                r.effectiveStatus.label,
                (v) => v + 1,
                ifAbsent: () => 1,
              );
              byType.update(r.type.label, (v) => v + 1, ifAbsent: () => 1);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _Metric(
                      'Visible resources',
                      '${all.length}',
                      Icons.inventory_2_rounded,
                      AppColors.primary,
                    ),
                    _Metric(
                      'Opportunities',
                      '$opportunities',
                      Icons.explore_rounded,
                      AppColors.info,
                    ),
                    _Metric(
                      'Discounts',
                      '$discounts',
                      Icons.local_offer_rounded,
                      AppColors.success,
                    ),
                    _Metric(
                      'Active in feed',
                      '$active',
                      Icons.bolt_rounded,
                      AppColors.accent,
                    ),
                    _Metric(
                      'Sponsored',
                      '$sponsored',
                      Icons.star_rounded,
                      AppColors.coral,
                    ),
                    if (widget.role.canManageMarketing)
                      const _MarketingMetrics(),
                  ],
                ),
                const SizedBox(height: 16),
                _Breakdown(title: 'By status', data: byStatus),
                const SizedBox(height: 16),
                _Breakdown(title: 'By type', data: byType),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Viewed → Clicked → Applied funnel with conversion rates.
class _Funnel extends StatelessWidget {
  final MetricTotals totals;
  const _Funnel({required this.totals});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
    Widget stage(String label, int value, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
    Widget arrow(String rate) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.chevron_right_rounded, color: Colors.grey),
          Text(
            rate,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: softCard(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          stage('Shown', totals.impressions, AppColors.primary),
          arrow(pct(totals.feedCtr)),
          stage('Viewed', totals.views, AppColors.primary),
          arrow(pct(totals.clickRate)),
          stage('Clicked', totals.clicks, AppColors.info),
          arrow(pct(totals.applyRate)),
          stage('Applied', totals.applies, AppColors.success),
        ],
      ),
    );
  }
}

/// A ranked list of resources by a chosen metric.
class _TopList extends StatelessWidget {
  final String title;
  final List<ResourceMetric> items;
  final int Function(MetricTotals) value;
  const _TopList({
    required this.title,
    required this.items,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: softCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              'No data yet',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            )
          else
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        items[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${value(items[i].totals)}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Live banner/campaign counts — only rendered for marketing roles (they can
/// read unpublished marketing docs).
class _MarketingMetrics extends ConsumerWidget {
  const _MarketingMetrics();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banners = ref.watch(cmsBannersProvider).valueOrNull ?? const [];
    final campaigns = ref.watch(cmsCampaignsProvider).valueOrNull ?? const [];
    final liveBanners = banners.where((b) => b.isLive()).length;
    final liveCampaigns = campaigns.where((c) => c.isLive()).length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Metric(
          'Live banners',
          '$liveBanners',
          Icons.view_carousel_rounded,
          AppColors.primary,
        ),
        const SizedBox(width: 16),
        _Metric(
          'Live campaigns',
          '$liveCampaigns',
          Icons.campaign_rounded,
          AppColors.info,
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Metric(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 200,
      padding: const EdgeInsets.all(18),
      decoration: softCard(context),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  final String title;
  final Map<String, int> data;
  const _Breakdown({required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.isEmpty
        ? 1
        : entries.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: softCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              'No data yet',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            )
          else
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(width: 160, child: Text(e.key)),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: e.value / max,
                          minHeight: 8,
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.10,
                          ),
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${e.value}', style: theme.textTheme.labelLarge),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

String _rate(double v) => '${(v * 100).toStringAsFixed(1)}%';

/// A horizontally scrollable data table card with a title + subtitle.
class _TableCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> columns;
  final List<List<Widget>> rows;
  final String emptyText;
  const _TableCard({
    required this.title,
    required this.subtitle,
    required this.columns,
    required this.rows,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: softCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                emptyText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 22,
                headingRowHeight: 38,
                dataRowMinHeight: 40,
                dataRowMaxHeight: 48,
                columns: [
                  for (var i = 0; i < columns.length; i++)
                    DataColumn(
                      label: Text(
                        columns[i],
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      numeric: i > 0 && i < columns.length - 1,
                    ),
                ],
                rows: [
                  for (final r in rows)
                    DataRow(cells: [for (final c in r) DataCell(c)]),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

Widget _cellText(String s, {double maxWidth = 220}) => ConstrainedBox(
  constraints: BoxConstraints(maxWidth: maxWidth),
  child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
);

/// Sponsored items + a per-sponsor rollup, each with a full report.
class _SponsorSection extends StatelessWidget {
  final List<ResourceMetric> metrics;
  const _SponsorSection({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sponsored = metrics.where((m) => m.sponsored).toList()
      ..sort(
        (a, b) => b.totals.impressions != a.totals.impressions
            ? b.totals.impressions.compareTo(a.totals.impressions)
            : b.totals.views.compareTo(a.totals.views),
      );
    final rollup = rollupBySponsor(metrics);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sponsor performance (all-time)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Open "Report" for a date range, daily trend, audience by country '
          'and a CSV to send to the sponsor.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 12),
        _TableCard(
          title: 'By sponsor',
          subtitle: 'Reach is summed per item.',
          emptyText:
              'No sponsored engagement yet. Mark resources as Sponsored to track them here.',
          columns: const [
            'Sponsor',
            'Items',
            'Impressions',
            'Reach',
            'Views',
            'Clicks',
            'Applies',
            'CTR',
          ],
          rows: [
            for (final s in rollup)
              [
                _cellText(s.brand),
                Text('${s.items}'),
                Text('${s.totals.impressions}'),
                Text('${s.uniques.reach}'),
                Text('${s.totals.views}'),
                Text('${s.totals.clicks}'),
                Text('${s.totals.applies}'),
                Text(_rate(s.totals.feedCtr)),
              ],
          ],
        ),
        const SizedBox(height: 12),
        _TableCard(
          title: 'Sponsored items',
          subtitle: 'CTR = detail views ÷ impressions.',
          emptyText: 'No sponsored items with data yet.',
          columns: const [
            'Item',
            'Impressions',
            'Reach',
            'Views',
            'CTR',
            'Clicks',
            'Applies',
            'Saves',
            '',
          ],
          rows: [
            for (final m in sponsored)
              [
                _cellText(m.title),
                Text('${m.totals.impressions}'),
                Text('${m.uniques.reach}'),
                Text('${m.totals.views}'),
                Text(_rate(m.totals.feedCtr)),
                Text('${m.totals.clicks}'),
                Text('${m.totals.applies}'),
                Text('${m.totals.saves}'),
                TextButton.icon(
                  onPressed: () =>
                      CmsSponsorReportScreen.openResource(context, m),
                  icon: const Icon(Icons.insights_rounded, size: 18),
                  label: const Text('Report'),
                ),
              ],
          ],
        ),
      ],
    );
  }
}

/// Banner impressions, reach, clicks and CTR.
class _BannerSection extends ConsumerWidget {
  const _BannerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final list = [
      ...ref.watch(cmsBannerMetricsProvider).valueOrNull ??
          const <BannerMetric>[],
    ]..sort((a, b) => b.totals.impressions.compareTo(a.totals.impressions));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Banner performance (all-time)',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _TableCard(
          title: 'Banners',
          subtitle: 'CTR = clicks ÷ impressions.',
          emptyText:
              'No banner data yet. It appears once students on the new app version see a banner.',
          columns: const [
            'Banner',
            'Impressions',
            'Reach',
            'Clicks',
            'CTR',
            '',
          ],
          rows: [
            for (final b in list)
              [
                _cellText(
                  '${b.title}${b.sponsored ? ' ★' : ''}'
                  '${b.placement != null ? ' · ${b.placement}' : ''}',
                  maxWidth: 260,
                ),
                Text('${b.totals.impressions}'),
                Text('${b.uniques.reach}'),
                Text('${b.totals.clicks}'),
                Text(_rate(b.ctr)),
                TextButton.icon(
                  onPressed: () =>
                      CmsSponsorReportScreen.openBanner(context, b),
                  icon: const Icon(Icons.insights_rounded, size: 18),
                  label: const Text('Report'),
                ),
              ],
          ],
        ),
      ],
    );
  }
}
