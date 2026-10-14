import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/audit_format.dart';
import '../../domain/audit_log.dart';
import '../providers/cms_admin_providers.dart';

/// Read-only audit trail of privileged CMS actions (admins only).
class CmsAuditLogsScreen extends ConsumerWidget {
  const CmsAuditLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(auditLogsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
          child: Text('Audit logs', style: theme.textTheme.headlineSmall),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) => Center(
              child: Text(
                'Failed to load audit logs.\n$e',
                textAlign: TextAlign.center,
              ),
            ),
            data: (entries) {
              if (entries.isEmpty) {
                return Center(
                  child: Text(
                    'No audit entries yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _AuditRow(entry: entries[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AuditRow extends StatelessWidget {
  final AuditLogEntry entry;
  const _AuditRow({required this.entry});

  IconData get _icon {
    if (entry.action.contains('role'))
      return Icons.admin_panel_settings_rounded;
    if (entry.action.contains('resource')) return Icons.inventory_2_rounded;
    if (entry.action.contains('banner')) return Icons.view_carousel_rounded;
    if (entry.action.contains('campaign')) return Icons.campaign_rounded;
    return Icons.receipt_long_rounded;
  }

  String _time(DateTime? t) {
    if (t == null) return '';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headline = auditHeadline(entry);
    final transition = auditStatusTransition(entry);
    final actor = auditActor(entry);
    return InkWell(
      onTap: () => _showRaw(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: softCard(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(_icon, color: AppColors.primary, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (transition != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          transition,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'by $actor',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _time(entry.at),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Raw entry (ids + all details) for debugging — kept accessible on tap.
  void _showRaw(BuildContext context) {
    final raw = <String, dynamic>{
      'action': entry.action,
      'target': '${entry.targetType} ${entry.targetId}',
      'actorUid': entry.actorUid,
      'actorRole': entry.actorRole,
      if (entry.actorEmail != null) 'actorEmail': entry.actorEmail,
      ...entry.details,
    };
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Audit entry'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in raw.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('${e.key}: ${e.value}'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
