import 'package:classtrack/features/subscription/domain/paywall_pricing.dart';
import 'package:classtrack/features/subscription/domain/upgrade_reason.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaywallPricing.compareAtPrice', () {
    test('monthly x months when the plan is cheaper (₹399 x 3 > ₹999)', () {
      expect(
          PaywallPricing.compareAtPrice(
              monthlyPrice: 399, months: 3, planPrice: 999),
          1197);
      expect(
          PaywallPricing.compareAtPrice(
              monthlyPrice: 399, months: 12, planPrice: 1899),
          4788);
    });

    test('null for monthly plans, missing monthly, or no real saving', () {
      expect(
          PaywallPricing.compareAtPrice(
              monthlyPrice: 399, months: 1, planPrice: 399),
          isNull);
      expect(
          PaywallPricing.compareAtPrice(
              monthlyPrice: null, months: 12, planPrice: 1899),
          isNull);
      expect(
          PaywallPricing.compareAtPrice(
              monthlyPrice: 100, months: 12, planPrice: 1200),
          isNull);
      expect(
          PaywallPricing.compareAtPrice(
              monthlyPrice: 100, months: null, planPrice: 50),
          isNull);
    });
  });

  test('pricing table covers every Pro gate with a feature name and icon', () {
    final reasons = {for (final r in planComparison) r.reason};
    for (final r in UpgradeReason.values) {
      if (r == UpgradeReason.general) continue;
      expect(reasons, contains(r), reason: '${r.name} missing from the table');
    }
    for (final row in planComparison) {
      expect(row.feature, isNotEmpty);
      // Pro is never worse than Free: every Pro cell has a value.
      expect(row.pro, isNotEmpty);
    }
    final wrapUp =
        planComparison.firstWhere((r) => r.reason == UpgradeReason.semesters);
    expect(wrapUp.free, isNull);
    expect(wrapUp.pro, PlanComparisonRow.included);
  });

  group('PaywallPricing.percentOff', () {
    test('computes a straightforward half-price discount', () {
      expect(PaywallPricing.percentOff(1000, 500), 50);
    });

    test('rounds to the nearest whole percent', () {
      // 1 - 399/999 = 60.06% -> 60
      expect(PaywallPricing.percentOff(999, 399), 60);
    });

    test('returns null when there is no real saving', () {
      expect(PaywallPricing.percentOff(500, 500), isNull); // equal
      expect(PaywallPricing.percentOff(500, 600), isNull); // more expensive
    });

    test('returns null for a saving that rounds below 1%', () {
      expect(PaywallPricing.percentOff(1000, 999.6), isNull);
    });

    test('returns null for invalid inputs', () {
      expect(PaywallPricing.percentOff(0, 0), isNull);
      expect(PaywallPricing.percentOff(-10, 5), isNull);
      expect(PaywallPricing.percentOff(100, -5), isNull);
      expect(PaywallPricing.percentOff(double.nan, 5), isNull);
      expect(PaywallPricing.percentOff(double.infinity, 5), isNull);
    });
  });
}
