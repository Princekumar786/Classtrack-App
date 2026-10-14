import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../data/file_download.dart';
import '../../domain/cms_analytics.dart';
import '../providers/cms_analytics_providers.dart';

/// A sponsor-ready report for ONE resource or banner: headline KPIs for a
/// window (last 7/30/90 days or the campaign's own dates), a daily trend,
/// reach by country and a one-click CSV to send to the sponsor.
class CmsSponsorReportScreen extends ConsumerStatefulWidget {
  /// `resourceMetrics` or `bannerMetrics`.
  final String collection;
  final String itemId;
  final String title;
  final String? brand;
  final UniqueCounts uniques;

  /// A campaign's own dates, offered as the default window when set.
  final ReportWindow? campaignWindow;

  const CmsSponsorReportScreen({
    super.key,
    required this.collection,
    required this.itemId,
    required this.title,
    this.brand,
    this.uniques = const UniqueCounts(),
    this.campaignWindow,
  });

  /// Opens the report for a resource.
  static Future<void> openResource(
    BuildContext context,
    ResourceMetric m, {
    ReportWindow? campaignWindow,
    String? brand,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      settings: const RouteSettings(name: 'Cms Sponsor Report'),
      builder: (_) => CmsSponsorReportScreen(
        collection: AppConstants.resourceMetricsCollection,
        itemId: m.id,
        title: m.title,
        brand: brand ?? m.brand,
        uniques: m.uniques,
        campaignWindow: campaignWindow,
      ),
    ),
  );

  /// Opens the report for a banner.
  static Future<void> openBanner(BuildContext context, BannerMetric m) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'Cms Sponsor Report'),
          builder: (_) => CmsSponsorReportScreen(
            collection: kBannerMetricsCollection,
            itemId: m.id,
            title: m.title,
            uniques: m.uniques,
          ),
        ),
      );

  @override
  ConsumerState<CmsSponsorReportScreen> createState() =>
      _CmsSponsorReportScreenState();
}

class _CmsSponsorReportScreenState
    extends ConsumerState<CmsSponsorReportScreen> {
  /// 0 = campaign dates; otherwise last N days.
  late int _days = widget.campaignWindow != null ? 0 : 30;

  ReportWindow get _window => _days == 0 && widget.campaignWindow != null
      ? widget.campaignWindow!
      : ReportWindow.lastDays(_days == 0 ? 30 : _days);

  bool get _isBanner => widget.collection == kBannerMetricsCollection;

  void _download(List<DailyMetric> series) {
    final csv = buildSponsorReportCsv(
      title: widget.title,
      brand: widget.brand,
      window: _window,
      series: series,
      uniques: widget.uniques,
    );
    final safe = widget.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    downloadTextFile(
      'classtrack-report-${safe.isEmpty ? widget.itemId : safe}-'
          '${_window.startId}-${_window.endId}.csv',
      'text/csv',
      csv,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daily = ref.watch(
      cmsItemDailyProvider((collection: widget.collection, id: widget.itemId)),
    );
    final window = _window;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isBanner ? 'Banner report' : 'Sponsor report'),
        actions: [
          if (canDownloadFiles)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: daily.valueOrNull == null
                    ? null
                    : () => _download(seriesFor(daily.value!, window)),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Download CSV'),
              ),
            ),
        ],
      ),
      body: daily.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(child: Text('Failed to load report.\n$e')),
        data: (buckets) {
          final series = seriesFor(buckets, window);
          final t = series.fold(const MetricTotals(), (s, d) => s + d.totals);
          final u = widget.uniques;
          String pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

          return ListView(
            padding: const EdgeInsets.all(28),
            children: [
              Text(widget.title, style: theme.textTheme.headlineSmall),
              if (widget.brand != null && widget.brand!.isNotEmpty)
                Text(
                  widget.brand!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (widget.campaignWindow != null)
                    ChoiceChip(
                      label: const Text('Campaign dates'),
                      selected: _days == 0,
                      onSelected: (_) => setState(() => _days = 0),
                    ),
                  for (final d in const [7, 30, 90])
                    ChoiceChip(
                      label: Text('${d}d'),
                      selected: _days == d,
                      onSelected: (_) => setState(() => _days = d),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    '${prettyDayId(window.startId)} → ${prettyDayId(window.endId)} (UTC)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _Kpi(
                    'Impressions',
                    '${t.impressions}',
                    Icons.visibility_outlined,
                    AppColors.primary,
                    hint: 'Times shown in a feed (once per session)',
                  ),
                  if (_isBanner) ...[
                    _Kpi(
                      'Clicks',
                      '${t.clicks}',
                      Icons.ads_click_rounded,
                      AppColors.info,
                    ),
                    _Kpi(
                      'CTR',
                      pct(t.impressions == 0 ? 0 : t.clicks / t.impressions),
                      Icons.percent_rounded,
                      AppColors.success,
                      hint: 'Clicks ÷ impressions',
                    ),
                  ] else ...[
                    _Kpi(
                      'Detail views',
                      '${t.views}',
                      Icons.open_in_new_rounded,
                      AppColors.info,
                    ),
                    _Kpi(
                      'Feed CTR',
                      pct(t.feedCtr),
                      Icons.percent_rounded,
                      AppColors.success,
                      hint: 'Views ÷ impressions',
                    ),
                    _Kpi(
                      'Link clicks',
                      '${t.clicks}',
                      Icons.ads_click_rounded,
                      AppColors.accent,
                      hint: '${pct(t.clickRate)} of viewers',
                    ),
                    _Kpi(
                      'Applies',
                      '${t.applies}',
                      Icons.task_alt_rounded,
                      AppColors.success,
                    ),
                    _Kpi(
                      'Saves',
                      '${t.saves}',
                      Icons.bookmark_rounded,
                      AppColors.coral,
                    ),
                    _Kpi(
                      'Shares',
                      '${t.shares}',
                      Icons.ios_share_rounded,
                      AppColors.coral,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _Kpi(
                    'Unique reach',
                    '${u.reach}',
                    Icons.groups_rounded,
                    AppColors.primary,
                    hint: 'All-time unique students',
                  ),
                  if (!_isBanner)
                    _Kpi(
                      'Unique viewers',
                      '${u.viewers}',
                      Icons.person_search_rounded,
                      AppColors.info,
                      hint: 'All-time',
                    ),
                  _Kpi(
                    'Unique clickers',
                    '${u.clickers}',
                    Icons.touch_app_rounded,
                    AppColors.accent,
                    hint: 'All-time',
                  ),
                  _Kpi(
                    'Frequency',
                    u.frequency(t).toStringAsFixed(1),
                    Icons.repeat_rounded,
                    AppColors.coral,
                    hint:
                        'Impressions per reached student (window ÷ all-time reach)',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _TrendCard(series: series, isBanner: _isBanner),
              const SizedBox(height: 24),
              _CountriesCard(uniques: u),
              const SizedBox(height: 16),
              Text(
                'Counts update a few seconds after students act. Impressions '
                'are counted once per student per app session. Unique counts '
                'are all-time; data before this report was added only has '
                'views/clicks/applies/saves/shares.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;
  const _Kpi(this.label, this.value, this.icon, this.color, {this.hint});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = Container(
      width: 190,
      padding: const EdgeInsets.all(16),
      decoration: softCard(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
    return hint == null ? card : Tooltip(message: hint!, child: card);
  }
}

/// Simple dependency-free daily bar chart (impressions behind, views/clicks
/// in front) so the CMS needs no chart package.
class _TrendCard extends StatelessWidget {
  final List<DailyMetric> series;
  final bool isBanner;
  const _TrendCard({required this.series, required this.isBanner});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    int front(MetricTotals t) => isBanner ? t.clicks : t.views;
    final maxV = series.fold<int>(
      1,
      (m, d) => [
        m,
        d.totals.impressions,
        front(d.totals),
      ].reduce((a, b) => a > b ? a : b),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: softCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Daily trend',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _Legend(AppColors.primary.withValues(alpha: 0.25), 'Impressions'),
              const SizedBox(width: 14),
              _Legend(AppColors.primary, isBanner ? 'Clicks' : 'Views'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final d in series)
                  Expanded(
                    child: Tooltip(
                      message:
                          '${prettyDayId(d.day)}\n'
                          '${d.totals.impressions} impressions · '
                          '${front(d.totals)} ${isBanner ? 'clicks' : 'views'}',
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: series.length > 45 ? 0.5 : 2,
                        ),
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            FractionallySizedBox(
                              heightFactor: d.totals.impressions / maxV,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.25,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            FractionallySizedBox(
                              heightFactor: front(d.totals) / maxV,
                              widthFactor: 0.6,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                prettyDayId(series.first.day),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const Spacer(),
              Text(
                prettyDayId(series.last.day),
                style: theme.textTheme.labelSmall?.copyWith(
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

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend(this.color, this.label);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _CountriesCard extends StatelessWidget {
  final UniqueCounts uniques;
  const _CountriesCard({required this.uniques});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = uniques.topCountries.take(10).toList();
    final total = uniques.reachByCountry.values.fold(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: softCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Audience by country (unique reach)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (top.isEmpty)
            Text(
              'No reach data yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            )
          else
            for (final c in top)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        c.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : c.value / total,
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
                    SizedBox(
                      width: 90,
                      child: Text(
                        '${c.value} · ${total == 0 ? 0 : (c.value * 100 / total).round()}%',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelLarge,
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
