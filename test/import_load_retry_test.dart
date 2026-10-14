import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classtrack/services/gemini_service.dart';

/// Import under heavy load: the app retries ONLY "server busy" errors, a
/// bounded number of times, with random waits so phones don't retry together.
void main() {
  FirebaseFunctionsException err(String code, [Map<String, dynamic>? d]) =>
      FirebaseFunctionsException(code: code, message: code, details: d);

  test('busy errors are retried, then succeed', () async {
    var calls = 0;
    final waits = <Duration>[];
    final result = await GeminiService.callWithRetry(() async {
      calls++;
      if (calls < 3) throw err('unavailable', {'reason': 'busy'});
      return 'ok';
    }, sleep: (d) async => waits.add(d));
    expect(result, 'ok');
    expect(calls, 3);
    expect(waits, hasLength(2));
    expect(waits[0].inMilliseconds, inInclusiveRange(3000, 8000));
    expect(waits[1].inMilliseconds, inInclusiveRange(6000, 16000));
  });

  test('gives up after the retry limit', () async {
    var calls = 0;
    await expectLater(
      GeminiService.callWithRetry(() async {
        calls++;
        throw err('unavailable');
      }, sleep: (_) async {}),
      throwsA(isA<FirebaseFunctionsException>()),
    );
    expect(calls, GeminiService.maxBusyRetries + 1);
  });

  test('quota, bad-input and auth errors are never retried', () async {
    for (final e in [
      err('resource-exhausted', {'reason': 'free_limit'}),
      err('resource-exhausted', {'reason': 'rate_limit'}),
      err('failed-precondition', {'reason': 'unreadable'}),
      err('unauthenticated'),
      err('deadline-exceeded'),
    ]) {
      var calls = 0;
      await expectLater(
        GeminiService.callWithRetry(() async {
          calls++;
          throw e;
        }, sleep: (_) async {}),
        throwsA(isA<FirebaseFunctionsException>()),
      );
      expect(calls, 1, reason: e.code);
    }
  });

  test('Cloud Run overload (resource-exhausted, no reason) is retried', () {
    expect(GeminiService.isRetryableBusyError(err('resource-exhausted')), isTrue);
  });
}
