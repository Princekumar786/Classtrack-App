import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/cms_analytics.dart';
import '../../domain/marketing.dart';
import '../providers/cms_analytics_providers.dart';
import '../providers/cms_marketing_providers.dart';
import 'cms_sponsor_report_screen.dart';

class CmsCampaignsScreen extends ConsumerWidget {
  const CmsCampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(cmsCampaignsProvider);
    final metrics = {
      for (final m
          in ref.watch(cmsResourceMetricsProvider).valueOrNull ??
              const <ResourceMetric>[])
        m.id: m,
    };

    void openEditor(Campaign? c) => Navigator.of(context).push(
      MaterialPageRoute(settings: const RouteSettings(name: 'Cms Campaign Editor'), builder: (_) => CmsCampaignEditorScreen(existing: c)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 12),
          // Wrap (not Row+Spacer) so the action button drops below the title on
          // narrow/mobile widths instead of overflowing off the right edge.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Text('Campaigns', style: theme.textTheme.headlineSmall),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () => openEditor(null),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New campaign'),
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) =>
                Center(child: Text('Failed to load campaigns.\n$e')),
            data: (campaigns) {
              if (campaigns.isEmpty) {
                return Center(
                  child: Text(
                    'No campaigns yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
                itemCount: campaigns.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = campaigns[i];
                  return InkWell(
                    onTap: () => openEditor(c),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: softCard(context),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.campaign_rounded,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${c.company} · ${Placements.label(c.placement)}'
                                  '${c.isLive() ? ' · live' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.hintColor,
                                  ),
                                ),
                                if (c.resourceId != null &&
                                    metrics[c.resourceId] != null)
                                  _CampaignMetricsRow(
                                    totals: metrics[c.resourceId]!.totals,
                                  ),
                              ],
                            ),
                          ),
                          if (c.resourceId != null &&
                              metrics[c.resourceId] != null)
                            IconButton(
                              tooltip: 'Sponsor report',
                              icon: const Icon(Icons.insights_rounded),
                              onPressed: () {
                                final now = DateTime.now();
                                final start =
                                    c.startDate ??
                                    c.createdAt ??
                                    now.subtract(const Duration(days: 29));
                                var end = c.endDate ?? now;
                                if (end.isAfter(now)) end = now;
                                CmsSponsorReportScreen.openResource(
                                  context,
                                  metrics[c.resourceId]!,
                                  brand: c.company,
                                  campaignWindow: end.isBefore(start)
                                      ? null
                                      : ReportWindow(start, end, c.name),
                                );
                              },
                            ),
                          Text(
                            c.published ? 'Published' : 'Draft',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: c.published
                                  ? AppColors.success
                                  : theme.hintColor,
                            ),
                          ),
                          Switch(
                            value: c.published,
                            onChanged: (v) => ref
                                .read(cmsMarketingRepositoryProvider)
                                ?.setCampaignPublished(c.id, v),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              final ok = await _confirm(context, c.name);
                              if (ok) {
                                await ref
                                    .read(cmsMarketingRepositoryProvider)
                                    ?.deleteCampaign(c.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<bool> _confirm(BuildContext context, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete campaign?'),
        content: Text('Delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

class CmsCampaignEditorScreen extends ConsumerStatefulWidget {
  final Campaign? existing;
  const CmsCampaignEditorScreen({super.key, this.existing});

  @override
  ConsumerState<CmsCampaignEditorScreen> createState() =>
      _CmsCampaignEditorScreenState();
}

class _CmsCampaignEditorScreenState
    extends ConsumerState<CmsCampaignEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _name = TextEditingController();
  final _resourceId = TextEditingController();
  final _countries = TextEditingController();
  final _audience = TextEditingController();
  final _priority = TextEditingController(text: '0');
  String _placement = Placements.home;
  bool _sponsored = true;
  bool _published = false;
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) {
      _company.text = c.company;
      _name.text = c.name;
      _resourceId.text = c.resourceId ?? '';
      _countries.text = c.countries.join(', ');
      _audience.text = c.targetAudience ?? '';
      _priority.text = c.priority.toString();
      _placement = c.placement;
      _sponsored = c.sponsored;
      _published = c.published;
      _start = c.startDate;
      _end = c.endDate;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _company,
      _name,
      _resourceId,
      _countries,
      _audience,
      _priority,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _nn(String s) => s.trim().isEmpty ? null : s.trim();
  List<String> _list(String s) =>
      s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(cmsMarketingRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await repo.saveCampaign(
        Campaign(
          id: widget.existing?.id ?? '',
          company: _company.text.trim(),
          name: _name.text.trim(),
          resourceId: _nn(_resourceId.text),
          countries: _list(_countries.text),
          targetAudience: _nn(_audience.text),
          priority: int.tryParse(_priority.text.trim()) ?? 0,
          placement: _placement,
          sponsored: _sponsored,
          published: _published,
          startDate: _start,
          endDate: _end,
          createdAt: widget.existing?.createdAt,
        ),
      );
      messenger.showSnackBar(const SnackBar(content: Text('Saved ✓')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New campaign' : 'Edit campaign'),
      ),
      bottomNavigationBar: CmsSaveBar(
        saving: _saving,
        isNew: widget.existing == null,
        label: 'campaign',
        onSave: _saving ? null : _save,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TextFormField(
                  controller: _company,
                  decoration: const InputDecoration(labelText: 'Company'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Campaign name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _resourceId,
                  decoration: const InputDecoration(
                    labelText: 'Linked resource id (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _placement,
                  decoration: const InputDecoration(labelText: 'Placement'),
                  items: [
                    for (final p in Placements.all)
                      DropdownMenuItem(
                        value: p,
                        child: Text(Placements.label(p)),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _placement = v ?? _placement),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _countries,
                  decoration: const InputDecoration(
                    labelText: 'Countries (comma-separated; "Global" = all)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _audience,
                  decoration: const InputDecoration(
                    labelText: 'Target audience',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priority,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Priority'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DateTile(
                        label: 'Start',
                        value: _start,
                        onPick: (d) => setState(() => _start = d),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateTile(
                        label: 'End',
                        value: _end,
                        onPick: (d) => setState(() => _end = d),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sponsored'),
                  value: _sponsored,
                  onChanged: (v) => setState(() => _sponsored = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Published'),
                  value: _published,
                  onChanged: (v) => setState(() => _published = v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onPick;
  const _DateTile({
    required this.label,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_rounded, size: 18)
              : IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () => onPick(null),
                ),
        ),
        child: Text(
          value == null
              ? 'Not set'
              : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }
}

/// Compact performance readout for a campaign's promoted resource, using the
/// real per-resource engagement counters (all-time). Honest proxy — attributed
/// to the linked resource, not synthetic campaign numbers.
class _CampaignMetricsRow extends StatelessWidget {
  final MetricTotals totals;
  const _CampaignMetricsRow({required this.totals});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget chip(IconData icon, String label, int value) => Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.hintColor),
          const SizedBox(width: 3),
          Text(
            '$value',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        children: [
          chip(Icons.visibility_outlined, 'impressions', totals.impressions),
          chip(Icons.visibility_rounded, 'views', totals.views),
          chip(Icons.ads_click_rounded, 'clicks', totals.clicks),
          chip(Icons.bookmark_rounded, 'saves', totals.saves),
        ],
      ),
    );
  }
}
