import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/content_report.dart';
import '../providers/report_providers.dart';

/// Moderation queue: student-submitted reports against resources. Moderators
/// can move a report through its lifecycle. Reporter identity is intentionally
/// not surfaced (privacy).
class CmsReportsScreen extends ConsumerStatefulWidget {
  const CmsReportsScreen({super.key});

  @override
  ConsumerState<CmsReportsScreen> createState() => _CmsReportsScreenState();
}

class _CmsReportsScreenState extends ConsumerState<CmsReportsScreen> {
  ReportStatus? _filter; // null = all

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(cmsReportsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Text('Reports', style: theme.textTheme.headlineSmall),
              _StatusFilter(
                value: _filter,
                onChanged: (s) => setState(() => _filter = s),
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) => Center(
              child: Text(
                'Failed to load reports.\n$e',
                textAlign: TextAlign.center,
              ),
            ),
            data: (all) {
              final rows = _filter == null
                  ? all
                  : all.where((r) => r.status == _filter).toList();
              final activeCounts = activeReportCountsByResource(all);
              if (rows.isEmpty) {
                return Center(
                  child: Text(
                    all.isEmpty
                        ? 'No reports yet. Student-submitted reports appear here.'
                        : 'No reports match this filter.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ReportRow(
                  report: rows[i],
                  otherActiveForResource:
                      (activeCounts[rows[i].resourceId] ?? 0) -
                      (rows[i].status.isActive ? 1 : 0),
                  onAction: (s) => _setStatus(rows[i], s),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _setStatus(ContentReport r, ReportStatus status) async {
    final repo = ref.read(reportRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repo.setStatus(r.id, status);
      messenger.showSnackBar(
        SnackBar(content: Text('Marked ${status.label.toLowerCase()}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not update: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}

class _ReportRow extends StatelessWidget {
  final ContentReport report;
  final int otherActiveForResource;
  final ValueChanged<ReportStatus> onAction;
  const _ReportRow({
    required this.report,
    required this.otherActiveForResource,
    required this.onAction,
  });

  Color _statusColor(ReportStatus s) {
    switch (s) {
      case ReportStatus.open:
        return AppColors.warning;
      case ReportStatus.underReview:
        return AppColors.info;
      case ReportStatus.resolved:
        return AppColors.success;
      case ReportStatus.dismissed:
        return AppColors.cancelled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = report;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: softCard(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        r.resourceTitle.isEmpty
                            ? '(resource ${r.resourceId})'
                            : r.resourceTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (otherActiveForResource > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '+$otherActiveForResource more',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  r.reason.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (r.message != null && r.message!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '“${r.message}”',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _statusColor(r.status).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  r.status.label,
                  style: TextStyle(
                    color: _statusColor(r.status),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<ReportStatus>(
                tooltip: 'Update status',
                onSelected: onAction,
                itemBuilder: (_) => [
                  for (final s in ReportStatus.values)
                    if (s != report.status)
                      PopupMenuItem(
                        value: s,
                        child: Text('Mark ${s.label.toLowerCase()}'),
                      ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusFilter extends StatelessWidget {
  final ReportStatus? value;
  final ValueChanged<ReportStatus?> onChanged;
  const _StatusFilter({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<ReportStatus?>(
      value: value,
      hint: const Text('All statuses'),
      onChanged: onChanged,
      items: [
        const DropdownMenuItem(value: null, child: Text('All statuses')),
        for (final s in ReportStatus.values)
          DropdownMenuItem(value: s, child: Text(s.label)),
      ],
    );
  }
}
