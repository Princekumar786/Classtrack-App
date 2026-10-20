import 'dart:convert';

import '../../../core/utils/validators.dart';
import 'profile_avatars.dart';

/// What a student wants ClassTrack to help with. Picked during onboarding and
/// used to tailor the "Your plan" summary (and stored on the profile as
/// `focusAreas` so the rest of the app can personalise later).
enum FocusArea {
  /// Legacy: no longer offered in onboarding, kept so old drafts/profiles parse.
  attendance,
  classes,
  deadlines,
  grades,
  budget,
  habits,
  exams;

  /// The cards shown in onboarding, in display order.
  static const onboardingChoices = [classes, deadlines, exams, grades, budget, habits];

  /// Parses a stored id, ignoring unknown values (forward-compatible).
  static FocusArea? tryParse(String? id) {
    for (final f in FocusArea.values) {
      if (f.name == id) return f;
    }
    return null;
  }
}

/// When the student does their best work. Picked in onboarding, shown on the
/// student card / plan preview and stored on the profile as `studyRhythm`.
enum StudyRhythm {
  earlyBird,
  daytime,
  nightOwl;

  String get label => switch (this) {
        earlyBird => 'Early bird',
        daytime => 'Daytime doer',
        nightOwl => 'Night owl',
      };

  /// Human-readable peak-focus window.
  String get window => switch (this) {
        earlyBird => '5 – 10 AM',
        daytime => '10 AM – 5 PM',
        nightOwl => '8 PM – 1 AM',
      };

  /// Peak window as [start, end) hours on a 0–24 clock (end may pass 24).
  (int, int) get hours => switch (this) {
        earlyBird => (5, 10),
        daytime => (10, 17),
        nightOwl => (20, 25),
      };

  static StudyRhythm? tryParse(String? id) {
    for (final r in StudyRhythm.values) {
      if (r.name == id) return r;
    }
    return null;
  }
}

/// Answers collected by the pre-sign-up onboarding flow.
///
/// Everything is optional: a student can skip any step and the app keeps its
/// existing defaults. Immutable; persisted as JSON by the draft provider.
class OnboardingProfile {
  /// Lowest / highest attendance target offered by the picker.
  static const int minTarget = 50;
  static const int maxTarget = 95;

  /// Sanitized first name (or empty when skipped).
  final String name;

  final Set<FocusArea> focusAreas;

  /// Attendance target in whole percent. No longer asked in onboarding (it
  /// stays at the app default and is changed in Settings), kept for seeding.
  final int targetAttendance;

  /// Chosen character file name (see [ProfileAvatars]); null = not chosen.
  final String? avatarCharacter;

  /// When the student studies best; null = skipped.
  final StudyRhythm? studyRhythm;

  const OnboardingProfile({
    this.name = '',
    this.focusAreas = const {},
    this.targetAttendance = _defaultTarget,
    this.avatarCharacter,
    this.studyRhythm,
  });

  /// Mirrors `AppConstants.defaultTargetAttendance` (kept as an int const so it
  /// can be a constructor default). Asserted equal in tests.
  static const int _defaultTarget = 75;
  static const int defaultTarget = _defaultTarget;

  bool get hasName => name.isNotEmpty;

  /// First word of [name], used in friendly copy ("Nice to meet you, Priya").
  String get firstName => hasName ? name.split(' ').first : '';

  /// True when the student answered anything worth seeding into a profile.
  bool get isEmpty =>
      !hasName &&
      focusAreas.isEmpty &&
      targetAttendance == _defaultTarget &&
      avatarCharacter == null &&
      studyRhythm == null;

  OnboardingProfile copyWith({
    String? name,
    Set<FocusArea>? focusAreas,
    int? targetAttendance,
    String? avatarCharacter,
    StudyRhythm? studyRhythm,
  }) {
    return OnboardingProfile(
      name: name == null ? this.name : Validators.sanitizeName(name),
      focusAreas: focusAreas ?? this.focusAreas,
      targetAttendance: targetAttendance == null
          ? this.targetAttendance
          : targetAttendance.clamp(minTarget, maxTarget),
      avatarCharacter: avatarCharacter ?? this.avatarCharacter,
      studyRhythm: studyRhythm ?? this.studyRhythm,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'focusAreas': focusAreas.map((f) => f.name).toList(),
        'targetAttendance': targetAttendance,
        if (avatarCharacter != null) 'avatarCharacter': avatarCharacter,
        if (studyRhythm != null) 'studyRhythm': studyRhythm!.name,
      };

  /// Defensive parse: anything malformed falls back to defaults so a corrupt
  /// draft can never block the onboarding screen.
  factory OnboardingProfile.fromJson(Map<String, dynamic> json) {
    final rawAreas = json['focusAreas'];
    final areas = <FocusArea>{
      if (rawAreas is List)
        for (final a in rawAreas)
          if (FocusArea.tryParse(a?.toString()) case final f?) f,
    };
    final rawTarget = json['targetAttendance'];
    final avatar = json['avatarCharacter'];
    return OnboardingProfile(
      name: Validators.sanitizeName(json['name']?.toString()),
      focusAreas: areas,
      targetAttendance: rawTarget is num
          ? rawTarget.round().clamp(minTarget, maxTarget)
          : _defaultTarget,
      // Only accept characters that exist and are on the free plan, so a new
      // (free) account never starts on a locked avatar.
      avatarCharacter:
          avatar is String && ProfileAvatars.isFree(avatar) ? avatar : null,
      studyRhythm: StudyRhythm.tryParse(json['studyRhythm']?.toString()),
    );
  }

  String encode() => jsonEncode(toJson());

  static OnboardingProfile decode(String? raw) {
    if (raw == null || raw.isEmpty) return const OnboardingProfile();
    try {
      final v = jsonDecode(raw);
      if (v is Map<String, dynamic>) return OnboardingProfile.fromJson(v);
    } catch (_) {}
    return const OnboardingProfile();
  }
}

/// Small attendance helpers used to make the target step concrete.
class AttendanceMath {
  AttendanceMath._();

  /// How many of [totalClasses] a student can miss and still finish at or
  /// above [targetPercent]. Integer maths avoids float rounding at the edge
  /// (e.g. 75% of 40 = exactly 30 attended → 10 skippable).
  static int maxSkippable(int totalClasses, int targetPercent) {
    if (totalClasses <= 0) return 0;
    final t = targetPercent.clamp(0, 100);
    final mustAttend = (totalClasses * t + 99) ~/ 100; // ceil(N * t / 100)
    return totalClasses - mustAttend;
  }
}
