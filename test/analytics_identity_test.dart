// Analytics: PostHog shows WHO did what by name, and every screen has a
// readable name (class names are obfuscated in release builds, so an unnamed
// route would never show up in PostHog's activity).
import 'dart:io';

import 'package:classtrack/features/auth/domain/app_user.dart';
import 'package:classtrack/services/analytics_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('person properties come from the profile, blanks are dropped', () {
    final user = AppUser.fromMap('u1', {
      'displayName': 'Priya Sharma',
      'email': 'priya@example.com',
      'detectedCountry': 'India',
      'university': '  ',
      'college': 'IIT Delhi',
      'semester': 5,
      'referralCount': 3,
    });
    final p = posthogPersonProperties(user, isPro: true);
    expect(p['name'], 'Priya Sharma');
    expect(p['email'], 'priya@example.com');
    expect(p['country'], 'India');
    expect(p['country_source'], 'detected');
    expect(p['college'], 'IIT Delhi');
    expect(p.containsKey('university'), isFalse);
    expect(p['semester'], 5);
    expect(p['is_pro'], true);
    expect(p['referral_count'], 3);
    expect(p['app_version'], isNotEmpty);
  });

  test('falls back to the auth email when the profile has none', () {
    final user = AppUser.fromMap('u1', {'country': 'Canada'});
    final p = posthogPersonProperties(user, isPro: false, authEmail: 'a@b.co');
    expect(p['email'], 'a@b.co');
    expect(p['country_source'], 'profile');
    expect(p.containsKey('name'), isFalse);
  });

  test('every MaterialPageRoute in lib/ has a screen name', () {
    final unnamed = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r'MaterialPageRoute(<[^>]*>)?\(').allMatches(src)) {
        final seg = src.substring(m.start, (m.start + 260).clamp(0, src.length));
        if (!seg.contains('settings:')) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          unnamed.add('${f.path}:$line');
        }
      }
    }
    expect(unnamed, isEmpty,
        reason: 'Add settings: RouteSettings(name: …) so PostHog tracks it');
  });
}
