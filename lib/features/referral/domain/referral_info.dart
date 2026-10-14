import '../../../core/constants/app_constants.dart';

/// The caller's referral state, returned by the `getReferralInfo` Cloud
/// Function. All fields are server-owned — the client only ever reads them.
///
/// Reward rule: every [milestoneSize] friends who join with your code earn
/// you [milestoneDays] of Pro (5 friends → 7 days). A friend who joins with a
/// code gets [rewardDays] once as a welcome gift.
class ReferralInfo {
  /// The user's own shareable invite code (e.g. "K7P2QM9").
  final String code;

  /// How many friends have successfully joined with this user's code.
  final int referralCount;

  /// The referrer uid this user redeemed, if any. Non-null once they've
  /// accepted an invite (each account may redeem only once).
  final String? referredBy;

  /// Free Pro days a FRIEND gets for joining with a code (welcome gift).
  final int rewardDays;

  /// Friends needed per reward for the inviter.
  final int milestoneSize;

  /// Pro days the inviter earns for every [milestoneSize] friends.
  final int milestoneDays;

  const ReferralInfo({
    required this.code,
    required this.referralCount,
    required this.referredBy,
    this.rewardDays = AppConstants.referralWelcomeDays,
    this.milestoneSize = AppConstants.referralMilestoneSize,
    this.milestoneDays = AppConstants.referralMilestoneDays,
  });

  bool get hasRedeemed => referredBy != null;

  int get _size => milestoneSize < 1 ? 1 : milestoneSize;

  /// Completed groups of friends (each one earned [milestoneDays]).
  int get milestonesReached => referralCount < 0 ? 0 : referralCount ~/ _size;

  /// Total Pro days this user has earned by inviting friends.
  int get earnedDays => milestonesReached * milestoneDays;

  /// Friends joined towards the NEXT reward (0..milestoneSize-1).
  int get inCurrentCycle => referralCount < 0 ? 0 : referralCount % _size;

  /// Friends still needed for the next reward (1..milestoneSize).
  int get friendsToNextReward => _size - inCurrentCycle;

  /// 0..1 progress towards the next reward.
  double get cycleProgress => inCurrentCycle / _size;

  factory ReferralInfo.fromMap(Map<String, dynamic> map) {
    int read(String k, int fallback) =>
        (map[k] as num?)?.toInt() ?? fallback;
    return ReferralInfo(
      code: (map['code'] as String?) ?? '',
      referralCount: read('referralCount', 0),
      referredBy: map['referredBy'] as String?,
      rewardDays: read('rewardDays', AppConstants.referralWelcomeDays),
      milestoneSize: read('milestoneSize', AppConstants.referralMilestoneSize),
      milestoneDays: read('milestoneDays', AppConstants.referralMilestoneDays),
    );
  }

  ReferralInfo copyWith({int? referralCount, String? referredBy}) => ReferralInfo(
        code: code,
        referralCount: referralCount ?? this.referralCount,
        referredBy: referredBy ?? this.referredBy,
        rewardDays: rewardDays,
        milestoneSize: milestoneSize,
        milestoneDays: milestoneDays,
      );
}
