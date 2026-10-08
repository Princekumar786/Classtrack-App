import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classtrack/core/theme/app_icons.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../attendance/domain/attendance_record.dart';
import '../../../attendance/presentation/providers/attendance_providers.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../schedule/domain/class_session.dart';
import '../../../schedule/presentation/providers/schedule_providers.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../subscription/presentation/widgets/upgrade_prompt.dart';
import '../../data/export_service.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  bool _busy = false;

  Future<void> _guard(Future<void> Function() task) async {
    // Exports are a Pro feature.
    if (!await requirePro(context, ref, UpgradeReason.export) || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Export & share')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Calendar', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _tile(
              icon: PhosphorIcons.calendarPlus(),
              title: 'Export schedule (.ics)',
              subtitle: 'Open in Google, Apple or Outlook Calendar',
              onTap: () => _guard(() async {
                final sessionsBySubject = <String, List<ClassSession>>{};
                for (final s in subjects) {
                  sessionsBySubject[s.id] = ref
                          .read(sessionsForSubjectProvider(s.id))
                          .valueOrNull ??
                      const [];
                }
                final now = DateTime.now();
                await ExportService.shareIcs(
                  subjects: subjects,
                  sessionsBySubject: sessionsBySubject,
                  semesterStart: DateTime(now.year, now.month, now.day),
                  semesterEnd: now.add(const Duration(days: 126)),
                );
              }),
            ),
            const SizedBox(height: 20),
            Text('Attendance summary', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _tile(
              icon: PhosphorIcons.filePdf(),
              title: 'Export as PDF',
              subtitle: 'A shareable attendance report',
              onTap: () => _guard(() async {
                await ExportService.sharePdf(
                  userName: ref.read(userProfileProvider).valueOrNull?.displayName ??
                      'Student',
                  subjects: subjects,
                  statsBySubject: _statsMap(subjects),
                  target: ref
                          .read(userProfileProvider)
                          .valueOrNull
                          ?.targetAttendancePercent ??
                      AppConstants.defaultTargetAttendance,
                );
              }),
            ),
            _tile(
              icon: PhosphorIcons.fileCsv(),
              title: 'Export as CSV',
              subtitle: 'Open in Excel or Google Sheets',
              onTap: () => _guard(() async {
                await ExportService.shareCsv(
                  subjects: subjects,
                  statsBySubject: _statsMap(subjects),
                );
              }),
            ),
            if (_busy) ...[
              const SizedBox(height: 28),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  Map<String, AttendanceStats> _statsMap(List subjects) {
    final map = <String, AttendanceStats>{};
    for (final s in subjects) {
      map[s.id] = ref.read(subjectStatsProvider(s.id));
    }
    return map;
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Icon(icon, color: AppColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
