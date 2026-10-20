import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../services/analytics_service.dart';
import '../../../../services/error_reporter.dart';
import '../../data/auth_repository.dart';
import '../../domain/app_user.dart';
import '../../domain/onboarding_profile.dart';
import 'onboarding_draft_provider.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    db: ref.watch(firestoreProvider),
  );
});

/// Streams the current user's profile document (null when signed out).
final userProfileProvider = StreamProvider<AppUser?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(authRepositoryProvider).watchProfile(uid);
});

/// Self-heal for accounts that exist in Firebase Auth but have no
/// `users/{uid}` profile (seen in production: Google sign-in succeeded, then
/// the profile write failed because Firestore was unreachable, and nothing
/// ever created it later). Whenever a user is signed in, this makes sure the
/// profile exists, retrying with growing pauses while the app is open. The
/// next app start tries again if all of these fail.
///
/// Watch it once near the app root (see `ClassTrackApp`).
final profileSelfHealProvider = Provider<void>((ref) {
  final uid = ref.watch(
      authStateProvider.select((a) => a.valueOrNull?.uid));
  if (uid == null) return;
  var disposed = false;
  ref.onDispose(() => disposed = true);
  unawaited(runProfileSelfHeal(
    ensure: () {
      final user = ref.read(firebaseAuthProvider).currentUser;
      if (user == null || user.uid != uid) return Future.value(false);
      final seed = ref.read(onboardingDraftProvider);
      return ref.read(authRepositoryProvider).ensureProfileDoc(
            uid: uid,
            displayName: user.displayName,
            email: user.email,
            photoUrl: user.photoURL,
            seed: seed.isEmpty ? null : seed,
          );
    },
    isCancelled: () => disposed,
    onCreated: () async {
      ref.read(analyticsProvider).log('profile_self_healed');
      try {
        await ref.read(onboardingDraftProvider.notifier).clear();
      } catch (_) {/* a stale draft must never matter here */}
    },
  ));
});

/// Retry loop behind [profileSelfHealProvider] (pure, unit-tested). Calls
/// [ensure] until it succeeds, [isCancelled] turns true, or [delays] run out.
/// Each failure is reported (network ones as `transient`). Never throws.
Future<void> runProfileSelfHeal({
  required Future<bool> Function() ensure,
  required bool Function() isCancelled,
  Future<void> Function()? onCreated,
  List<Duration> delays = const [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
    Duration(seconds: 120),
  ],
}) async {
  for (var attempt = 0;; attempt++) {
    if (isCancelled()) return;
    try {
      final created = await ensure();
      if (created) await onCreated?.call();
      return;
    } catch (e, st) {
      ErrorReporter.report(e, st,
          reason: 'profile_self_heal', extra: {'attempt': attempt + 1});
      if (attempt >= delays.length) return;
      await Future<void>.delayed(delays[attempt]);
    }
  }
}

/// The ONE country used for targeting everywhere (opportunities, discounts,
/// banners, campaigns, CMS pushes): profile choice, else auto-detected.
/// Use this instead of reading `profile.country` for any targeting.
final effectiveCountryProvider = Provider<String?>((ref) {
  return ref.watch(
      userProfileProvider.select((a) => a.valueOrNull?.effectiveCountry));
});

/// Handles auth mutations with a loading/error [AsyncValue] state.
///
/// [readSeed]/[clearSeed] connect the pre-sign-up onboarding answers: they're
/// passed to the repository (which only applies them to a brand-new profile)
/// and cleared after ANY successful sign-in, so a later account on the same
/// device never inherits them.
class AuthController extends StateNotifier<AsyncValue<void>> {
  final AuthRepository _repo;
  final OnboardingProfile? Function()? _readSeed;
  final Future<void> Function()? _clearSeed;

  AuthController(
    this._repo, {
    OnboardingProfile? Function()? readSeed,
    Future<void> Function()? clearSeed,
  })  : _readSeed = readSeed,
        _clearSeed = clearSeed,
        super(const AsyncData(null));

  OnboardingProfile? get _seed {
    final s = _readSeed?.call();
    return (s == null || s.isEmpty) ? null : s;
  }

  Future<bool> _run(Future<void> Function() action,
      {bool consumesSeed = false}) async {
    state = const AsyncLoading();
    try {
      await action();
      if (consumesSeed) {
        try {
          await _clearSeed?.call();
        } catch (_) {/* a stale draft must never fail sign-in */}
      }
      state = const AsyncData(null);
      return true;
    } catch (e, st) {
      state = AsyncError(e, st);
      return false;
    }
  }

  Future<bool> signIn(String email, String password) =>
      _run(() => _repo.signInWithEmail(email, password), consumesSeed: true);

  Future<bool> signUp(String email, String password, String name) => _run(
      () => _repo.signUpWithEmail(email, password, name, seed: _seed),
      consumesSeed: true);

  Future<bool> signInWithGoogle() =>
      _run(() => _repo.signInWithGoogle(seed: _seed), consumesSeed: true);

  Future<bool> resetPassword(String email) =>
      _run(() => _repo.sendPasswordReset(email));

  Future<bool> deleteAccount() => _run(_repo.deleteAccount);
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(
    ref.watch(authRepositoryProvider),
    // ref.read (not watch): editing the draft must not rebuild the controller.
    readSeed: () => ref.read(onboardingDraftProvider),
    clearSeed: () => ref.read(onboardingDraftProvider.notifier).clear(),
  );
});
