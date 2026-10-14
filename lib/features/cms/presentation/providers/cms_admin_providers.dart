import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/utils/firestore_parsing.dart';
import '../../domain/audit_log.dart';

/// Streams recent audit-log entries (admins only per Firestore rules).
final auditLogsProvider = StreamProvider<List<AuditLogEntry>>((ref) {
  final db = ref.watch(firestoreProvider);
  return db
      .collection('auditLogs')
      .orderBy('at', descending: true)
      .limit(150)
      .snapshots()
      .map(
        (s) => parseDocsSafely(
          s.docs,
          AuditLogEntry.fromMap,
          context: 'auditLogs',
        ),
      );
});

/// Calls the admin-only `setUserRole` callable and reports success/failure.
class SetUserRoleController extends StateNotifier<AsyncValue<void>> {
  final FirebaseFunctions _functions;
  SetUserRoleController(this._functions) : super(const AsyncData(null));

  /// Assigns [roleKey] ('none' to revoke) to [uid]. Returns an error message on
  /// failure, or null on success.
  Future<String?> assign({required String uid, required String roleKey}) async {
    state = const AsyncLoading();
    try {
      final callable = _functions.httpsCallable('setUserRole');
      await callable.call({'uid': uid.trim(), 'role': roleKey});
      state = const AsyncData(null);
      return null;
    } on FirebaseFunctionsException catch (e, st) {
      state = AsyncError(e, st);
      switch (e.code) {
        case 'permission-denied':
          return e.message ?? 'You are not allowed to assign this role.';
        case 'not-found':
          return 'No user found with that uid.';
        case 'unauthenticated':
          return 'Please sign in again.';
        case 'invalid-argument':
          return e.message ?? 'Invalid input.';
        default:
          return e.message ?? 'Could not update the role.';
      }
    } catch (e, st) {
      state = AsyncError(e, st);
      return 'Something went wrong. Try again.';
    }
  }
}

final setUserRoleControllerProvider =
    StateNotifierProvider<SetUserRoleController, AsyncValue<void>>((ref) {
      return SetUserRoleController(ref.watch(firebaseFunctionsProvider));
    });

/// A user resolved by email lookup (Admin SDK), with their current CMS role.
class UserLookup {
  final String uid;
  final String email;
  final String? displayName;

  /// Role claim key ('none' when no CMS access).
  final String roleKey;
  const UserLookup({
    required this.uid,
    required this.email,
    this.displayName,
    required this.roleKey,
  });
}

/// Looks up a user by email via the admin-only `lookupUserByEmail` callable.
class UserLookupController extends StateNotifier<AsyncValue<UserLookup?>> {
  final FirebaseFunctions _functions;
  UserLookupController(this._functions) : super(const AsyncData(null));

  void clear() => state = const AsyncData(null);

  Future<void> lookup(String email) async {
    state = const AsyncLoading();
    try {
      final res = await _functions.httpsCallable('lookupUserByEmail').call({
        'email': email.trim(),
      });
      final d = (res.data as Map).cast<String, dynamic>();
      state = AsyncData(
        UserLookup(
          uid: d['uid'] as String,
          email: (d['email'] as String?) ?? email.trim(),
          displayName: d['displayName'] as String?,
          roleKey: (d['role'] as String?) ?? 'none',
        ),
      );
    } on FirebaseFunctionsException catch (e, st) {
      state = AsyncError(
        e.code == 'not-found'
            ? 'No user found with that email.'
            : e.code == 'permission-denied'
            ? 'Admins only.'
            : (e.message ?? 'Lookup failed.'),
        st,
      );
    } catch (e, st) {
      state = AsyncError('Something went wrong. Try again.', st);
    }
  }
}

final userLookupControllerProvider =
    StateNotifierProvider<UserLookupController, AsyncValue<UserLookup?>>((ref) {
      return UserLookupController(ref.watch(firebaseFunctionsProvider));
    });
