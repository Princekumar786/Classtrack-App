import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
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
