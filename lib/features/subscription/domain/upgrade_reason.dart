import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/domain/profile_avatars.dart';
import 'pro_constants.dart';

/// Why the student is being asked to upgrade. Every free-tier limit and Pro
/// gate in the app maps to exactly one reason, so the upgrade prompt and the
/// pricing page can speak to what they were actually trying to do.
enum UpgradeReason {
  aiChat,
  timetableScans,
  learningPlans,
  opportunities,
  insights,
  dailySummary,
  smartNotes,
  export,
  avatars,
  accentColor,
  calendarSync,
  semesters,
  general;

  UpgradeCopy get copy => _copy[this]!;

  /// Stable id for analytics.
  String get id => name;
}

/// Presentation for one [UpgradeReason].
class UpgradeCopy {
  const UpgradeCopy({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.paywallHeadline,
    required this.highlight,
    this.limit,
    this.limitUnit,
    this.resets,
  });

  final IconData icon;
  final Color color;

  /// Prompt title, e.g. "You've used your free AI messages".
  final String title;

  /// One or two sentences explaining what happened and what Pro changes.
  final String message;

  /// Pricing-page headline tailored to this reason.
  final String paywallHeadline;

  /// The single Pro benefit that answers this reason (shown highlighted).
  final String highlight;

  /// Free allowance size for limit reasons (null = a Pro-only feature).
  final int? limit;

  /// Unit for the usage meter, e.g. "messages".
  final String? limitUnit;

  /// How the allowance resets: 'month' or null (never — lifetime).
  final String? resets;

  bool get isLimit => limit != null;
}

const _ai = Color(0xFF7C6CF0);

final Map<UpgradeReason, UpgradeCopy> _copy = {
  UpgradeReason.aiChat: const UpgradeCopy(
    icon: Icons.auto_awesome_rounded,
    color: _ai,
    title: 'You’ve used your free AI messages',
    message: 'Free includes ${ProConstants.freeMonthlyChatLimit} AI messages a '
        'month. Pro gives you unlimited questions, planning and study help.',
    paywallHeadline: 'Keep the conversation going',
    highlight: 'Unlimited AI assistant — no monthly cap',
    limit: ProConstants.freeMonthlyChatLimit,
    limitUnit: 'messages',
    resets: 'month',
  ),
  UpgradeReason.timetableScans: const UpgradeCopy(
    icon: Icons.document_scanner_rounded,
    color: AppColors.info,
    title: 'You’ve used your free scans',
    message: 'Free includes 2 AI timetable scans. Pro lets you import from a '
        'photo, PDF or text as often as you like. Manual entry stays free.',
    paywallHeadline: 'Import every timetable in seconds',
    highlight: 'Unlimited timetable scans from a photo, PDF or text',
    limit: 2,
    limitUnit: 'scans',
  ),
  UpgradeReason.learningPlans: const UpgradeCopy(
    icon: Icons.route_rounded,
    color: AppColors.success,
    title: 'You’ve used your free study plans',
    message: 'Free includes 2 learning plans. Pro unlocks unlimited plans with '
        'AI-tailored roadmaps for every subject.',
    paywallHeadline: 'A study plan for every subject',
    highlight: 'Unlimited AI learning plans',
    limit: 2,
    limitUnit: 'plans',
  ),
  UpgradeReason.opportunities: const UpgradeCopy(
    icon: Icons.explore_rounded,
    color: AppColors.accent,
    title: 'See every opportunity',
    message: 'Free shows the latest few. Pro opens the full library of '
        'scholarships, internships and student perks — with search and filters.',
    paywallHeadline: 'Never miss a scholarship or perk',
    highlight: 'The full opportunities & perks library',
  ),
  UpgradeReason.insights: const UpgradeCopy(
    icon: Icons.insights_rounded,
    color: AppColors.primary,
    title: 'Insights are a Pro feature',
    message: 'See attendance forecasts, safe-skip counts, spending projections '
        'and grade trends built from your own data.',
    paywallHeadline: 'Know where your semester is heading',
    highlight: 'Insights & predictions',
  ),
  UpgradeReason.dailySummary: const UpgradeCopy(
    icon: Icons.today_rounded,
    color: AppColors.coral,
    title: 'Daily summary is a Pro feature',
    message: 'Get an AI briefing of your day — classes, deadlines and exams — '
        'and download it as a PDF.',
    paywallHeadline: 'Start every day prepared',
    highlight: 'AI daily agenda summary',
  ),
  UpgradeReason.smartNotes: const UpgradeCopy(
    icon: Icons.sticky_note_2_rounded,
    color: AppColors.accent,
    title: 'Smart notes are a Pro feature',
    message: 'Add links, images, PDFs and flashcards to your lecture notes.',
    paywallHeadline: 'Notes that help you study',
    highlight: 'Smart lecture notes with attachments & flashcards',
  ),
  UpgradeReason.export: const UpgradeCopy(
    icon: Icons.ios_share_rounded,
    color: AppColors.info,
    title: 'Export is a Pro feature',
    message: 'Export attendance and your schedule to PDF, CSV or your calendar.',
    paywallHeadline: 'Take your data anywhere',
    highlight: 'PDF, CSV & calendar export',
  ),
  UpgradeReason.avatars: UpgradeCopy(
    icon: Icons.face_retouching_natural_rounded,
    color: const Color(0xFFEC4899),
    title: 'Unlock every character',
    message: 'Free includes ${ProfileAvatars.freeCount} characters. Pro unlocks '
        'all ${ProfileAvatars.all.length}.',
    paywallHeadline: 'Make ClassTrack yours',
    highlight: 'All ${ProfileAvatars.all.length} profile characters',
  ),
  UpgradeReason.accentColor: const UpgradeCopy(
    icon: Icons.palette_rounded,
    color: Color(0xFFEC4899),
    title: 'Custom colours are a Pro feature',
    message: 'Personalise ClassTrack with your own accent colour.',
    paywallHeadline: 'Make ClassTrack yours',
    highlight: 'Custom accent colours',
  ),
  UpgradeReason.calendarSync: const UpgradeCopy(
    icon: Icons.sync_rounded,
    color: AppColors.success,
    title: 'Auto-sync is a Pro feature',
    message: 'Import your Google Calendar events and tasks automatically every '
        'day — no duplicates.',
    paywallHeadline: 'Your calendar, always in sync',
    highlight: 'Daily Google Calendar & Tasks auto-sync',
  ),
  UpgradeReason.semesters: const UpgradeCopy(
    icon: Icons.inventory_2_rounded,
    color: AppColors.primary,
    title: 'Semester wrap-up is a Pro feature',
    message: 'Wrap up a semester to save its subjects, marks, exams and '
        'attendance, start the next one fresh, and track your SGPA and CGPA '
        'over time.',
    paywallHeadline: 'Every semester, saved and counted',
    highlight: 'Semester wrap-up, past semesters & CGPA',
  ),
  UpgradeReason.general: const UpgradeCopy(
    icon: Icons.workspace_premium_rounded,
    color: AppColors.primary,
    title: 'Upgrade to ClassTrack Pro',
    message: 'Unlimited AI, timetable scans, insights, exports and more.',
    paywallHeadline: 'Unlock your best semester yet',
    highlight: 'Everything in ClassTrack, unlocked',
  ),
};

/// "Resets on 1 Nov" for a monthly allowance (local time), else null.
String? resetLabel(UpgradeCopy copy, DateTime now) {
  if (copy.resets != 'month') return null;
  final next = DateTime(now.year, now.month + 1, 1);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return 'Resets on 1 ${months[next.month - 1]}';
}

/// One row of the Free-vs-Pro comparison ("WHY PRO?") on the pricing page.
///
/// Cell values: `null` = not included (✗), [included] = included (✓), any
/// other text is shown as-is (e.g. "10 / month", "Unlimited").
class PlanComparisonRow {
  const PlanComparisonRow(
    this.feature,
    this.free,
    this.pro, {
    required this.icon,
    required this.color,
    this.reason,
  });

  static const String included = 'Included';

  final String feature;

  /// Free-tier value; null renders as "not included".
  final String? free;
  final String pro;
  final IconData icon;
  final Color color;

  /// The reason this row answers (so it can be highlighted in context).
  final UpgradeReason? reason;
}

const _green = Color(0xFF84CC16);
const _pink = Color(0xFFEC4899);
const _sky = Color(0xFF38BDF8);
const _amber = Color(0xFFF59E0B);

/// Every row of the pricing table. Keep in sync with the real gates
/// (each [UpgradeReason]) — tested in test/paywall_pricing_test.dart.
final List<PlanComparisonRow> planComparison = [
  const PlanComparisonRow('Attendance, timetable & reminders',
      PlanComparisonRow.included, PlanComparisonRow.included,
      icon: Icons.fact_check_rounded, color: _ai),
  const PlanComparisonRow('Grades, exams & GPA', PlanComparisonRow.included,
      PlanComparisonRow.included,
      icon: Icons.school_rounded, color: _green),
  const PlanComparisonRow(
      'AI assistant', '${ProConstants.freeMonthlyChatLimit}/mo', 'Unlimited',
      icon: Icons.auto_awesome_rounded, color: _ai, reason: UpgradeReason.aiChat),
  const PlanComparisonRow('Timetable scans', '2', 'Unlimited',
      icon: Icons.document_scanner_rounded,
      color: _sky,
      reason: UpgradeReason.timetableScans),
  const PlanComparisonRow('AI learning plans', '2', 'Unlimited',
      icon: Icons.route_rounded,
      color: _green,
      reason: UpgradeReason.learningPlans),
  const PlanComparisonRow(
      'Semester wrap-up & CGPA', null, PlanComparisonRow.included,
      icon: Icons.history_edu_rounded,
      color: _amber,
      reason: UpgradeReason.semesters),
  const PlanComparisonRow('Insights & predictions', null, PlanComparisonRow.included,
      icon: Icons.insights_rounded,
      color: _green,
      reason: UpgradeReason.insights),
  const PlanComparisonRow('Daily AI summary', null, PlanComparisonRow.included,
      icon: Icons.today_rounded,
      color: AppColors.coral,
      reason: UpgradeReason.dailySummary),
  const PlanComparisonRow('Smart notes & flashcards', null, PlanComparisonRow.included,
      icon: Icons.sticky_note_2_rounded,
      color: _amber,
      reason: UpgradeReason.smartNotes),
  const PlanComparisonRow('Google Calendar auto-sync', null, PlanComparisonRow.included,
      icon: Icons.sync_rounded,
      color: _sky,
      reason: UpgradeReason.calendarSync),
  const PlanComparisonRow('Scholarships & perks', 'Latest 5', 'All',
      icon: Icons.explore_rounded,
      color: AppColors.accent,
      reason: UpgradeReason.opportunities),
  const PlanComparisonRow('PDF, CSV & calendar export', null, PlanComparisonRow.included,
      icon: Icons.ios_share_rounded,
      color: _sky,
      reason: UpgradeReason.export),
  PlanComparisonRow('Profile characters', '${ProfileAvatars.freeCount}',
      '${ProfileAvatars.all.length}',
      icon: Icons.face_retouching_natural_rounded,
      color: _pink,
      reason: UpgradeReason.avatars),
  const PlanComparisonRow('Custom accent colours', null, PlanComparisonRow.included,
      icon: Icons.palette_rounded,
      color: _pink,
      reason: UpgradeReason.accentColor),
];
