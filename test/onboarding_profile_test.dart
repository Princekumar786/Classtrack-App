import 'package:classtrack/core/constants/app_constants.dart';
import 'package:classtrack/core/providers/app_settings_provider.dart';
import 'package:classtrack/features/auth/data/auth_repository.dart';
import 'package:classtrack/features/auth/domain/onboarding_profile.dart';
import 'package:classtrack/features/auth/domain/profile_avatars.dart';
import 'package:classtrack/features/auth/presentation/providers/auth_providers.dart';
import 'package:classtrack/features/auth/presentation/providers/onboarding_draft_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the seed passed to the repository without touching Firebase.
class _SeedSpyRepo implements AuthRepository {
  OnboardingProfile? lastSeed;
  bool fail = false;

  @override
  Future<void> signUpWithEmail(String email, String password, String name,
      {OnboardingProfile? seed}) async {
    if (fail) throw Exception('boom');
    lastSeed = seed;
  }

  @override
  Future<void> signInWithGoogle({OnboardingProfile? seed}) async {
    lastSeed = seed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('AttendanceMath.maxSkippable', () {
    test('75% of 40 lets you miss exactly 10', () {
      expect(AttendanceMath.maxSkippable(40, 75), 10);
    });
    test('rounds the required count UP (never overstates skips)', () {
      // 85% of 40 = 34 attended → 6 skippable.
      expect(AttendanceMath.maxSkippable(40, 85), 6);
      // 75% of 30 = 22.5 → must attend 23 → 7 skippable (not 7.5/8).
      expect(AttendanceMath.maxSkippable(30, 75), 7);
    });
    test('edge cases', () {
      expect(AttendanceMath.maxSkippable(0, 75), 0);
      expect(AttendanceMath.maxSkippable(40, 100), 0);
      expect(AttendanceMath.maxSkippable(40, 0), 40);
    });
  });

  group('OnboardingProfile', () {
    test('default target matches the app default', () {
      expect(OnboardingProfile.defaultTarget,
          AppConstants.defaultTargetAttendance.round());
      expect(const OnboardingProfile().isEmpty, isTrue);
    });

    test('copyWith sanitizes names and clamps the target', () {
      final p = const OnboardingProfile()
          .copyWith(name: '  <b>Priya</b>   Sharma ', targetAttendance: 120);
      expect(p.name, 'Priya Sharma');
      expect(p.firstName, 'Priya');
      expect(p.targetAttendance, OnboardingProfile.maxTarget);
      expect(p.isEmpty, isFalse);
    });

    test('JSON round-trip', () {
      final p = OnboardingProfile(
        name: 'Priya',
        focusAreas: const {FocusArea.attendance, FocusArea.budget},
        targetAttendance: 80,
        avatarCharacter: ProfileAvatars.free.first,
      );
      final back = OnboardingProfile.decode(p.encode());
      expect(back.name, 'Priya');
      expect(back.focusAreas, {FocusArea.attendance, FocusArea.budget});
      expect(back.targetAttendance, 80);
      expect(back.avatarCharacter, ProfileAvatars.free.first);
    });

    test('decode tolerates corrupt / hostile drafts', () {
      expect(OnboardingProfile.decode('not json').isEmpty, isTrue);
      expect(OnboardingProfile.decode(null).isEmpty, isTrue);
      final p = OnboardingProfile.decode(
          '{"focusAreas":["attendance","nope"],"targetAttendance":5,'
          '"avatarCharacter":"${ProfileAvatars.pro.first}"}');
      expect(p.focusAreas, {FocusArea.attendance});
      expect(p.targetAttendance, OnboardingProfile.minTarget);
      // Pro-only avatars are never seeded into a new (free) account.
      expect(p.avatarCharacter, isNull);
    });
  });

  group('AuthRepository.buildNewProfile', () {
    test('without a seed keeps the previous defaults', () {
      final u = AuthRepository.buildNewProfile(uid: 'u1', displayName: 'A');
      expect(u.displayName, 'A');
      expect(u.targetAttendancePercent, AppConstants.defaultTargetAttendance);
      expect(u.avatarCharacter, ProfileAvatars.defaultForUid('u1'));
      expect(u.focusAreas, isEmpty);
    });

    test('applies onboarding answers; auth name wins over draft name', () {
      final seed = OnboardingProfile(
        name: 'Draft Name',
        focusAreas: const {FocusArea.deadlines},
        targetAttendance: 85,
        avatarCharacter: ProfileAvatars.free[3],
      );
      final u = AuthRepository.buildNewProfile(
          uid: 'u1', displayName: 'Google Name', seed: seed);
      expect(u.displayName, 'Google Name');
      expect(u.targetAttendancePercent, 85);
      expect(u.avatarCharacter, ProfileAvatars.free[3]);
      expect(u.focusAreas, ['deadlines']);
      expect(u.toMap()['focusAreas'], ['deadlines']);
    });

    test('falls back to the draft name when auth has none', () {
      final u = AuthRepository.buildNewProfile(
          uid: 'u1', seed: const OnboardingProfile(name: 'Priya'));
      expect(u.displayName, 'Priya');
    });
  });

  group('Draft → sign-up wiring', () {
    late ProviderContainer container;
    late _SeedSpyRepo repo;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      repo = _SeedSpyRepo();
      container = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(repo),
      ]);
    });
    tearDown(() => container.dispose());

    test('draft persists to prefs and survives a restart', () async {
      final ctrl = container.read(onboardingDraftProvider.notifier);
      await ctrl.update((p) => p.copyWith(name: 'Priya'));
      ctrl.toggleFocus(FocusArea.grades);
      // Writes are debounced (no disk write per slider tick); the screen
      // flushes before leaving onboarding.
      await ctrl.flush();
      final prefs = container.read(sharedPrefsProvider);
      final reloaded = OnboardingDraftController(prefs);
      expect(reloaded.state.name, 'Priya');
      expect(reloaded.state.focusAreas, {FocusArea.grades});
    });

    test('sign-up passes the draft as seed, then clears it', () async {
      await container
          .read(onboardingDraftProvider.notifier)
          .update((p) => p.copyWith(name: 'Priya', targetAttendance: 80));

      final ok = await container
          .read(authControllerProvider.notifier)
          .signUp('a@b.co', 'abc12345', 'Priya');

      expect(ok, isTrue);
      expect(repo.lastSeed?.targetAttendance, 80);
      expect(container.read(onboardingDraftProvider).isEmpty, isTrue);
      expect(
          container
              .read(sharedPrefsProvider)
              .containsKey(AppConstants.prefsOnboardingDraft),
          isFalse);
    });

    test('a pending draft write is debounced, then flushed', () async {
      final ctrl = container.read(onboardingDraftProvider.notifier);
      final prefs = container.read(sharedPrefsProvider);
      for (var t = 50; t <= 95; t += 5) {
        await ctrl.update((p) => p.copyWith(targetAttendance: t)); // slider drag
      }
      // Nothing written yet — no storage I/O per drag tick.
      expect(prefs.containsKey(AppConstants.prefsOnboardingDraft), isFalse);
      expect(container.read(onboardingDraftProvider).targetAttendance, 95);
      await ctrl.flush();
      expect(OnboardingProfile.decode(prefs.getString(AppConstants.prefsOnboardingDraft))
          .targetAttendance, 95);
    });

    test('an empty draft is not sent as a seed', () async {
      await container.read(authControllerProvider.notifier).signInWithGoogle();
      expect(repo.lastSeed, isNull);
    });

    test('a failed sign-up keeps the draft for the retry', () async {
      repo.fail = true;
      await container
          .read(onboardingDraftProvider.notifier)
          .update((p) => p.copyWith(name: 'Priya'));
      final ok = await container
          .read(authControllerProvider.notifier)
          .signUp('a@b.co', 'abc12345', 'Priya');
      expect(ok, isFalse);
      expect(container.read(onboardingDraftProvider).name, 'Priya');
    });
  });
}
