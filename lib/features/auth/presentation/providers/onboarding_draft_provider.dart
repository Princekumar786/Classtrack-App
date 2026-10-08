import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_settings_provider.dart';
import '../../domain/onboarding_profile.dart';

/// Holds the personalised-onboarding answers until the student signs up.
///
/// Onboarding runs before sign-in, so there's no uid to scope by: the draft is
/// device-global and written on every change (so killing the app mid-flow
/// doesn't lose answers). It is cleared after the first successful sign-in so
/// a second account on the same device never inherits it.
class OnboardingDraftController extends StateNotifier<OnboardingProfile> {
  OnboardingDraftController(this._prefs)
      : super(OnboardingProfile.decode(
            _prefs.getString(AppConstants.prefsOnboardingDraft)));

  final SharedPreferences _prefs;
  Timer? _saveTimer;

  /// Updates the draft immediately (UI reacts at once) and persists it shortly
  /// after. Debounced so dragging the target slider or tapping cards doesn't
  /// hit storage on every frame (a source of onboarding jank); [flush] forces
  /// the write (called before leaving onboarding).
  Future<void> update(OnboardingProfile Function(OnboardingProfile) change) {
    state = change(state);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), flush);
    return Future.value();
  }

  /// Writes any pending change now.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _prefs.setString(AppConstants.prefsOnboardingDraft, state.encode());
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      // Best-effort final write; the in-memory prefs cache updates synchronously.
      _prefs.setString(AppConstants.prefsOnboardingDraft, state.encode());
    }
    super.dispose();
  }

  void toggleFocus(FocusArea area) => update((p) {
        final next = {...p.focusAreas};
        next.contains(area) ? next.remove(area) : next.add(area);
        return p.copyWith(focusAreas: next);
      });

  Future<void> clear() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    state = const OnboardingProfile();
    await _prefs.remove(AppConstants.prefsOnboardingDraft);
  }
}

final onboardingDraftProvider =
    StateNotifierProvider<OnboardingDraftController, OnboardingProfile>(
  (ref) => OnboardingDraftController(ref.watch(sharedPrefsProvider)),
);
