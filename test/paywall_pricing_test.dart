import 'package:classtrack/features/subscription/domain/paywall_pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
