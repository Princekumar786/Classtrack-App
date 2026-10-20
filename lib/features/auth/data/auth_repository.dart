import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/validators.dart';
import '../../../services/error_reporter.dart';
import '../domain/app_user.dart';
import '../domain/onboarding_profile.dart';
import '../domain/profile_avatars.dart';

/// Handles authentication and the users/{uid} profile document.
class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final GoogleSignIn _googleSignIn;

  AuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore db,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth,
        _db = db,
        _googleSignIn = googleSignIn ??
            GoogleSignIn(
              // Explicit Web client ID so the native SDK always returns an ID
              // token, without depending on the `default_web_client_id`
              // resource that R8 strips from shrunk release builds.
              serverClientId: AppConstants.googleServerClientId,
            );

  User? get currentUser => _auth.currentUser;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection(AppConstants.usersCollection).doc(uid);

  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signUpWithEmail(
    String email,
    String password,
    String displayName, {
    OnboardingProfile? seed,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    // Sanitize the name before it touches Auth or Firestore so a user can't
    // store HTML/script (e.g. "<b>Alert</b>") that could render on a web/email
    // surface downstream.
    final cleanName = Validators.sanitizeName(displayName);
    await cred.user?.updateDisplayName(cleanName);
    await _ensureProfile(cred.user!, displayName: cleanName, seed: seed);
    // Send a verification link so the account's email is authenticated.
    await cred.user?.sendEmailVerification();
  }

  /// Whether the signed-in user's email is verified (Google users are always
  /// considered verified).
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  bool get isPasswordUser =>
      _auth.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

  Future<void> reloadUser() async => _auth.currentUser?.reload();

  Future<void> resendVerificationEmail() async =>
      _auth.currentUser?.sendEmailVerification();

  Future<void> signInWithGoogle({OnboardingProfile? seed}) async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      // User cancelled the picker.
      throw FirebaseAuthException(
        code: 'cancelled',
        message: 'Sign-in cancelled',
      );
    }
    final googleAuth = await googleUser.authentication;
    if (googleAuth.idToken == null) {
      // No ID token means the native Google SDK couldn't mint a Firebase-usable
      // token. This is a build/config problem — NOT a wrong password — so it
      // gets its own code to avoid the misleading "Incorrect email or password"
      // message. Common causes: the app's signing SHA-1 (e.g. the Play App
      // Signing key) isn't registered in Firebase, or the Web client ID is
      // missing from the build.
      throw FirebaseAuthException(
        code: 'google-no-token',
        message: 'Google didn\'t return a sign-in token.',
      );
    }
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final cred = await _auth.signInWithCredential(credential);
    await _ensureProfile(cred.user!,
        displayName: cred.user!.displayName, seed: seed);
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Sign-in path: creates the profile if missing, retrying short network
  /// blips. Still throws if it keeps failing (so the onboarding [seed] is NOT
  /// cleared); the app-start self-heal ([ensureProfileDoc] via
  /// `profileSelfHealProvider`) then creates it once Firestore is reachable.
  Future<void> _ensureProfile(
    User user, {
    String? displayName,
    OnboardingProfile? seed,
  }) =>
      withProfileRetry(() => ensureProfileDoc(
            uid: user.uid,
            displayName: displayName ?? user.displayName,
            email: user.email,
            photoUrl: user.photoURL,
            seed: seed,
          ));

  /// Creates `users/{uid}` if it does not exist yet. Returns true when it was
  /// created now. Existing profiles are never overwritten.
  ///
  /// Runs in a transaction on purpose: transactions always read from the
  /// SERVER and fail when offline. A plain `get()` could answer "doesn't
  /// exist" from the offline cache, and the following `set()` would then wipe
  /// a real profile once the phone came back online.
  Future<bool> ensureProfileDoc({
    required String uid,
    String? displayName,
    String? email,
    String? photoUrl,
    OnboardingProfile? seed,
  }) {
    final ref = _userDoc(uid);
    return _db.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return false;
      final profile = buildNewProfile(
        uid: uid,
        displayName: displayName,
        email: email,
        photoUrl: photoUrl,
        seed: seed,
      );
      tx.set(ref, profile.toMap());
      return true;
    });
  }

  /// Runs [action], retrying transient (network/offline) failures with a
  /// growing pause. Non-transient errors (e.g. permission-denied) and the last
  /// failure are rethrown.
  static Future<T> withProfileRetry<T>(
    Future<T> Function() action, {
    List<Duration> delays = const [
      Duration(seconds: 1),
      Duration(seconds: 3),
    ],
  }) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await action();
      } catch (e) {
        if (attempt >= delays.length || !isTransientError(e)) rethrow;
        await Future<void>.delayed(delays[attempt]);
      }
    }
  }

  /// Pure builder for a first-time profile (unit-tested). The auth-provided
  /// name wins; the onboarding name is only a fallback (e.g. a Google account
  /// with no display name).
  static AppUser buildNewProfile({
    required String uid,
    String? displayName,
    String? email,
    String? photoUrl,
    OnboardingProfile? seed,
  }) {
    final authName = Validators.sanitizeName(displayName);
    final name = authName.isNotEmpty ? authName : (seed?.name ?? '');
    return AppUser(
      uid: uid,
      displayName: name.isEmpty ? null : name,
      email: email,
      photoUrl: photoUrl,
      // The character picked in onboarding, else a distinct deterministic
      // default (on uid) instead of a plain name initial.
      avatarCharacter: seed?.avatarCharacter ?? ProfileAvatars.defaultForUid(uid),
      targetAttendancePercent: seed?.targetAttendance.toDouble() ??
          AppConstants.defaultTargetAttendance,
      focusAreas: seed?.focusAreas.map((f) => f.name).toList() ?? const [],
      studyRhythm: seed?.studyRhythm?.name,
    );
  }

  Stream<AppUser?> watchProfile(String uid) {
    return _userDoc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return AppUser.fromMap(uid, data);
    });
  }

  Future<void> updateTargetAttendance(String uid, double target) =>
      _userDoc(uid).set(
        {'targetAttendancePercent': target},
        SetOptions(merge: true),
      );

  Future<void> updateMonthlyBudget(String uid, double budget) =>
      _userDoc(uid).set(
        {'monthlyBudget': budget < 0 ? 0 : budget},
        SetOptions(merge: true),
      );

  Future<void> updateCurrency(String uid, String currency) =>
      _userDoc(uid).set(
        {'currency': currency},
        SetOptions(merge: true),
      );

  Future<void> updateDisplayName(String uid, String name) async {
    final clean = Validators.sanitizeName(name);
    await _auth.currentUser?.updateDisplayName(clean);
    await _userDoc(uid).set({'displayName': clean}, SetOptions(merge: true));
  }

  /// Merge-writes the optional progressive-profiling fields (country, degree,
  /// interests, career goal, …). The caller builds [fields] — using
  /// [FieldValue.delete] for values the student cleared and sanitized strings
  /// for text — so a single round-trip both sets and clears profile details.
  /// Only client-writable profile keys should ever be passed here; server-owned
  /// fields (referral*, entitlements) are never part of this map.
  Future<void> updateProfileDetails(
    String uid,
    Map<String, dynamic> fields,
  ) =>
      _userDoc(uid).set(fields, SetOptions(merge: true));

  /// Full account deletion — required for Play Store data-safety compliance.
  /// Delegates to the `deleteAccount` Cloud Function, which recursively deletes
  /// the ENTIRE users/{uid} tree, the server-only entitlement/usage docs, and
  /// the Firebase Auth user with Admin privileges. This fixes the old client
  /// path that (a) only deleted subjects/sessions/attendance (leaving tasks,
  /// exams, notes, expenses, grades, habits, study & chat behind) and (b) wiped
  /// data BEFORE user.delete(), which could fail with requires-recent-login and
  /// leave an emptied-but-live account.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final callable = FirebaseFunctions.instance.httpsCallable('deleteAccount');
    await callable.call();
    // The server removed the auth user; clear local sessions so the app returns
    // to the logged-out state (which also cancels local notifications).
    await _googleSignIn.signOut();
    try {
      await _auth.signOut();
    } catch (_) {/* already gone server-side */}
  }
}
