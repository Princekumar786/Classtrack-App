import 'dart:io';

import 'package:classtrack/features/auth/domain/profile_avatars.dart';
import 'package:flutter_test/flutter_test.dart';

/// firestore.rules hard-codes the free character list (rules can't import
/// Dart). If ProfileAvatars changes, this test fails until the rules match —
/// otherwise free users could be blocked from (or allowed past) the Pro gate.
void main() {
  test('firestore.rules freeAvatars() matches ProfileAvatars.free', () {
    final rules = File('firestore.rules').readAsStringSync();
    final body = RegExp(r'function freeAvatars\(\)\s*\{\s*return\s*\[([^\]]*)\]')
        .firstMatch(rules)!
        .group(1)!;
    final inRules = RegExp(r"'([^']+)'").allMatches(body).map((m) => m.group(1)).toList();
    expect(inRules, ProfileAvatars.free);
  });
}
