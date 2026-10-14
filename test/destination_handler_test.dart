import 'package:classtrack/core/utils/destination_handler.dart';
import 'package:classtrack/features/cms/domain/marketing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPaywallDestination', () {
    test('matches pricing-page destinations', () {
      for (final d in ['app://paywall', 'paywall', 'PRO', ' pricing ', 'upgrade']) {
        expect(isPaywallDestination(d), isTrue, reason: d);
      }
    });

    test('ignores other destinations', () {
      for (final d in [null, '', 'tab:explore', 'resource:abc', 'https://x.com']) {
        expect(isPaywallDestination(d), isFalse, reason: '$d');
      }
    });
  });

  group('filterBannersForPro', () {
    const everyone = CmsBanner(id: 'all', title: 'Hackathon');
    const freeOnly = CmsBanner(id: 'free', title: 'Ad', showToPro: false);
    const upgrade =
        CmsBanner(id: 'up', title: 'Go Pro', destination: 'app://paywall');
    const banners = [everyone, freeOnly, upgrade];

    test('free users see every banner', () {
      expect(filterBannersForPro(banners, hideProOnly: false), banners);
    });

    test('Pro users skip "free users only" and pricing banners', () {
      expect(
        filterBannersForPro(banners, hideProOnly: true).map((b) => b.id),
        ['all'],
      );
    });
  });
}
