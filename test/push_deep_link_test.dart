import 'package:classtrack/services/push_deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushDeepLink.parse', () {
    test('resource:<id> and aliases → ResourceDeepLink', () {
      expect(PushDeepLink.parse('resource:abc123'),
          const ResourceDeepLink('abc123'));
      expect(PushDeepLink.parse('  Opportunity: sap-cert '),
          const ResourceDeepLink('sap-cert'));
      expect(PushDeepLink.parse('discount:x'), const ResourceDeepLink('x'));
      expect(PushDeepLink.parse('perk:y'), const ResourceDeepLink('y'));
    });

    test('forResource round-trips', () {
      final p = PushDeepLink.forResource(' id42 ');
      expect(p, 'resource:id42');
      expect(PushDeepLink.parse(p), const ResourceDeepLink('id42'));
    });

    test('tab:<name> → TabDeepLink with HomeShell index', () {
      expect(PushDeepLink.parse('tab:home'), const TabDeepLink(0));
      expect(PushDeepLink.parse('tab:Schedule'), const TabDeepLink(1));
      expect(PushDeepLink.parse('tab:explore'), const TabDeepLink(2));
      expect(PushDeepLink.parse('tab:opportunities'), const TabDeepLink(2));
      expect(PushDeepLink.parse('tab:planner'), const TabDeepLink(3));
    });

    test('non-links / malformed → null', () {
      expect(PushDeepLink.parse(null), isNull);
      expect(PushDeepLink.parse(''), isNull);
      expect(PushDeepLink.parse('daily_agenda'), isNull);
      expect(PushDeepLink.parse('attendance_checkin|s1|09:00'), isNull);
      expect(PushDeepLink.parse('resource:'), isNull);
      expect(PushDeepLink.parse('resource:a/b'), isNull);
      expect(PushDeepLink.parse('tab:unknown'), isNull);
      expect(PushDeepLink.parse(':abc'), isNull);
      expect(PushDeepLink.parse('https://example.com'), isNull);
    });
  });
}
