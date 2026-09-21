import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../opportunities/domain/recommendation_weights.dart';
import '../../../opportunities/presentation/providers/opportunities_providers.dart';
import '../providers/cms_config_providers.dart';

/// CMS Settings — recommendation engine weights (PRD §12), editable by admins.
/// These are stored at `config/recommendation` and read live by the app's
/// personalization scoring (Phase 6).
class CmsSettingsScreen extends ConsumerStatefulWidget {
  const CmsSettingsScreen({super.key});

  @override
  ConsumerState<CmsSettingsScreen> createState() => _CmsSettingsScreenState();
}

class _CmsSettingsScreenState extends ConsumerState<CmsSettingsScreen> {
  final _c = <String, TextEditingController>{};
  bool _seeded = false;
  bool _saving = false;

  static const _fields = <(String, String)>[
    ('countryMatch', 'Country match'),
    ('degreeMatch', 'Degree match'),
    ('departmentMatch', 'Department match'),
    ('interestMatch', 'Interest match'),
    ('careerGoal', 'Career goal match'),
    ('deadlineRelevance', 'Deadline relevance'),
    ('freshness', 'Freshness'),
  ];

  void _seed(RecommendationWeights w) {
    if (_seeded) return;
    _seeded = true;
    final m = w.toMap();
    for (final (key, _) in _fields) {
      _c[key] = TextEditingController(text: (m[key] ?? 0).toString());
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  RecommendationWeights _current() {
    int v(String k) => int.tryParse(_c[k]?.text.trim() ?? '') ?? 0;
    return RecommendationWeights(
      countryMatch: v('countryMatch'),
      degreeMatch: v('degreeMatch'),
      departmentMatch: v('departmentMatch'),
      academicYear: v('academicYear'),
      interestMatch: v('interestMatch'),
      careerGoal: v('careerGoal'),
      deadlineRelevance: v('deadlineRelevance'),
      freshness: v('freshness'),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(cmsConfigRepositoryProvider)
          .saveRecommendationWeights(_current());
      messenger.showSnackBar(const SnackBar(content: Text('Weights saved ✓')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(recommendationWeightsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => Center(child: Text('Failed to load settings.\n$e')),
      data: (w) {
        _seed(w);
        final total = _current().maxScore;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                Text('Settings', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Recommendation weights. The final match score is normalized '
                  'against the total, so relative sizes are what matter.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.hintColor),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: softCard(context),
                  child: Column(
                    children: [
                      for (final (key, label) in _fields)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Expanded(child: Text(label)),
                              SizedBox(
                                width: 100,
                                child: TextField(
                                  controller: _c[key],
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  textAlign: TextAlign.center,
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                      isDense: true, border: OutlineInputBorder()),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Total (max raw score)',
                                style: theme.textTheme.titleSmall),
                          ),
                          Text('$total',
                              style: theme.textTheme.titleMedium?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(48)),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_rounded),
                  label: const Text('Save weights'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
