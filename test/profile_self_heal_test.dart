// Regression tests for accounts that exist in Firebase Auth but have no
// users/{uid} profile (Google sign-in succeeded, the profile write failed
// because Firestore was unreachable, and nothing created it later).

import 'package:classtrack/features/auth/data/auth_repository.dart';
import 'package:classtrack/features/auth/presentation/providers/auth_providers.dart';
import 'package:classtrack/services/error_reporter.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

class _FakeAuth implements FirebaseAuth {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGoogle implements GoogleSignIn {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

FirebaseException _offline() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');

void main() {
  setUp(() {
    ErrorReporter.resetForTest();
    ErrorReporter.debugSink = null;
  });

  group('ensureProfileDoc', () {
    late FakeFirebaseFirestore db;
    late AuthRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      repo = AuthRepository(auth: _FakeAuth(), db: db, googleSignIn: _FakeGoogle());
    });

    test('creates a missing profile', () async {
      final created = await repo.ensureProfileDoc(
          uid: 'u1', displayName: 'Asha', email: 'a@example.com');
      expect(created, isTrue);
      final snap = await db.collection('users').doc('u1').get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['displayName'], 'Asha');
      expect(snap.data()!['avatarCharacter'], isNotNull);
    });

    test('never overwrites an existing profile', () async {
      await db.collection('users').doc('u1').set({'displayName': 'Real', 'currency': '\$'});
      final created = await repo.ensureProfileDoc(uid: 'u1', displayName: 'Other');
      expect(created, isFalse);
      final data = (await db.collection('users').doc('u1').get()).data()!;
      expect(data['displayName'], 'Real');
      expect(data['currency'], '\$');
    });
  });

  group('withProfileRetry', () {
    const fast = [Duration.zero, Duration.zero];

    test('retries network errors, then succeeds', () async {
      var calls = 0;
      final r = await AuthRepository.withProfileRetry(() async {
        calls++;
        if (calls < 3) throw _offline();
        return 'ok';
      }, delays: fast);
      expect(r, 'ok');
      expect(calls, 3);
    });

    test('rethrows after the last retry', () async {
      var calls = 0;
      await expectLater(
        AuthRepository.withProfileRetry(() async {
          calls++;
          throw _offline();
        }, delays: fast),
        throwsA(isA<FirebaseException>()),
      );
      expect(calls, 3);
    });

    test('does not retry non-network errors', () async {
      var calls = 0;
      await expectLater(
        AuthRepository.withProfileRetry(() async {
          calls++;
          throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
        }, delays: fast),
        throwsA(isA<FirebaseException>()),
      );
      expect(calls, 1);
    });
  });

  group('runProfileSelfHeal', () {
    test('keeps trying until the profile is created, then calls onCreated', () async {
      final reports = <ErrorReport>[];
      ErrorReporter.debugSink = reports.add;
      var calls = 0;
      var createdCalls = 0;
      await runProfileSelfHeal(
        ensure: () async {
          calls++;
          if (calls < 3) throw _offline();
          return true;
        },
        isCancelled: () => false,
        onCreated: () async => createdCalls++,
        delays: const [Duration.zero, Duration.zero, Duration.zero],
      );
      expect(calls, 3);
      expect(createdCalls, 1);
      expect(reports, hasLength(2));
      expect(reports.first.reason, 'profile_self_heal');
      expect(reports.first.kind, 'transient');
    });

    test('does not call onCreated when the profile already existed', () async {
      var createdCalls = 0;
      await runProfileSelfHeal(
        ensure: () async => false,
        isCancelled: () => false,
        onCreated: () async => createdCalls++,
      );
      expect(createdCalls, 0);
    });

    test('stops when cancelled (e.g. signed out) and never throws', () async {
      var calls = 0;
      var cancelled = false;
      await runProfileSelfHeal(
        ensure: () async {
          calls++;
          cancelled = true;
          throw _offline();
        },
        isCancelled: () => cancelled,
        delays: const [Duration.zero, Duration.zero],
      );
      expect(calls, 1);
    });

    test('gives up quietly after the last delay', () async {
      var calls = 0;
      await runProfileSelfHeal(
        ensure: () async {
          calls++;
          throw _offline();
        },
        isCancelled: () => false,
        delays: const [Duration.zero],
      );
      expect(calls, 2);
    });
  });
}
