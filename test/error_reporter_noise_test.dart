import 'package:classtrack/services/error_reporter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    ErrorReporter.resetForTest();
    ErrorReporter.debugSink = null;
  });

  test('Firestore transaction-channel cancel noise is never reported', () {
    final reports = <ErrorReport>[];
    ErrorReporter.debugSink = reports.add;
    ErrorReporter.report(
      MissingPluginException('No implementation found for method cancel on '
          'channel plugins.flutter.io/firebase_firestore/transaction/0b1ce36a-d6d1-4842-a561-6d4d9f6657bf'),
      StackTrace.empty,
      reason: 'while de-activating platform stream on channel '
          'plugins.flutter.io/firebase_firestore/transaction/0b1ce36a-d6d1-4842-a561-6d4d9f6657bf',
    );
    expect(reports, isEmpty);
  });

  test('other MissingPluginExceptions are still reported', () {
    final reports = <ErrorReport>[];
    ErrorReporter.debugSink = reports.add;
    ErrorReporter.report(MissingPluginException('foo'), StackTrace.empty,
        reason: 'x');
    expect(reports, hasLength(1));
  });

  test('ids in the reason do not split the throttle signature', () {
    ErrorReport r(String id) => ErrorReport(
          error: StateError('boom'),
          stack: StackTrace.empty,
          reason: 'channel/$id',
          fatal: false,
          kind: 'defect',
          screen: null,
        );
    expect(r('0b1ce36a-d6d1-4842-a561-6d4d9f6657bf').signature,
        r('977b148d-6e17-471a-a782-a3dda1c914aa').signature);
  });
}
