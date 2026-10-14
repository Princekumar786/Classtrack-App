import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classtrack/services/error_reporter.dart';

/// Every error must reach the dashboards with the right tags: real bugs as
/// `defect` (fatal only when asked), network/offline noise as `transient` and
/// never fatal.
void main() {
  final reports = <ErrorReport>[];
  setUp(() {
    reports.clear();
    ErrorReporter.resetForTest();
    ErrorReporter.debugSink = reports.add;
  });
  tearDown(() => ErrorReporter.debugSink = null);

  test('a code defect is reported as fatal defect when asked', () {
    ErrorReporter.report(StateError('bad state'), StackTrace.current,
        reason: 'uncaught_async', fatal: true);
    expect(reports.single.fatal, isTrue);
    expect(reports.single.kind, 'defect');
    expect(reports.single.reason, 'uncaught_async');
  });

  test('transient errors are still reported but never fatal', () {
    for (final e in <Object>[
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      TimeoutException('slow'),
      MissingPluginException('no impl'),
    ]) {
      ErrorReporter.report(e, null, fatal: true);
    }
    expect(reports, hasLength(3));
    expect(reports.every((r) => !r.fatal && r.kind == 'transient'), isTrue);
  });

  test('permission-denied is a defect (rules/code bug), not transient', () {
    expect(
        isTransientError(
            FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')),
        isFalse);
  });

  test('reports carry the last screen as a breadcrumb', () {
    ErrorReporter.setScreen('Attendance');
    ErrorReporter.report(Exception('x'), null);
    expect(reports.single.screen, 'Attendance');
  });
}
