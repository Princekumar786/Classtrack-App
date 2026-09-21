import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';

/// App-level user profile stored at users/{uid}.
class AppUser {
  final String uid;
  final String? displayName;
  final String? email;
  final String? photoUrl;

  /// The selected profile character asset file name (e.g.
  /// `icons8-batman-144.png`), stored under `assets/characters/`. Null falls
  /// back to a deterministic default derived from [uid]. Replaces the old
  /// first-letter avatar.
  final String? avatarCharacter;

  final double targetAttendancePercent;
  final double monthlyBudget;
  final String currency;
  final DateTime? createdAt;

  /// The user's own shareable invite code (allocated on first visit to the
  /// referral screen by the getReferralInfo Cloud Function). Null until then.
  final String? referralCode;

  /// How many friends have redeemed this user's code.
  final int referralCount;

  /// The referral code / referrer uid this user redeemed, if any. Non-null once
  /// they've accepted someone's invite (each user may redeem only once).
  final String? referredBy;

  // ── Progressive profiling (all OPTIONAL) ────────────────────────────────
  // These power personalised Opportunities & Discounts (Phase 6). They are
  // filled in later via Settings → Edit profile — never forced at sign-up —
  // so every field is nullable/empty and the app must work with none of them.

  /// Country the student is based in (e.g. "India"). ⭐ Primary targeting key
  /// for country-based promotions and discounts.
  final String? country;

  /// State / region within the country.
  final String? stateRegion;

  /// City / town.
  final String? city;

  /// University the student attends.
  final String? university;

  /// College / institute (may differ from the parent university).
  final String? college;

  /// Degree / programme, e.g. "MBA", "B.Tech".
  final String? degree;

  /// Department / branch, e.g. "Computer Science", "Finance".
  final String? department;

  /// Current academic year (1..N), null when unknown.
  final int? academicYear;

  /// Current semester (1..N), null when unknown.
  final int? semester;

  /// Expected graduation year (e.g. 2027), null when unknown.
  final int? graduationYear;

  /// Primary career goal, e.g. "Internship", "Job", "Higher studies",
  /// "Research", "Freelancing", "Startup", "Government exams".
  final String? careerGoal;

  /// Free-form interests used for opportunity matching, e.g. ["AI",
  /// "Finance"]. Empty when the student hasn't picked any.
  final List<String> interests;

  const AppUser({
    required this.uid,
    this.displayName,
    this.email,
    this.photoUrl,
    this.avatarCharacter,
    this.targetAttendancePercent = AppConstants.defaultTargetAttendance,
    this.monthlyBudget = 0,
    this.currency = '₹',
    this.createdAt,
    this.referralCode,
    this.referralCount = 0,
    this.referredBy,
    this.country,
    this.stateRegion,
    this.city,
    this.university,
    this.college,
    this.degree,
    this.department,
    this.academicYear,
    this.semester,
    this.graduationYear,
    this.careerGoal,
    this.interests = const [],
  });

  /// True once the student has filled in at least one profiling field. Used to
  /// nudge (never force) profile completion and to gate personalisation.
  bool get hasAnyProfileDetails =>
      (country?.isNotEmpty ?? false) ||
      (stateRegion?.isNotEmpty ?? false) ||
      (city?.isNotEmpty ?? false) ||
      (university?.isNotEmpty ?? false) ||
      (college?.isNotEmpty ?? false) ||
      (degree?.isNotEmpty ?? false) ||
      (department?.isNotEmpty ?? false) ||
      academicYear != null ||
      semester != null ||
      graduationYear != null ||
      (careerGoal?.isNotEmpty ?? false) ||
      interests.isNotEmpty;

  AppUser copyWith({
    String? displayName,
    String? email,
    String? photoUrl,
    String? avatarCharacter,
    double? targetAttendancePercent,
    double? monthlyBudget,
    String? currency,
    String? referralCode,
    int? referralCount,
    String? referredBy,
    String? country,
    String? stateRegion,
    String? city,
    String? university,
    String? college,
    String? degree,
    String? department,
    int? academicYear,
    int? semester,
    int? graduationYear,
    String? careerGoal,
    List<String>? interests,
  }) {
    return AppUser(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      avatarCharacter: avatarCharacter ?? this.avatarCharacter,
      targetAttendancePercent:
          targetAttendancePercent ?? this.targetAttendancePercent,
      monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      currency: currency ?? this.currency,
      createdAt: createdAt,
      referralCode: referralCode ?? this.referralCode,
      referralCount: referralCount ?? this.referralCount,
      referredBy: referredBy ?? this.referredBy,
      country: country ?? this.country,
      stateRegion: stateRegion ?? this.stateRegion,
      city: city ?? this.city,
      university: university ?? this.university,
      college: college ?? this.college,
      degree: degree ?? this.degree,
      department: department ?? this.department,
      academicYear: academicYear ?? this.academicYear,
      semester: semester ?? this.semester,
      graduationYear: graduationYear ?? this.graduationYear,
      careerGoal: careerGoal ?? this.careerGoal,
      interests: interests ?? this.interests,
    );
  }

  Map<String, dynamic> toMap() => {
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'avatarCharacter': avatarCharacter,
        'targetAttendancePercent': targetAttendancePercent,
        'monthlyBudget': monthlyBudget,
        'currency': currency,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        // NOTE: referralCode / referralCount / referredBy are intentionally NOT
        // written here. They are owned by the Cloud Functions backend (admin
        // SDK) so a client can never spoof their invite count or reward. The
        // client only ever reads them (see fromMap below).
      };

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    final rawName = map['displayName'] as String?;
    // Sanitize on read too, so any name written before this guard existed (or
    // by a future path that forgot to) can never render as HTML downstream.
    final cleanName = rawName == null ? null : Validators.sanitizeName(rawName);
    return AppUser(
      uid: uid,
      displayName: (cleanName == null || cleanName.isEmpty) ? null : cleanName,
      email: map['email'] as String?,
      photoUrl: map['photoUrl'] as String?,
      avatarCharacter: map['avatarCharacter'] as String?,
      targetAttendancePercent:
          (map['targetAttendancePercent'] as num?)?.toDouble() ??
              AppConstants.defaultTargetAttendance,
      monthlyBudget: (map['monthlyBudget'] as num?)?.toDouble() ?? 0,
      currency: (map['currency'] as String?) ?? '₹',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      referralCode: map['referralCode'] as String?,
      referralCount: (map['referralCount'] as num?)?.toInt() ?? 0,
      referredBy: map['referredBy'] as String?,
      country: map['country'] as String?,
      stateRegion: map['stateRegion'] as String?,
      city: map['city'] as String?,
      university: map['university'] as String?,
      college: map['college'] as String?,
      degree: map['degree'] as String?,
      department: map['department'] as String?,
      academicYear: (map['academicYear'] as num?)?.toInt(),
      semester: (map['semester'] as num?)?.toInt(),
      graduationYear: (map['graduationYear'] as num?)?.toInt(),
      careerGoal: map['careerGoal'] as String?,
      interests: (map['interests'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
    );
  }
}
