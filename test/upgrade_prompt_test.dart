import 'package:classtrack/core/theme/app_theme.dart';
import 'package:classtrack/features/subscription/domain/upgrade_reason.dart';
import 'package:classtrack/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:classtrack/features/subscription/presentation/widgets/upgrade_prompt.dart';
import 'package:classtrack/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Analytics extends AnalyticsService {
  final events = <String>[];
  @override
  Future<void> log(String name, [Map<String, Object>? params]) async =>
      events.add('$name:${params?['reason']}');
}

Future<_Analytics> _pump(WidgetTester tester,
    {required bool isPro, required UpgradeReason reason, int? used, List<bool>? results}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final analytics = _Analytics();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      isProProvider.overrideWith((ref) => isPro),
      analyticsProvider.overrideWithValue(analytics),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true), child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                // NB: not `results?.add(await …)` — that short-circuits the
                // call itself when results is null.
                final r = await showUpgradePrompt(context, reason, used: used);
                results?.add(r);
              },
              child: const Text('trigger'),
            ),
          ),
        ),
      ),
    ),
  ));
  return analytics;
}

void main() {
  test('every reason has complete, non-empty copy', () {
    for (final r in UpgradeReason.values) {
      final c = r.copy;
      expect(c.title, isNotEmpty, reason: r.name);
      expect(c.message, isNotEmpty, reason: r.name);
      expect(c.paywallHeadline, isNotEmpty, reason: r.name);
      expect(c.highlight, isNotEmpty, reason: r.name);
    }
    // Limits carry a unit; only chat resets monthly (scans/plans are lifetime).
    expect(UpgradeReason.aiChat.copy.resets, 'month');
    expect(UpgradeReason.timetableScans.copy.resets, isNull);
    expect(UpgradeReason.learningPlans.copy.limit, 2);
  });

  test('resetLabel names the first of next month (and rolls the year)', () {
    final chat = UpgradeReason.aiChat.copy;
    expect(resetLabel(chat, DateTime(2026, 10, 2)), 'Resets on 1 Nov');
    expect(resetLabel(chat, DateTime(2026, 12, 31)), 'Resets on 1 Jan');
    expect(resetLabel(UpgradeReason.timetableScans.copy, DateTime(2026, 10, 2)), isNull);
  });

  testWidgets('limit prompt shows the usage meter and Pro answer', (tester) async {
    final results = <bool>[];
    final a = await _pump(tester, isPro: false, reason: UpgradeReason.aiChat, results: results);
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('You’ve used your free AI messages'), findsOneWidget);
    expect(find.text('10 / 10 messages used'), findsOneWidget);
    expect(find.textContaining('Resets on 1 '), findsOneWidget);
    expect(find.textContaining('Unlimited AI assistant'), findsOneWidget);
    expect(find.text('See Pro plans'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(results, [false]);
    expect(a.events, ['upgrade_prompt_shown:aiChat', 'upgrade_prompt_dismissed:aiChat']);
  });

  testWidgets('"See Pro plans" opens the pricing page for that reason', (tester) async {
    final a = await _pump(tester, isPro: false, reason: UpgradeReason.timetableScans);
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2 scans used'), findsOneWidget);
    expect(find.textContaining('Resets on'), findsNothing); // lifetime allowance

    await tester.tap(find.text('See Pro plans'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Import every timetable in seconds'), findsOneWidget);
    expect(find.text('WHY PRO?'), findsOneWidget);
    expect(a.events, containsAll(['upgrade_prompt_accepted:timetableScans', 'paywall_viewed:timetableScans']));
  });

  testWidgets('feature gate (no limit) has no meter; partial usage honoured', (tester) async {
    await _pump(tester, isPro: false, reason: UpgradeReason.export);
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    expect(find.text('Export is a Pro feature'), findsOneWidget);
    expect(find.textContaining('used'), findsNothing);
  });

  testWidgets('Pro users are never prompted', (tester) async {
    final results = <bool>[];
    final a = await _pump(tester, isPro: true, reason: UpgradeReason.aiChat, results: results);
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();
    expect(find.text('See Pro plans'), findsNothing);
    expect(results, [true]);
    expect(a.events, isEmpty);
  });
}
