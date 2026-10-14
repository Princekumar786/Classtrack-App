// The redesigned pricing page, driven by fake store plans that mirror the
// reference design (₹399 monthly, ₹999 quarterly, ₹1,899 annual).
import 'package:classtrack/core/theme/app_theme.dart';
import 'package:classtrack/features/subscription/data/subscription_service.dart';
import 'package:classtrack/features/subscription/domain/upgrade_reason.dart';
import 'package:classtrack/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:classtrack/features/subscription/presentation/screens/paywall_screen.dart';
import 'package:classtrack/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class _NoopAnalytics extends AnalyticsService {
  @override
  Future<void> log(String name, [Map<String, Object>? params]) async {}
}

class _FakeStore extends SubscriptionService {
  _FakeStore(this.packages);
  final List<Package> packages;
  Package? bought;
  int restores = 0;

  @override
  Future<List<Package>> fetchPackages() async => packages;

  @override
  Future<bool> purchase(Package package) async {
    bought = package;
    return false; // behave like a cancelled sheet: stay on the page
  }

  @override
  Future<RestoreResult> restore() async {
    restores++;
    return const RestoreResult(
        RestoreStatus.nothingFound, 'No previous purchases found for this account.');
  }
}

Package _pkg(String id, PackageType type, double price, String priceString) =>
    Package(
      id,
      type,
      StoreProduct('classtrack_$id', '', 'ClassTrack Pro', price, priceString, 'INR'),
      const PresentedOfferingContext('default', null, null),
    );

final _plans = [
  _pkg(r'$rc_annual', PackageType.annual, 1899, '₹1,899.00'),
  _pkg(r'$rc_monthly', PackageType.monthly, 399, '₹399.00'),
  _pkg(r'$rc_three_month', PackageType.threeMonth, 999, '₹999.00'),
];

Future<_FakeStore> _pump(WidgetTester tester,
    {UpgradeReason reason = UpgradeReason.general}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final store = _FakeStore(_plans);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      subscriptionServiceProvider.overrideWithValue(store),
      analyticsProvider.overrideWithValue(_NoopAnalytics()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: PaywallScreen(reason: reason),
    ),
  ));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('plan cards in order with compare-at prices and MOST POPULAR',
      (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);

    expect(find.text('THE BEST CLASSTRACK EXPERIENCE'), findsOneWidget);
    final monthly = tester.getTopLeft(find.text('Pro Monthly')).dy;
    final quarterly = tester.getTopLeft(find.text('Pro Quarterly')).dy;
    final annual = tester.getTopLeft(find.text('Pro Annual')).dy;
    expect(monthly < quarterly && quarterly < annual, isTrue);

    // Struck-out "what it would cost monthly": 399 x 3 and 399 x 12.
    expect(find.text('₹1,197'), findsOneWidget);
    expect(find.text('₹4,788'), findsOneWidget);
    expect(find.text('₹999.00'), findsOneWidget);
    expect(find.text('MOST POPULAR'), findsOneWidget);
    expect(find.text('Just ₹158/month'), findsOneWidget);

    // Annual is pre-selected; tapping another plan changes the CTA.
    expect(find.text('PURCHASE PRO ANNUAL'), findsOneWidget);
    await tester.tap(find.text('Pro Monthly'));
    await tester.pump();
    expect(find.text('PURCHASE PRO MONTHLY'), findsOneWidget);

    // Google Play billing terms are shown under the button.
    expect(find.textContaining('charged to your Google Play account'),
        findsOneWidget);
    expect(find.text('Terms of Use'), findsOneWidget);
  });

  testWidgets('WHY PRO? lists every feature, incl. semester wrap-up',
      (tester) async {
    await _pump(tester);
    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('WHY PRO?'), 300, scrollable: scroll);
    for (final row in planComparison) {
      await tester.scrollUntilVisible(find.text(row.feature), 200, scrollable: scroll);
      expect(find.text(row.feature), findsOneWidget, reason: row.feature);
    }
    expect(find.text('Semester wrap-up & CGPA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buy uses the selected plan; restore reports nothing found',
      (tester) async {
    final store = await _pump(tester);
    await tester.tap(find.text('Pro Quarterly'));
    await tester.pump();
    await tester.tap(find.text('PURCHASE PRO QUARTERLY'));
    await tester.pumpAndSettle();
    expect(store.bought?.packageType, PackageType.threeMonth);

    final restore = find.text('RESTORE PURCHASES');
    await tester.scrollUntilVisible(restore, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(store.restores, 1);
    expect(find.text('No previous purchases found for this account.'),
        findsOneWidget);
  });

  testWidgets('opened from a gate: shows that headline', (tester) async {
    await _pump(tester, reason: UpgradeReason.semesters);
    expect(find.text('Every semester, saved and counted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a small phone with large text', (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        subscriptionServiceProvider.overrideWithValue(_FakeStore(_plans)),
        analyticsProvider.overrideWithValue(_NoopAnalytics()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!),
        home: const PaywallScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
