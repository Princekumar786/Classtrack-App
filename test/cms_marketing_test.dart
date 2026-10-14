import 'package:classtrack/features/cms/domain/marketing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Placements', () {
    test('all placements have labels', () {
      for (final p in Placements.all) {
        expect(Placements.label(p), isNotEmpty);
      }
      expect(Placements.label('home'), 'Home — bottom');
      expect(Placements.label('featured'), 'Featured card');
    });
  });

  group('CmsBanner.isLive', () {
    final now = DateTime(2026, 6, 15);
    test('unpublished is never live', () {
      const b = CmsBanner(id: 'b', title: 'T', published: false);
      expect(b.isLive(now), isFalse);
    });
    test('published with no window is live', () {
      const b = CmsBanner(id: 'b', title: 'T', published: true);
      expect(b.isLive(now), isTrue);
    });
    test('respects start/end window', () {
      final before = CmsBanner(
        id: 'b',
        title: 'T',
        published: true,
        startDate: now.add(const Duration(days: 1)),
      );
      expect(before.isLive(now), isFalse);
      final after = CmsBanner(
        id: 'b',
        title: 'T',
        published: true,
        endDate: now.subtract(const Duration(days: 1)),
      );
      expect(after.isLive(now), isFalse);
      final within = CmsBanner(
        id: 'b',
        title: 'T',
        published: true,
        startDate: now.subtract(const Duration(days: 1)),
        endDate: now.add(const Duration(days: 1)),
      );
      expect(within.isLive(now), isTrue);
    });
  });

  group('CmsBanner.fromMap', () {
    test('parses fields', () {
      final b = CmsBanner.fromMap('b1', {
        'title': 'Welcome',
        'placement': 'home',
        'countries': ['India', 'Global'],
        'priority': 5,
        'sponsored': true,
        'published': true,
        'startDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(b.title, 'Welcome');
      expect(b.placement, 'home');
      expect(b.countries, ['India', 'Global']);
      expect(b.priority, 5);
      expect(b.sponsored, isTrue);
      expect(b.published, isTrue);
      expect(b.startDate, DateTime(2026, 1, 1));
      // Older banners without the field keep showing to Pro users.
      expect(b.showToPro, isTrue);
    });

    test('showToPro round-trips', () {
      final off = CmsBanner.fromMap('b2', {'title': 'Ad', 'showToPro': false});
      expect(off.showToPro, isFalse);
      expect(off.toMap()['showToPro'], isFalse);
      expect(const CmsBanner(id: 'b', title: 'T').toMap()['showToPro'], isTrue);
    });
  });

  group('Campaign', () {
    test('defaults sponsored true; isLive respects publish + window', () {
      const c = Campaign(id: 'c', company: 'Acme', name: 'Promo');
      expect(c.sponsored, isTrue);
      expect(c.published, isFalse);
      expect(c.isLive(DateTime(2026, 6, 15)), isFalse);
    });

    test('fromMap parses fields', () {
      final c = Campaign.fromMap('c1', {
        'company': 'Acme',
        'name': 'Summer Promo',
        'resourceId': 'r1',
        'placement': 'discounts',
        'countries': ['USA'],
        'published': true,
      });
      expect(c.company, 'Acme');
      expect(c.name, 'Summer Promo');
      expect(c.resourceId, 'r1');
      expect(c.placement, 'discounts');
      expect(c.countries, ['USA']);
      expect(c.published, isTrue);
    });
  });
}
