import 'package:classtrack/features/moments/data/moment_share_service.dart';
import 'package:classtrack/features/moments/domain/shareable_moment.dart';
import 'package:classtrack/features/moments/presentation/widgets/moment_card.dart';
import 'package:classtrack/features/referral/domain/referral_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReferralInfo', () {
    test('parses a full server payload', () {
      final info = ReferralInfo.fromMap({
        'code': 'K7P2QM9',
        'referralCount': 12,
        'referredBy': 'someUid',
        'rewardDays': 3,
        'milestoneSize': 5,
        'milestoneDays': 7,
      });
      expect(info.code, 'K7P2QM9');
      expect(info.referralCount, 12);
      expect(info.hasRedeemed, isTrue);
      expect(info.milestonesReached, 2);
      expect(info.earnedDays, 14); // 2 groups of 5 * 7 days
      expect(info.inCurrentCycle, 2);
      expect(info.friendsToNextReward, 3);
    });

    test('applies safe defaults for a sparse payload (older backend)', () {
      final info = ReferralInfo.fromMap({'code': 'ABCD123'});
      expect(info.referralCount, 0);
      expect(info.referredBy, isNull);
      expect(info.hasRedeemed, isFalse);
      expect(info.rewardDays, 3);
      expect(info.milestoneSize, 5);
      expect(info.milestoneDays, 7);
      expect(info.earnedDays, 0);
      expect(info.friendsToNextReward, 5);
    });

    test('4 friends earn nothing yet; the 5th unlocks 7 days', () {
      const four = ReferralInfo(code: 'X', referralCount: 4, referredBy: null);
      expect(four.earnedDays, 0);
      expect(four.friendsToNextReward, 1);
      final five = four.copyWith(referralCount: 5);
      expect(five.earnedDays, 7);
      expect(five.friendsToNextReward, 5);
      expect(five.cycleProgress, 0);
    });
  });

  group('MomentCard capture pipeline', () {
    testWidgets('renders and rasterises to non-empty PNG bytes',
        (tester) async {
      final boundaryKey = GlobalKey();
      const moment = ShareableMoment(
        id: 'attendance',
        emoji: '👑',
        headline: 'Attendance royalty',
        value: '92%',
        valueLabel: 'attendance',
        caption: 'Consistent all semester.',
        shareText: '92% attendance 👑',
        gradient: [Color(0xFF8B7FEC), Color(0xFF6C5CE7)],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: const MomentCard(
                    moment: moment,
                    studentName: 'Alex',
                    inviteCode: 'K7P2QM9',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The card shows its hero stat and personalised invite line.
      expect(find.text('92%'), findsOneWidget);
      expect(find.text('Join with code K7P2QM9'), findsOneWidget);

      // The share pipeline can rasterise the boundary to a PNG. Image
      // encoding is real async work, so it must run via runAsync (the fake
      // test clock would otherwise never complete toByteData).
      final bytes = await tester.runAsync(
        () => MomentShareService.capturePng(boundaryKey, pixelRatio: 1.0),
      );
      expect(bytes, isNotNull);
      expect(bytes!.isNotEmpty, isTrue);
      // PNG magic number: 0x89 'P' 'N' 'G'.
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });
}
