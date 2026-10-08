import 'package:classtrack/features/auth/domain/profile_avatars.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks in the freemium split: the first 15 characters are free, the rest are
/// Pro, and every free user is auto-assigned (and can fall back to) only a free
/// character so they're never locked out of their own avatar.
void main() {
  test('exactly 15 characters are free', () {
    expect(ProfileAvatars.freeCount, 15);
    expect(ProfileAvatars.free.length, 15);
  });

  test('free + pro together cover the whole catalog with no overlap', () {
    expect(ProfileAvatars.free.length + ProfileAvatars.pro.length,
        ProfileAvatars.all.length);
    expect(ProfileAvatars.free.toSet().intersection(ProfileAvatars.pro.toSet()),
        isEmpty);
    expect([...ProfileAvatars.free, ...ProfileAvatars.pro], ProfileAvatars.all);
  });

  test('isFree reflects the split precisely', () {
    for (final f in ProfileAvatars.free) {
      expect(ProfileAvatars.isFree(f), isTrue, reason: '$f should be free');
    }
    for (final p in ProfileAvatars.pro) {
      expect(ProfileAvatars.isFree(p), isFalse, reason: '$p should be Pro');
    }
    expect(ProfileAvatars.isFree(null), isFalse);
    expect(ProfileAvatars.isFree('not-a-character.png'), isFalse);
  });

  test('the default avatar assigned at sign-up is always a free one', () {
    for (final uid in ['', 'user123', 'abc', 'zzz-999', 'PrinceKumar']) {
      final assigned = ProfileAvatars.defaultForUid(uid);
      expect(ProfileAvatars.free.contains(assigned), isTrue,
          reason: 'uid "$uid" was assigned non-free avatar $assigned');
    }
  });
}
