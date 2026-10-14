import 'package:flutter_test/flutter_test.dart';

import 'package:classtrack/features/cms/domain/cms_analytics.dart';

void main() {
  sponsorTests();
  group('MetricTotals', () {
    test('fromMap parses and rates compute correctly', () {
      final t = MetricTotals.fromMap(
          {'views': 100, 'clicks': 25, 'applies': 5, 'saves': 10, 'shares': 2});
      expect(t.views, 100);
      expect(t.clickRate, closeTo(0.25, 1e-9));
      expect(t.applyRate, closeTo(0.2, 1e-9));
    });

    test('rates are zero-safe', () {
      const t = MetricTotals();
      expect(t.clickRate, 0);
      expect(t.applyRate, 0);
    });

    test('addition combines totals', () {
      const a = MetricTotals(views: 10, clicks: 2);
      const b = MetricTotals(views: 5, clicks: 3, applies: 1);
      final c = a + b;
      expect(c.views, 15);
      expect(c.clicks, 5);
      expect(c.applies, 1);
    });
  });

  group('sumDailyWithinDays', () {
    final now = DateTime.utc(2026, 8, 8, 12);
    List<DailyMetric> daily() => [
          DailyMetric(dayIdFor(now), const MetricTotals(views: 10, clicks: 4)),
          DailyMetric(dayIdFor(now.subtract(const Duration(days: 3))),
              const MetricTotals(views: 20, clicks: 5)),
          DailyMetric(dayIdFor(now.subtract(const Duration(days: 20))),
              const MetricTotals(views: 100, clicks: 50)),
        ];

    test('7-day window excludes the 20-day-old bucket', () {
      final t = sumDailyWithinDays(daily(), 7, now: now);
      expect(t.views, 30); // 10 + 20
      expect(t.clicks, 9);
    });

    test('30-day window includes all', () {
      final t = sumDailyWithinDays(daily(), 30, now: now);
      expect(t.views, 130);
    });
  });

  group('topResourcesBy', () {
    final list = [
      const ResourceMetric(
          id: '1', title: 'A', type: 'internship', totals: MetricTotals(views: 5)),
      const ResourceMetric(
          id: '2', title: 'B', type: 'discount', totals: MetricTotals(views: 50)),
      const ResourceMetric(
          id: '3', title: 'C', type: 'internship', totals: MetricTotals(views: 0)),
    ];

    test('ranks by selector descending and drops zeros', () {
      final top = topResourcesBy(list, (t) => t.views);
      expect(top.map((r) => r.id).toList(), ['2', '1']); // '3' has 0 views
    });
  });
}


void sponsorTests() {
  group('sponsor metrics', () {
    test('feed CTR and new fields parse', () {
      final t = MetricTotals.fromMap({'impressions': 200, 'views': 50});
      expect(t.impressions, 200);
      expect(t.feedCtr, closeTo(0.25, 1e-9));
      expect(const MetricTotals().feedCtr, 0);
    });

    test('UniqueCounts parses reach by country and sorts', () {
      final u = UniqueCounts.fromMap({
        'reach': 30,
        'uniqueViewers': 10,
        'uniqueClickers': 4,
        'reachByCountry': {'India': 20, 'USA': 8, 'Unknown': 2, 'Zero': 0},
      });
      expect(u.reach, 30);
      expect(u.viewers, 10);
      expect(u.clickers, 4);
      expect(u.topCountries.map((e) => e.key).toList(),
          ['India', 'USA', 'Unknown']);
      expect(u.frequency(const MetricTotals(impressions: 60)), 2);
    });

    test('ReportWindow fills zero days and sums only inside the window', () {
      final w = ReportWindow(
          DateTime.utc(2026, 10, 1, 12), DateTime.utc(2026, 10, 5, 12), 'c');
      final buckets = [
        const DailyMetric('20260930', MetricTotals(views: 99)),
        const DailyMetric('20261002', MetricTotals(views: 3, impressions: 9)),
        const DailyMetric('20261005', MetricTotals(views: 1)),
      ];
      final s = seriesFor(buckets, w);
      expect(s.map((d) => d.day).toList(),
          ['20261001', '20261002', '20261003', '20261004', '20261005']);
      expect(s[0].totals.views, 0);
      expect(sumWindow(buckets, w).views, 4);
    });

    test('rollupBySponsor groups sponsored items by brand', () {
      final list = [
        const ResourceMetric(
            id: '1',
            title: 'A',
            type: 'discount',
            brand: 'Acme',
            sponsored: true,
            totals: MetricTotals(impressions: 10),
            uniques: UniqueCounts(reach: 5, reachByCountry: {'India': 5})),
        const ResourceMetric(
            id: '2',
            title: 'B',
            type: 'discount',
            brand: 'Acme',
            sponsored: true,
            totals: MetricTotals(impressions: 5),
            uniques: UniqueCounts(reach: 3, reachByCountry: {'India': 3})),
        const ResourceMetric(
            id: '3',
            title: 'C',
            type: 'internship',
            brand: 'Other',
            totals: MetricTotals(impressions: 100)),
      ];
      final r = rollupBySponsor(list);
      expect(r.length, 1);
      expect(r.first.brand, 'Acme');
      expect(r.first.items, 2);
      expect(r.first.totals.impressions, 15);
      expect(r.first.uniques.reach, 8);
      expect(r.first.uniques.reachByCountry['India'], 8);
    });

    test('sponsor CSV has summary, countries and a row per day', () {
      final w = ReportWindow(
          DateTime.utc(2026, 10, 1), DateTime.utc(2026, 10, 2), 'c');
      final csv = buildSponsorReportCsv(
        title: '=Evil, "Title"',
        brand: 'Acme',
        window: w,
        series: seriesFor(
            [const DailyMetric('20261001', MetricTotals(impressions: 4, views: 1))],
            w),
        uniques: const UniqueCounts(reach: 3, reachByCountry: {'India': 3}),
      );
      final lines = csv.split('\r\n');
      expect(lines, contains('Item,"\'=Evil, ""Title"""'));
      expect(lines, contains('Impressions,4'));
      expect(lines, contains('Feed CTR (views / impressions),25.0%'));
      expect(lines, contains('India,3'));
      expect(lines, contains('2026-10-01,4,1,0,0,0,0'));
      expect(lines.last, '2026-10-02,0,0,0,0,0,0');
    });
  });
}
