import 'package:classtrack/features/chat/presentation/widgets/ai_error_view.dart';
import 'package:classtrack/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Object error, {required bool isPro}) {
  return tester.pumpWidget(ProviderScope(
    overrides: [isProProvider.overrideWith((ref) => isPro)],
    child: MaterialApp(
      home: Scaffold(body: AiErrorView(error: error, onRetry: () {})),
    ),
  ));
}

void main() {
  final limit = FirebaseFunctionsException(
      code: 'resource-exhausted', message: 'x', details: const {'reason': 'free_limit'});

  testWidgets('free user at the limit is asked to upgrade (no Retry)', (tester) async {
    await _pump(tester, limit, isPro: false);
    expect(find.text('Upgrade to Pro'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.textContaining('10 free AI messages'), findsOneWidget);
  });

  testWidgets('Pro user hitting the daily cap is not upsold', (tester) async {
    await _pump(tester, FirebaseFunctionsException(code: 'resource-exhausted', message: 'x'),
        isPro: true);
    expect(find.text('Upgrade to Pro'), findsNothing);
    expect(find.textContaining('try again tomorrow'), findsOneWidget);
  });

  testWidgets('network errors keep Retry', (tester) async {
    await _pump(tester, Exception('socket'), isPro: false);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Upgrade to Pro'), findsNothing);
  });
}
