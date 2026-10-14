import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../opportunities/domain/resource.dart';
import '../../data/file_download.dart';
import '../../domain/cms_export.dart';
import '../../domain/cms_metrics.dart';
import '../../domain/cms_role.dart';
import '../providers/cms_resource_providers.dart';

/// CMS landing page: a live overview of the content library (real counts from
/// the `resources` stream) plus a compact summary of what this role can manage.
class CmsDashboardScreen extends ConsumerWidget {
  final CmsRole role;
  const CmsDashboardScreen({super.key, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(cmsResourcesProvider);

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Text('Dashboard', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          'Signed in as ${role.label}. Here\'s an overview of your content.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 24),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, __) => _ErrorCard(message: '$e'),
          data: (resources) {
            final m = computeContentMetrics(resources);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (resources.isNotEmpty && canDownloadFiles)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton.icon(
                        onPressed: () => _exportCsv(context, resources),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('Export CSV'),
                      ),
                    ),
                  ),
                _KpiWrap(metrics: m),
                const SizedBox(height: 24),
                if (m.total > 0) ...[
                  Text(
                    'Content by type',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TypeBreakdown(metrics: m),
                  const SizedBox(height: 24),
                ],
                Text(
                  'Your access',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _AccessGrid(role: role),
              ],
            );
          },
        ),
      ],
    );
  }

  void _exportCsv(BuildContext context, List<Resource> resources) {
    final csv = buildResourcesCsv(resources);
    final stamp = DateTime.now().toIso8601String().split('T').first;
    downloadTextFile('resources-$stamp.csv', 'text/csv;charset=utf-8', csv);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported ${resources.length} resources to CSV ✓'),
      ),
    );
  }
}

class _KpiWrap extends StatelessWidget {
  final CmsContentMetrics metrics;
  const _KpiWrap({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final cards = <Widget>[
      _KpiCard(
        label: 'Total resources',
        value: m.total,
        icon: Icons.inventory_2_rounded,
        color: AppColors.primary,
      ),
      _KpiCard(
        label: 'Published',
        value: m.published,
        icon: Icons.public_rounded,
        color: AppColors.success,
      ),
      _KpiCard(
        label: 'Drafts',
        value: m.drafts,
        icon: Icons.edit_note_rounded,
        color: AppColors.info,
      ),
      _KpiCard(
        label: 'Expiring ≤ 7 days',
        value: m.expiringSoon,
        icon: Icons.schedule_rounded,
        color: AppColors.warning,
        highlight: m.expiringSoon > 0,
      ),
      _KpiCard(
        label: 'Archived',
        value: m.archived,
        icon: Icons.archive_rounded,
        color: AppColors.cancelled,
      ),
      _KpiCard(
        label: 'Sponsored',
        value: m.sponsored,
        icon: Icons.star_rounded,
        color: AppColors.accent,
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth > 1000 ? 3 : (c.maxWidth > 620 ? 2 : 1);
        final w = (c.maxWidth - (cols - 1) * 16) / cols;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [for (final card in cards) SizedBox(width: w, child: card)],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool highlight;
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: softCard(context).copyWith(
        border: highlight ? Border.all(color: color, width: 1.4) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBreakdown extends StatelessWidget {
  final CmsContentMetrics metrics;
  const _TypeBreakdown({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = metrics.topTypes.take(6).toList();
    final maxVal = top.isEmpty
        ? 1
        : top.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: softCard(context),
      child: Column(
        children: [
          for (final e in top)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(e.key.icon, size: 18, color: e.key.color),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 150,
                    child: Text(
                      e.key.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: e.value / maxVal,
                        minHeight: 8,
                        backgroundColor: theme.dividerColor,
                        color: e.key.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${e.value}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AccessGrid extends StatelessWidget {
  final CmsRole role;
  const _AccessGrid({required this.role});

  @override
  Widget build(BuildContext context) {
    final caps = <(String, IconData, bool)>[
      ('Manage content', Icons.inventory_2_rounded, role.canEditContent),
      ('Moderate reports', Icons.flag_rounded, role.canModerate),
      ('Marketing & banners', Icons.campaign_rounded, role.canManageMarketing),
      ('View analytics', Icons.insights_rounded, role.canViewAnalytics),
      ('Manage users', Icons.group_rounded, role.canManageUsers),
      ('Audit logs', Icons.receipt_long_rounded, role.canViewAuditLogs),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth > 900
            ? 3
            : (constraints.maxWidth > 560 ? 2 : 1);
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 3.4,
          children: [
            for (final (label, icon, enabled) in caps)
              _CapabilityCard(label: label, icon: icon, enabled: enabled),
          ],
        );
      },
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  const _CapabilityCard({
    required this.label,
    required this.icon,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled ? AppColors.primary : theme.hintColor;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: softCard(context),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              enabled ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
              size: 18,
              color: enabled ? AppColors.success : theme.hintColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: softCard(context),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Could not load content metrics.\n$message',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
