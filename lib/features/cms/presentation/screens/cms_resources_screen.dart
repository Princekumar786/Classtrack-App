import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../opportunities/domain/resource.dart';
import '../../../opportunities/domain/resource_status.dart';
import '../../../opportunities/domain/resource_type.dart';
import '../../domain/cms_role.dart';
import '../providers/cms_resource_providers.dart';
import 'cms_resource_editor_screen.dart';

/// The CMS content library — lists every resource (any status) with search,
/// status/type filters and per-row lifecycle actions. Editing/creating opens
/// the [CmsResourceEditorScreen].
class CmsResourcesScreen extends ConsumerStatefulWidget {
  final CmsRole role;
  const CmsResourcesScreen({super.key, required this.role});

  @override
  ConsumerState<CmsResourcesScreen> createState() => _CmsResourcesScreenState();
}

class _CmsResourcesScreenState extends ConsumerState<CmsResourcesScreen> {
  String _query = '';
  ResourceStatus? _status;
  ResourceType? _type;

  /// Multi-select (bulk actions) state.
  bool _selectionMode = false;
  final Set<String> _selected = {};

  bool _matches(Resource r) {
    if (_status != null && r.status != _status) return false;
    if (_type != null && r.type != _type) return false;
    if (_query.trim().isEmpty) return true;
    final q = _query.toLowerCase();
    return r.title.toLowerCase().contains(q) ||
        r.organization.toLowerCase().contains(q) ||
        (r.company?.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(cmsResourcesProvider);
    final canEdit = widget.role.canEditContent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 8),
          // Wrap (not Row+Spacer) so the action button drops below the title on
          // narrow/mobile widths instead of overflowing off the right edge.
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Text('Resources', style: theme.textTheme.headlineSmall),
              if (canEdit)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => setState(() {
                        _selectionMode = !_selectionMode;
                        if (!_selectionMode) _selected.clear();
                      }),
                      icon: Icon(
                        _selectionMode
                            ? Icons.close_rounded
                            : Icons.checklist_rounded,
                      ),
                      label: Text(_selectionMode ? 'Cancel' : 'Select'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      onPressed: () => _openEditor(context, null),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New resource'),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 4, 28, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search title, organization or company',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: theme.cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _StatusDropdown(
                value: _status,
                onChanged: (s) => setState(() => _status = s),
              ),
              const SizedBox(width: 12),
              _TypeDropdown(
                value: _type,
                onChanged: (t) => setState(() => _type = t),
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) => Center(
              child: Text(
                'Failed to load resources.\n$e',
                textAlign: TextAlign.center,
              ),
            ),
            data: (all) {
              final rows = all.where(_matches).toList();
              if (rows.isEmpty) {
                return Center(
                  child: Text(
                    all.isEmpty
                        ? 'No resources yet. Create your first one.'
                        : 'No resources match your filters.',
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
                itemBuilder: (_, i) => _ResourceRow(
                  resource: rows[i],
                  canEdit: canEdit,
                  selectionMode: _selectionMode,
                  selected: _selected.contains(rows[i].id),
                  onToggle: () => _toggleSelected(rows[i].id),
                  onEdit: () => _openEditor(context, rows[i]),
                  onAction: (a) => _runAction(context, rows[i], a),
                ),
              );
            },
          ),
        ),
        if (_selectionMode && _selected.isNotEmpty) _bulkBar(context),
      ],
    );
  }

  void _toggleSelected(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  Widget _bulkBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                '${_selected.length} selected',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                ),
                onPressed: () => _runBulk(context, _BulkAction.publish),
                icon: const Icon(Icons.publish_rounded, size: 18),
                label: const Text('Publish'),
              ),
              OutlinedButton.icon(
                onPressed: () => _runBulk(context, _BulkAction.archive),
                icon: const Icon(Icons.archive_outlined, size: 18),
                label: const Text('Archive'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                onPressed: () => _runBulk(context, _BulkAction.delete),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runBulk(BuildContext context, _BulkAction action) async {
    final repo = ref.read(cmsResourceRepositoryProvider);
    if (repo == null) return;
    final all =
        ref.read(cmsResourcesProvider).valueOrNull ?? const <Resource>[];
    final targets = all.where((r) => _selected.contains(r.id)).toList();
    if (targets.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    if (action == _BulkAction.delete) {
      final ok = await _confirmBulkDelete(context, targets.length);
      if (!ok) return;
    }
    var done = 0;
    final failed = <String>[];
    for (final r in targets) {
      try {
        switch (action) {
          case _BulkAction.publish:
            await repo.setStatus(r, ResourceStatus.active);
            break;
          case _BulkAction.archive:
            await repo.setStatus(r, ResourceStatus.archived);
            break;
          case _BulkAction.delete:
            await repo.delete(r.id);
            break;
        }
        done++;
      } catch (_) {
        failed.add(r.title);
      }
    }
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selectionMode = false;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? '$done updated ✓'
              : '$done updated · ${failed.length} skipped '
                    '(e.g. "${failed.first}" needs a title, organization & link to publish)',
        ),
      ),
    );
  }

  Future<bool> _confirmBulkDelete(BuildContext context, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count resource${count == 1 ? '' : 's'}?'),
        content: const Text(
          'This permanently deletes the selected resources. Consider '
          'archiving instead to preserve analytics and history.',
        ),
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

  void _openEditor(BuildContext context, Resource? resource) {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'Cms Resource Editor'),
        builder: (_) => CmsResourceEditorScreen(existing: resource),
      ),
    );
  }

  Future<void> _runAction(
    BuildContext context,
    Resource r,
    _RowAction action,
  ) async {
    final repo = ref.read(cmsResourceRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (action) {
        case _RowAction.publish:
          await repo.setStatus(r, ResourceStatus.active);
          messenger.showSnackBar(const SnackBar(content: Text('Published ✓')));
          break;
        case _RowAction.draft:
          await repo.setStatus(r, ResourceStatus.draft);
          messenger.showSnackBar(
            const SnackBar(content: Text('Moved to draft')),
          );
          break;
        case _RowAction.archive:
          await repo.setStatus(r, ResourceStatus.archived);
          messenger.showSnackBar(const SnackBar(content: Text('Archived')));
          break;
        case _RowAction.duplicate:
          await repo.duplicate(r);
          messenger.showSnackBar(
            const SnackBar(content: Text('Duplicated as draft')),
          );
          break;
        case _RowAction.delete:
          final ok = await _confirmDelete(context, r);
          if (ok) {
            await repo.delete(r.id);
            messenger.showSnackBar(const SnackBar(content: Text('Deleted')));
          }
          break;
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is ArgumentError ? e.message.toString() : 'Action failed: $e',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<bool> _confirmDelete(BuildContext context, Resource r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete resource?'),
        content: Text(
          'Permanently delete "${r.title}"? Consider archiving instead to '
          'preserve analytics and history.',
        ),
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

enum _RowAction { publish, draft, archive, duplicate, delete }

enum _BulkAction { publish, archive, delete }

class _ResourceRow extends StatelessWidget {
  final Resource resource;
  final bool canEdit;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final ValueChanged<_RowAction> onAction;
  const _ResourceRow({
    required this.resource,
    required this.canEdit,
    required this.selectionMode,
    required this.selected,
    required this.onToggle,
    required this.onEdit,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = resource;
    final effective = r.effectiveStatus;
    return InkWell(
      onTap: selectionMode ? onToggle : (canEdit ? onEdit : null),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: softCard(context).copyWith(
          border: selected
              ? Border.all(color: AppColors.primary, width: 1.6)
              : null,
        ),
        child: Row(
          children: [
            if (selectionMode) ...[
              Checkbox(value: selected, onChanged: (_) => onToggle()),
              const SizedBox(width: 4),
            ],
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: r.type.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(r.type.icon, color: r.type.color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${r.type.label} · ${r.brandName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (r.sponsored)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: AppColors.accent,
                ),
              ),
            _StatusChip(status: effective, stored: r.status),
            if (canEdit && !selectionMode)
              PopupMenuButton<_RowAction>(
                onSelected: onAction,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _RowAction.publish,
                    child: Text('Publish'),
                  ),
                  PopupMenuItem(
                    value: _RowAction.draft,
                    child: Text('Move to draft'),
                  ),
                  PopupMenuItem(
                    value: _RowAction.archive,
                    child: Text('Archive'),
                  ),
                  PopupMenuItem(
                    value: _RowAction.duplicate,
                    child: Text('Duplicate'),
                  ),
                  PopupMenuItem(
                    value: _RowAction.delete,
                    child: Text('Delete'),
                  ),
                ],
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final ResourceStatus status;
  final ResourceStatus stored;
  const _StatusChip({required this.status, required this.stored});

  @override
  Widget build(BuildContext context) {
    // Show the effective status; if it differs from the stored one (date-driven
    // transition), hint at that with a small dot.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status != stored) ...[
            Icon(Icons.schedule_rounded, size: 11, color: status.color),
            const SizedBox(width: 4),
          ],
          Text(
            status.label,
            style: TextStyle(
              color: status.color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  final ResourceStatus? value;
  final ValueChanged<ResourceStatus?> onChanged;
  const _StatusDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<ResourceStatus?>(
      value: value,
      hint: const Text('Status'),
      onChanged: onChanged,
      items: [
        const DropdownMenuItem(value: null, child: Text('All statuses')),
        for (final s in ResourceStatus.values)
          DropdownMenuItem(value: s, child: Text(s.label)),
      ],
    );
  }
}

class _TypeDropdown extends StatelessWidget {
  final ResourceType? value;
  final ValueChanged<ResourceType?> onChanged;
  const _TypeDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<ResourceType?>(
      value: value,
      hint: const Text('Type'),
      onChanged: onChanged,
      items: [
        const DropdownMenuItem(value: null, child: Text('All types')),
        for (final t in ResourceType.values)
          DropdownMenuItem(value: t, child: Text(t.label)),
      ],
    );
  }
}
