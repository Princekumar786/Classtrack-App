import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/cms_category.dart';
import '../providers/cms_category_providers.dart';

/// Manage the content taxonomy: create / rename / enable-disable / order
/// categories for opportunities and discounts. Disabling (not deleting) is the
/// safe default so existing resource references never break.
class CmsCategoriesScreen extends ConsumerWidget {
  const CmsCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(cmsCategoriesProvider);

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
              Text('Categories', style: theme.textTheme.headlineSmall),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () => _editDialog(context, ref, null),
                icon: const Icon(Icons.add_rounded),
                label: const Text('New category'),
              ),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, __) => Center(
              child: Text(
                'Failed to load categories.\n$e',
                textAlign: TextAlign.center,
              ),
            ),
            data: (all) {
              if (all.isEmpty) {
                return Center(
                  child: Text(
                    'No categories yet. Create your first one.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
                children: [
                  for (final kind in CategoryKind.values) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Text(
                        '${kind.label} categories',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ...() {
                      final rows = sortedCategories(
                        all.where((c) => c.kind == kind).toList(),
                      );
                      if (rows.isEmpty) {
                        return [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'None yet.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.hintColor,
                              ),
                            ),
                          ),
                        ];
                      }
                      return rows.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _CategoryRow(
                            category: c,
                            onEdit: () => _editDialog(context, ref, c),
                            onToggle: (v) => ref
                                .read(cmsCategoryRepositoryProvider)
                                ?.setEnabled(c.id, v),
                            onDelete: () => _confirmDelete(context, ref, c),
                          ),
                        ),
                      );
                    }(),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _editDialog(
    BuildContext context,
    WidgetRef ref,
    CmsCategory? existing,
  ) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final sortCtrl = TextEditingController(
      text: (existing?.sort ?? 0).toString(),
    );
    var kind = existing?.kind ?? CategoryKind.opportunity;
    final repo = ref.read(cmsCategoryRepositoryProvider);
    if (repo == null) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New category' : 'Edit category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CategoryKind>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Applies to'),
                items: [
                  for (final k in CategoryKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (v) => setLocal(() => kind = v ?? kind),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sortCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sort order (lower shows first)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final sort = int.tryParse(sortCtrl.text.trim()) ?? 0;
    if (existing == null) {
      await repo.create(
        CmsCategory(id: '', name: name, slug: '', kind: kind, sort: sort),
      );
    } else {
      await repo.update(existing.copyWith(name: name, kind: kind, sort: sort));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CmsCategory c,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${c.name}"?'),
        content: const Text(
          'Deleting removes the category entirely. If resources still use it, '
          'prefer Disable (toggle) instead — it hides the category from '
          'pickers without breaking existing references.',
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
    if (ok == true) {
      await ref.read(cmsCategoryRepositoryProvider)?.delete(c.id);
    }
  }
}

class _CategoryRow extends StatelessWidget {
  final CmsCategory category;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  const _CategoryRow({
    required this.category,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = category;
    return Opacity(
      opacity: c.enabled ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        decoration: softCard(context),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '#${c.sort}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    c.slug,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              c.enabled ? 'Enabled' : 'Disabled',
              style: theme.textTheme.labelSmall?.copyWith(
                color: c.enabled ? AppColors.success : theme.hintColor,
              ),
            ),
            Switch(value: c.enabled, onChanged: onToggle),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
