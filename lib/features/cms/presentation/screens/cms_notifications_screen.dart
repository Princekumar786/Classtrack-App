import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/push_deep_link.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../auth/domain/profile_options.dart';
import '../../../opportunities/domain/resource.dart';
import '../../domain/cms_notification.dart';
import '../providers/cms_marketing_providers.dart';
import '../providers/cms_resource_providers.dart';

/// Compose and send targeted push notifications. Composing enqueues a doc that
/// the `sendQueuedNotification` Cloud Function delivers to the target topic.
class CmsNotificationsScreen extends ConsumerStatefulWidget {
  const CmsNotificationsScreen({super.key});

  @override
  ConsumerState<CmsNotificationsScreen> createState() =>
      _CmsNotificationsScreenState();
}

class _CmsNotificationsScreenState
    extends ConsumerState<CmsNotificationsScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _payload = TextEditingController();
  String? _country; // null = all
  Resource? _linked; // post the push opens, if any
  bool _sending = false;

  /// Links the push to [r]: sets the payload and pre-fills empty title/body.
  void _onLinkSelected(Resource? r) {
    setState(() {
      _linked = r;
      if (r == null) {
        _payload.clear();
        return;
      }
      _payload.text = PushDeepLink.forResource(r.id);
      if (_title.text.trim().isEmpty) _title.text = r.title;
      if (_body.text.trim().isEmpty && r.organization.isNotEmpty) {
        _body.text = '${r.type.label} by ${r.organization} — tap to view.';
      }
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _payload.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final repo = ref.read(cmsMarketingRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Title and message are required.')),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await repo.enqueueNotification(
        title: _title.text.trim(),
        body: _body.text.trim(),
        country: _country,
        payload: _payload.text.trim(),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Queued for delivery ✓')),
      );
      _title.clear();
      _body.clear();
      _payload.clear();
      setState(() {
        _country = null;
        _linked = null;
      });
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not queue: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = ref.watch(cmsNotificationsProvider);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Text('Notifications', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Send a targeted push. Leave country as "All" to broadcast to '
              'everyone. Avoid over-notifying.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: softCard(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _body,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _country,
                    decoration: const InputDecoration(
                      labelText: 'Target country',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All (broadcast)'),
                      ),
                      for (final c in ProfileOptions.countries)
                        DropdownMenuItem<String?>(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() => _country = v),
                  ),
                  const SizedBox(height: 12),
                  _ResourceLinkPicker(
                    selected: _linked,
                    onSelected: _onLinkSelected,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _payload,
                    onChanged: (_) {
                      // Manual edit detaches the picked resource.
                      if (_linked != null &&
                          _payload.text.trim() !=
                              PushDeepLink.forResource(_linked!.id)) {
                        setState(() => _linked = null);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Deep-link payload (optional)',
                      hintText: 'resource:<id>  or  tab:explore',
                      helperText:
                          'Filled automatically when you pick a post above.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final counts = ref
                          .watch(audienceCountsProvider)
                          .valueOrNull;
                      final est = counts?.estimate(country: _country);
                      return Row(
                        children: [
                          const Icon(
                            Icons.groups_rounded,
                            size: 16,
                            color: AppColors.info,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              est == null
                                  ? 'Estimated recipients: …'
                                  : _country == null
                                  ? 'Estimated recipients: ~$est (everyone)'
                                  : 'Estimated recipients: ~$est in $_country',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.hintColor,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: const Text('Send notification'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('Recent', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            history.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => Text('Failed to load history: $e'),
              data: (items) {
                if (items.isEmpty) {
                  return Text(
                    'No notifications sent yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  );
                }
                return Column(
                  children: [for (final n in items) _HistoryRow(n: n)],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final CmsNotification n;
  const _HistoryRow({required this.n});

  Color _statusColor() {
    switch (n.status) {
      case 'sent':
        return AppColors.success;
      case 'failed':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: softCard(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${n.country ?? 'All'}${n.topic != null ? ' · ${n.topic}' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _statusColor().withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              n.status,
              style: TextStyle(
                color: _statusColor(),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search-as-you-type picker for the opportunity / discount a push opens.
/// Only student-visible (published, non-expired) posts are offered, since a
/// link to a draft would land users on an "unavailable" message.
class _ResourceLinkPicker extends ConsumerWidget {
  final Resource? selected;
  final ValueChanged<Resource?> onSelected;
  const _ResourceLinkPicker({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = selected;
    if (s != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(s.type.icon, color: s.type.color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Opens: ${s.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${s.type.label}'
                    '${s.organization.isNotEmpty ? ' · ${s.organization}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove link',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => onSelected(null),
            ),
          ],
        ),
      );
    }

    final all = ref.watch(cmsResourcesProvider).valueOrNull ?? const [];
    final options = all.where((r) => r.isVisibleToStudents).toList();
    return Autocomplete<Resource>(
      displayStringForOption: (r) => r.title,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return options.take(20);
        return options
            .where(
              (r) =>
                  r.title.toLowerCase().contains(q) ||
                  r.organization.toLowerCase().contains(q) ||
                  r.type.label.toLowerCase().contains(q),
            )
            .take(20);
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
        controller: controller,
        focusNode: focusNode,
        decoration: const InputDecoration(
          labelText: 'Link to a post (optional)',
          hintText: 'Search opportunities & discounts, e.g. "SAP"',
          prefixIcon: Icon(Icons.link_rounded),
        ),
      ),
      optionsViewBuilder: (context, onSelect, results) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 640),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final r in results)
                  ListTile(
                    dense: true,
                    leading: Icon(r.type.icon, color: r.type.color),
                    title: Text(
                      r.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${r.type.label}'
                      '${r.organization.isNotEmpty ? ' · ${r.organization}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelect(r),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
