import 'package:classtrack/features/chat/domain/ai_errors.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseFunctionsException _err(String code, [Object? details]) =>
    FirebaseFunctionsException(code: code, message: 'x', details: details);

void main() {
  group('classifyChatError', () {
    test('server-tagged free limit → upgrade prompt (even with fresh local count)', () {
      final e = _err('resource-exhausted', {'reason': 'free_limit', 'action': 'chat'});
      expect(classifyChatError(e, isPro: false), ChatErrorKind.freeLimit);
    });

    test('untagged resource-exhausted: free → upgrade, Pro → daily cap', () {
      final e = _err('resource-exhausted');
      expect(classifyChatError(e, isPro: false), ChatErrorKind.freeLimit);
      expect(classifyChatError(e, isPro: true), ChatErrorKind.proDailyCap);
    });

    test('unverified email is its own case', () {
      final e = _err('failed-precondition', {'reason': 'email_unverified'});
      expect(classifyChatError(e, isPro: false), ChatErrorKind.emailUnverified);
      expect(aiErrorReason(e), 'email_unverified');
    });

    test('anything else is a generic failure', () {
      expect(classifyChatError(_err('internal'), isPro: false), ChatErrorKind.other);
      expect(classifyChatError(Exception('socket'), isPro: false), ChatErrorKind.other);
      expect(aiErrorReason(Exception('x')), isNull);
    });

    test('free-limit copy names the limit and Pro', () {
      expect(freeChatLimitMessage, contains('10 free AI messages'));
      expect(freeChatLimitMessage, contains('Upgrade to ClassTrack Pro'));
    });
  });
}
