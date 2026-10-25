// Automatic country targeting: a student in India who never picked a country
// must still see India-only opportunities/discounts and receive India-targeted
// CMS pushes. Profile choice always wins over the phone-detected country.
import 'package:classtrack/core/providers/firebase_providers.dart';
import 'package:classtrack/features/auth/domain/app_user.dart';
import 'package:classtrack/features/auth/presentation/providers/auth_providers.dart';
import 'package:classtrack/features/opportunities/domain/resource.dart';
import 'package:classtrack/features/opportunities/domain/resource_status.dart';
import 'package:classtrack/features/opportunities/domain/resource_type.dart';
import 'package:classtrack/features/opportunities/presentation/providers/opportunities_providers.dart';
import 'package:classtrack/services/country_detector.dart';
import 'package:classtrack/services/push_messaging_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const uid = 'u1';

class _FixedDetector extends CountryDetector {
  _FixedDetector(this.value);
  final DetectedCountry? value;
  @override
  Future<DetectedCountry?> detect() async => value;
}

class _SpyPush extends PushMessagingService {
  final topics = <String?>[];
  @override
  Future<void> setCountryTopic(String? country) async =>
      topics.add(PushMessagingService.countryTopicFor(country));
}

const _indiaOnly = Resource(
  id: 'in',
  type: ResourceType.scholarship,
  title: 'India scholarship',
  organization: 'Org',
  status: ResourceStatus.active,
  countries: ['India'],
);
const _usOnly = Resource(
  id: 'us',
  type: ResourceType.scholarship,
  title: 'US scholarship',
  organization: 'Org',
  status: ResourceStatus.active,
  countries: ['United States'],
);
const _global = Resource(
  id: 'gl',
  type: ResourceType.scholarship,
  title: 'Global scholarship',
  organization: 'Org',
  status: ResourceStatus.active,
);

void main() {
  group('effectiveCountryOf (same rule as functions/notifications.js)', () {
    test('profile wins; empty or "Other" defers to detection', () {
      expect(effectiveCountryOf('Germany', 'India'), 'Germany');
      expect(effectiveCountryOf(null, 'India'), 'India');
      expect(effectiveCountryOf('  ', 'India'), 'India');
      expect(effectiveCountryOf('Other', 'India'), 'India');
      expect(effectiveCountryOf('Other', null), 'Other');
      expect(effectiveCountryOf(null, null), isNull);
    });

    test('AppUser exposes it and flags when it was detected', () {
      final detected = AppUser.fromMap(uid, {'detectedCountry': 'India'});
      expect(detected.effectiveCountry, 'India');
      expect(detected.countryIsDetected, isTrue);
      final chosen =
          AppUser.fromMap(uid, {'country': 'Canada', 'detectedCountry': 'India'});
      expect(chosen.effectiveCountry, 'Canada');
      expect(chosen.countryIsDetected, isFalse);
    });
  });

  group('pickCountry', () {
    test('SIM first, then network, then device region', () {
      expect(pickCountry(sim: 'in', network: 'us', region: 'US')?.name, 'India');
      expect(pickCountry(sim: 'in')?.source, CountrySource.sim);
      final net = pickCountry(sim: '', network: 'IN', region: 'US');
      expect((net?.name, net?.source), ('India', CountrySource.network));
      // Wi-Fi-only tablet set to English (India).
      final reg = pickCountry(region: 'IN');
      expect((reg?.name, reg?.source), ('India', CountrySource.deviceRegion));
    });

    test('unknown or non-targetable codes give nothing', () {
      expect(pickCountry(sim: 'xx', network: null, region: null), isNull);
      expect(pickCountry(), isNull);
      expect(pickCountry(sim: 'gb')?.name, 'United Kingdom');
    });

    test('every mapped name is a country the CMS can target', () {
      for (final name in kIsoToTargetCountry.values) {
        expect(PushMessagingService.countryTopicFor(name), isNotNull);
      }
    });
  });

  group('wired end to end', () {
    Future<(ProviderContainer, FakeFirebaseFirestore, _SpyPush)> setup(
        Map<String, dynamic> profile,
        {DetectedCountry? detected}) async {
      final db = FakeFirebaseFirestore();
      await db.collection('users').doc(uid).set(profile);
      final push = _SpyPush();
      final c = ProviderContainer(overrides: [
        firestoreProvider.overrideWithValue(db),
        currentUidProvider.overrideWithValue(uid),
        countryDetectorProvider.overrideWithValue(_FixedDetector(detected)),
        pushMessagingServiceProvider.overrideWithValue(push),
        visibleResourcesProvider
            .overrideWith((ref) => Stream.value(const [_indiaOnly, _usOnly, _global])),
        userProfileProvider.overrideWith((ref) => db
            .collection('users')
            .doc(uid)
            .snapshots()
            .map((s) => s.exists ? AppUser.fromMap(uid, s.data()!) : null)),
      ]);
      addTearDown(c.dispose);
      c.listen(countryDetectionSyncProvider, (_, __) {});
      c.listen(pushCountryTopicSyncProvider, (_, __) {});
      c.listen(opportunitiesFeedProvider, (_, __) {});
      // Detection → profile write → stream → topic hops a few async gaps;
      // 50ms was flaky on a busy machine.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return (c, db, push);
    }

    test('no profile country: detects India, saves it, targets India everywhere',
        () async {
      final (c, db, push) = await setup({'displayName': 'A'},
          detected: const DetectedCountry('India', CountrySource.sim));

      final doc = await db.collection('users').doc(uid).get();
      expect(doc['detectedCountry'], 'India');
      expect(doc['detectedCountrySource'], 'sim');

      expect(c.read(effectiveCountryProvider), 'India');
      final ids = c.read(opportunitiesFeedProvider).map((r) => r.id).toSet();
      expect(ids, {'in', 'gl'}, reason: 'India-only shown, US-only hidden');
      // Device joins the topic an India-targeted CMS push is sent to.
      expect(push.topics.last, 'country_india');
    });

    test('profile country beats the detected one', () async {
      final (c, db, push) = await setup({'country': 'United States'},
          detected: const DetectedCountry('India', CountrySource.sim));
      expect(c.read(effectiveCountryProvider), 'United States');
      final ids = c.read(opportunitiesFeedProvider).map((r) => r.id).toSet();
      expect(ids, {'us', 'gl'});
      expect(push.topics.last, 'country_united_states');
      // Detection is still recorded (used if they clear their choice).
      final doc = await db.collection('users').doc(uid).get();
      expect(doc['detectedCountry'], 'India');
    });

    test('nothing detected and no profile: global only, no country topic',
        () async {
      final (c, db, push) = await setup({'displayName': 'A'});
      expect(c.read(effectiveCountryProvider), isNull);
      final ids = c.read(opportunitiesFeedProvider).map((r) => r.id).toSet();
      expect(ids, {'gl'});
      expect(push.topics.last, isNull);
      final doc = await db.collection('users').doc(uid).get();
      expect(doc.data()!.containsKey('detectedCountry'), isFalse);
    });

    test('no rewrite when the saved detection is unchanged', () async {
      final (_, db, _) = await setup({'detectedCountry': 'India'},
          detected: const DetectedCountry('India', CountrySource.sim));
      final doc = await db.collection('users').doc(uid).get();
      expect(doc.data()!.containsKey('detectedCountryAt'), isFalse);
    });
  });
}
