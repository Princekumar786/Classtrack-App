// Pure analytics aggregation for the CMS, over the backend-written counters
// (`metricsDaily` global per-day totals, `resourceMetrics` / `bannerMetrics`
// per-item all-time totals, and their `daily/{yyyymmdd}` sub-buckets).
// Flutter/Firestore-free so it's unit-testable.

class MetricTotals {
  /// Times a card/banner was shown in a feed (once per user session).
  final int impressions;
  final int views;
  final int clicks;
  final int applies;
  final int saves;
  final int shares;

  const MetricTotals({
    this.impressions = 0,
    this.views = 0,
    this.clicks = 0,
    this.applies = 0,
    this.saves = 0,
    this.shares = 0,
  });

  static int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  factory MetricTotals.fromMap(Map<String, dynamic> m) => MetricTotals(
    impressions: _i(m['impressions']),
    views: _i(m['views']),
    clicks: _i(m['clicks']),
    applies: _i(m['applies']),
    saves: _i(m['saves']),
    shares: _i(m['shares']),
  );

  MetricTotals operator +(MetricTotals o) => MetricTotals(
    impressions: impressions + o.impressions,
    views: views + o.views,
    clicks: clicks + o.clicks,
    applies: applies + o.applies,
    saves: saves + o.saves,
    shares: shares + o.shares,
  );

  bool get isEmpty =>
      impressions == 0 &&
      views == 0 &&
      clicks == 0 &&
      applies == 0 &&
      saves == 0 &&
      shares == 0;

  /// Feed click-through rate: detail views ÷ impressions (0..1).
  double get feedCtr => impressions == 0 ? 0 : views / impressions;

  /// Clicks ÷ views (0..1) — how many who opened it tapped the sponsor link.
  double get clickRate => views == 0 ? 0 : clicks / views;

  /// Applies ÷ clicks (0..1).
  double get applyRate => clicks == 0 ? 0 : applies / clicks;

  /// Saves + shares — "engagement actions" sponsors care about beyond clicks.
  int get engagements => saves + shares;
}

/// Unique-user counts (all-time; the backend keeps one marker per user).
class UniqueCounts {
  /// Users who saw it anywhere (feed impression or detail view).
  final int reach;
  final int viewers;
  final int clickers;

  /// Reach split by the student's profile country.
  final Map<String, int> reachByCountry;

  const UniqueCounts({
    this.reach = 0,
    this.viewers = 0,
    this.clickers = 0,
    this.reachByCountry = const {},
  });

  factory UniqueCounts.fromMap(Map<String, dynamic> m) {
    final raw = m['reachByCountry'];
    final byCountry = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final n = (v as num?)?.toInt() ?? 0;
        if (n > 0) byCountry[k.toString()] = n;
      });
    }
    return UniqueCounts(
      reach: MetricTotals._i(m['reach']),
      viewers: MetricTotals._i(m['uniqueViewers']),
      clickers: MetricTotals._i(m['uniqueClickers']),
      reachByCountry: byCountry,
    );
  }

  UniqueCounts operator +(UniqueCounts o) {
    final merged = {...reachByCountry};
    o.reachByCountry.forEach((k, v) => merged[k] = (merged[k] ?? 0) + v);
    return UniqueCounts(
      reach: reach + o.reach,
      viewers: viewers + o.viewers,
      clickers: clickers + o.clickers,
      reachByCountry: merged,
    );
  }

  /// Countries by reach, highest first.
  List<MapEntry<String, int>> get topCountries =>
      reachByCountry.entries.toList()..sort(
        (a, b) => b.value != a.value
            ? b.value.compareTo(a.value)
            : a.key.compareTo(b.key),
      );

  /// Average impressions per reached user (ad "frequency").
  double frequency(MetricTotals t) => reach == 0 ? 0 : t.impressions / reach;
}

/// UTC yyyymmdd bucket id — MUST match the Cloud Function's `dayId`.
String dayIdFor(DateTime date) {
  final d = date.toUtc();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}$m$day';
}

/// yyyymmdd → "2026-10-11".
String prettyDayId(String id) => id.length == 8
    ? '${id.substring(0, 4)}-${id.substring(4, 6)}-${id.substring(6, 8)}'
    : id;

/// A single day's totals (global, or for one resource/banner).
class DailyMetric {
  final String day; // yyyymmdd
  final MetricTotals totals;
  const DailyMetric(this.day, this.totals);

  factory DailyMetric.fromMap(String id, Map<String, dynamic> m) =>
      DailyMetric((m['day'] as String?) ?? id, MetricTotals.fromMap(m));
}

/// Per-resource all-time totals (Top Content + sponsor reports).
class ResourceMetric {
  final String id;
  final String title;
  final String? type;
  final String? brand;
  final bool sponsored;
  final MetricTotals totals;
  final UniqueCounts uniques;
  const ResourceMetric({
    required this.id,
    required this.title,
    required this.type,
    required this.totals,
    this.brand,
    this.sponsored = false,
    this.uniques = const UniqueCounts(),
  });

  factory ResourceMetric.fromMap(String id, Map<String, dynamic> m) =>
      ResourceMetric(
        id: id,
        title: (m['title'] as String?) ?? '($id)',
        type: m['type'] as String?,
        brand: m['brand'] as String?,
        sponsored: m['sponsored'] == true,
        totals: MetricTotals.fromMap(m),
        uniques: UniqueCounts.fromMap(m),
      );
}

/// Per-banner all-time totals (impressions + clicks).
class BannerMetric {
  final String id;
  final String title;
  final String? placement;
  final bool sponsored;
  final MetricTotals totals;
  final UniqueCounts uniques;
  const BannerMetric({
    required this.id,
    required this.title,
    required this.totals,
    this.placement,
    this.sponsored = false,
    this.uniques = const UniqueCounts(),
  });

  /// Banner CTR: clicks ÷ impressions (0..1).
  double get ctr =>
      totals.impressions == 0 ? 0 : totals.clicks / totals.impressions;

  factory BannerMetric.fromMap(String id, Map<String, dynamic> m) =>
      BannerMetric(
        id: id,
        title: (m['title'] as String?) ?? '($id)',
        placement: m['placement'] as String?,
        sponsored: m['sponsored'] == true,
        totals: MetricTotals.fromMap(m),
        uniques: UniqueCounts.fromMap(m),
      );
}

/// Sums the daily totals for the last [days] days (inclusive of today, UTC).
MetricTotals sumDailyWithinDays(
  List<DailyMetric> daily,
  int days, {
  DateTime? now,
}) {
  final cutoff = dayIdFor(
    (now ?? DateTime.now()).subtract(Duration(days: days - 1)),
  );
  var total = const MetricTotals();
  for (final d in daily) {
    if (d.day.compareTo(cutoff) >= 0) total = total + d.totals;
  }
  return total;
}

/// An inclusive reporting window, either "last N days" or a campaign's dates.
class ReportWindow {
  final DateTime start;
  final DateTime end;
  final String label;
  const ReportWindow(this.start, this.end, this.label);

  factory ReportWindow.lastDays(int days, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return ReportWindow(
      t.subtract(Duration(days: days - 1)),
      t,
      'Last $days days',
    );
  }

  String get startId => dayIdFor(start);
  String get endId => dayIdFor(end);

  bool contains(String dayId) =>
      dayId.compareTo(startId) >= 0 && dayId.compareTo(endId) <= 0;

  /// Every day id in the window (oldest first), capped at [maxDays].
  List<String> dayIds({int maxDays = 366}) {
    final out = <String>[];
    var d = DateTime.utc(
      start.toUtc().year,
      start.toUtc().month,
      start.toUtc().day,
    );
    final last = DateTime.utc(
      end.toUtc().year,
      end.toUtc().month,
      end.toUtc().day,
    );
    while (!d.isAfter(last) && out.length < maxDays) {
      out.add(dayIdFor(d));
      d = d.add(const Duration(days: 1));
    }
    return out;
  }
}

/// Fills a complete, zero-padded daily series for [window] from sparse
/// buckets — so charts and CSVs show quiet days as 0 instead of skipping them.
List<DailyMetric> seriesFor(List<DailyMetric> buckets, ReportWindow window) {
  final byDay = {for (final b in buckets) b.day: b.totals};
  return [
    for (final id in window.dayIds())
      DailyMetric(id, byDay[id] ?? const MetricTotals()),
  ];
}

/// Sums [buckets] that fall inside [window].
MetricTotals sumWindow(List<DailyMetric> buckets, ReportWindow window) {
  var total = const MetricTotals();
  for (final b in buckets) {
    if (window.contains(b.day)) total = total + b.totals;
  }
  return total;
}

/// Top [n] resources by the metric selected via [selector], descending.
List<ResourceMetric> topResourcesBy(
  List<ResourceMetric> list,
  int Function(MetricTotals) selector, {
  int n = 5,
}) {
  final filtered = list.where((r) => selector(r.totals) > 0).toList()
    ..sort((a, b) => selector(b.totals).compareTo(selector(a.totals)));
  return filtered.take(n).toList();
}

/// All-time rollup for one sponsor brand across its resources.
class SponsorRollup {
  final String brand;
  final int items;
  final MetricTotals totals;
  final UniqueCounts uniques;
  const SponsorRollup(this.brand, this.items, this.totals, this.uniques);
}

/// Groups sponsored resource metrics by brand, biggest reach first. Reach is
/// summed per item, so a student who saw two items of one brand counts twice
/// (labelled "item reach" in the UI).
List<SponsorRollup> rollupBySponsor(List<ResourceMetric> list) {
  final map = <String, SponsorRollup>{};
  for (final r in list.where((r) => r.sponsored)) {
    final brand = (r.brand == null || r.brand!.trim().isEmpty)
        ? r.title
        : r.brand!.trim();
    final prev = map[brand];
    map[brand] = prev == null
        ? SponsorRollup(brand, 1, r.totals, r.uniques)
        : SponsorRollup(
            brand,
            prev.items + 1,
            prev.totals + r.totals,
            prev.uniques + r.uniques,
          );
  }
  return map.values.toList()..sort(
    (a, b) => b.uniques.reach != a.uniques.reach
        ? b.uniques.reach.compareTo(a.uniques.reach)
        : b.totals.impressions.compareTo(a.totals.impressions),
  );
}

String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

String _csvCell(Object? value) {
  var s = value?.toString() ?? '';
  // Spreadsheet formula-injection guard (string cells only).
  if (value is String && s.isNotEmpty && '=+-@\t\r'.contains(s[0])) {
    s = "'$s";
  }
  final quote =
      s.contains(',') ||
      s.contains('"') ||
      s.contains('\n') ||
      s.contains('\r');
  return quote ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Sponsor-ready CSV: a summary block, reach by country and the full daily
/// series. Opens cleanly in Excel / Google Sheets.
String buildSponsorReportCsv({
  required String title,
  String? brand,
  required ReportWindow window,
  required List<DailyMetric> series,
  required UniqueCounts uniques,
}) {
  final t = series.fold(const MetricTotals(), (s, d) => s + d.totals);
  final rows = <List<Object?>>[
    ['ClassTrack sponsor report'],
    ['Item', title],
    if (brand != null && brand.isNotEmpty) ['Sponsor', brand],
    [
      'Period',
      '${prettyDayId(window.startId)} to ${prettyDayId(window.endId)}',
    ],
    [],
    ['Metric', 'Value'],
    ['Impressions', t.impressions],
    ['Detail views', t.views],
    ['Feed CTR (views / impressions)', _pct(t.feedCtr)],
    ['Link clicks', t.clicks],
    ['Click rate (clicks / views)', _pct(t.clickRate)],
    ['Applies', t.applies],
    ['Saves', t.saves],
    ['Shares', t.shares],
    ['Unique reach (all-time)', uniques.reach],
    ['Unique viewers (all-time)', uniques.viewers],
    ['Unique clickers (all-time)', uniques.clickers],
    [],
    ['Country', 'Unique reach (all-time)'],
    for (final c in uniques.topCountries) [c.key, c.value],
    [],
    ['Date', 'Impressions', 'Views', 'Clicks', 'Applies', 'Saves', 'Shares'],
    for (final d in series)
      [
        prettyDayId(d.day),
        d.totals.impressions,
        d.totals.views,
        d.totals.clicks,
        d.totals.applies,
        d.totals.saves,
        d.totals.shares,
      ],
  ];
  return rows.map((r) => r.map(_csvCell).join(',')).join('\r\n');
}
