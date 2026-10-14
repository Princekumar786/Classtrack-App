import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/analytics_service.dart';
import '../../data/import_draft_store.dart';
import '../screens/review_screen.dart';

/// "You have an unsaved imported timetable" card with Review / Discard.
/// Renders nothing when there is no draft. Shown on Home and on the import
/// screen so a scan interrupted by the app closing can be finished.
class ImportDraftBanner extends ConsumerWidget {
  final EdgeInsetsGeometry padding;
  const ImportDraftBanner({super.key, this.padding = EdgeInsets.zero});

  static String _ago(DateTime savedAt, DateTime now) {
    final d = now.difference(savedAt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    final days = d.inDays;
    return days == 1 ? 'yesterday' : '$days days ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(importDraftProvider);
    if (draft == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final n = draft.subjectCount;
    final what = n > 0
        ? '$n subject${n == 1 ? '' : 's'}'
        : '${draft.schedule.tasks.length} item'
            '${draft.schedule.tasks.length == 1 ? '' : 's'}';

    return Padding(
      padding: padding,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.pending_actions_rounded,
                  color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Finish your timetable import',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 34),
              child: Text(
                'You scanned $what ${_ago(draft.savedAt, DateTime.now())} '
                'but didn’t save it yet.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => _discard(context, ref),
                  child: const Text('Discard'),
                ),
                TextButton.icon(
                  onPressed: () {
                    ref.read(analyticsProvider).log('import_draft_resumed');
                    Navigator.of(context).push(MaterialPageRoute(
                        settings: const RouteSettings(name: 'Review'),
                        builder: (_) =>
                            ReviewScreen(schedule: draft.schedule)));
                  },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Review & save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard this import?'),
        content: const Text(
            'The scanned timetable will be deleted. You would need to scan it '
            'again to add it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard')),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(analyticsProvider).log('import_draft_discarded');
    await ref.read(importDraftProvider.notifier).clear();
  }
}
