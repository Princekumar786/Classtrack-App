import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../providers/opportunities_providers.dart';
import '../widgets/resource_card.dart';
import 'resource_detail_screen.dart';

/// The student's saved opportunities & deals. Saved items stay available even
/// after their status changes (PRD §15).
class SavedOpportunitiesScreen extends ConsumerWidget {
  const SavedOpportunitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(savedResourcesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off_rounded, size: 48, color: theme.hintColor),
                const SizedBox(height: 12),
                Text("Couldn't load your saved items.",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(savedResourcesProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Refresh'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bookmark_border_rounded,
                        size: 48, color: theme.hintColor),
                    const SizedBox(height: 12),
                    Text('Nothing saved yet', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Tap the bookmark on any opportunity or deal to keep it here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(savedResourcesProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final r = items[i];
                return ResourceCard(
                  resource: r,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      settings: const RouteSettings(name: 'Resource Detail'),
                      builder: (_) => ResourceDetailScreen(resource: r))),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
