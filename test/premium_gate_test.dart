import 'package:classtrack/features/opportunities/domain/resource.dart';
import 'package:classtrack/features/opportunities/domain/resource_type.dart';
import 'package:classtrack/features/opportunities/presentation/providers/opportunities_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a resource updated [daysAgo] days ago (null ⇒ no updatedAt).
Resource _r(String id, {int? daysAgo}) => Resource(
      id: id,
      type: ResourceType.internship,
      title: id,
      organization: 'Org',
      updatedAt: daysAgo == null
          ? null
          : DateTime.now().subtract(Duration(days: daysAgo)),
    );

void main() {
  group('sortByRecency', () {
    test('orders newest-updated first, undated last', () {
      final out = sortByRecency([
        _r('old', daysAgo: 30),
        _r('undated'),
        _r('new', daysAgo: 1),
        _r('mid', daysAgo: 10),
      ]);
      expect(out.map((r) => r.id).toList(), ['new', 'mid', 'old', 'undated']);
    });

    test('does not mutate the input list', () {
      final input = [_r('a', daysAgo: 5), _r('b', daysAgo: 1)];
      sortByRecency(input);
      expect(input.map((r) => r.id).toList(), ['a', 'b']);
    });
  });

  group('freeAllowedIds (free-tier premium gate)', () {
    final many = List.generate(8, (i) => _r('r$i', daysAgo: i)); // r0 newest

    test('Pro users are never limited (null = show all)', () {
      expect(freeAllowedIds(many, isPro: true), isNull);
    });

    test('null when the feed is within the free limit', () {
      final few = many.take(kFreeResourceLimit).toList();
      expect(freeAllowedIds(few, isPro: false), isNull);
    });

    test('free users get exactly the 5 most-recently-updated ids', () {
      final ids = freeAllowedIds(many, isPro: false);
      expect(ids, isNotNull);
      expect(ids!.length, kFreeResourceLimit);
      // r0..r4 are the newest five (r0 updated today … r4 four days ago).
      expect(ids, {'r0', 'r1', 'r2', 'r3', 'r4'});
      expect(ids.contains('r5'), isFalse); // older ⇒ locked
    });

    test('locked count is total minus the free preview', () {
      final ids = freeAllowedIds(many, isPro: false)!;
      expect(many.length - ids.length, 3); // 8 total − 5 free = 3 locked
    });
  });

  group('splitPerksForDisplay (perks search can\'t bypass the gate)', () {
    Resource perk(String id, int daysAgo, {bool featured = false}) => Resource(
          id: id,
          type: ResourceType.discount,
          title: id,
          organization: id,
          featured: featured,
          updatedAt: DateTime.now().subtract(Duration(days: daysAgo)),
        );
    // p0..p4 are the free five; p5..p7 are locked.
    final perks = List.generate(8, (i) => perk('p$i', i));
    final allowed = freeAllowedIds(perks, isPro: false)!;

    test('REGRESSION: searching for a locked perk shows nothing of it', () {
      // The search result is ONLY a locked perk (e.g. user typed its name).
      final split = splitPerksForDisplay([perks[7]],
          allowedIds: allowed, searching: true);
      expect(split.carousel, isEmpty);
      expect(split.deals, isEmpty);
    });

    test('searching shows only the allowed matches, with no carousel', () {
      final split = splitPerksForDisplay([perks[1], perks[6]],
          allowedIds: allowed, searching: true);
      expect(split.carousel, isEmpty);
      expect(split.deals.map((r) => r.id), ['p1']);
    });

    test('category filter with only locked perks: fallback carousel is empty',
        () {
      final split = splitPerksForDisplay([perks[5], perks[6]],
          allowedIds: allowed, searching: false);
      expect(split.carousel, isEmpty);
      expect(split.deals, isEmpty);
    });

    test('fallback carousel uses allowed perks only; deals exclude them', () {
      final split =
          splitPerksForDisplay(perks, allowedIds: allowed, searching: false);
      expect(split.carousel.map((r) => r.id), ['p0', 'p1', 'p2']);
      expect(split.deals.map((r) => r.id), ['p3', 'p4']);
      for (final r in [...split.carousel, ...split.deals]) {
        expect(allowed.contains(r.id), isTrue);
      }
    });

    test('Pro (null gate) sees everything when searching', () {
      final split =
          splitPerksForDisplay(perks, allowedIds: null, searching: true);
      expect(split.deals.length, perks.length);
    });
  });
}
