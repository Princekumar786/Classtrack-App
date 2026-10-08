import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classtrack/core/theme/app_icons.dart';
import 'package:classtrack/core/theme/subject_icons.dart';

import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../attendance/presentation/providers/attendance_providers.dart';
import '../../../import/presentation/screens/import_screen.dart';
import '../../domain/subject.dart';
import '../providers/subject_providers.dart';
import 'edit_subject_screen.dart';
import 'subject_detail_screen.dart';

class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  void _openEditor(BuildContext context, {Subject? subject}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditSubjectScreen(subject: subject)),
    );
  }

  void _openPhotoImport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ImportScreen()),
    );
  }

  /// Bottom sheet shown when the user taps the "+" FAB: choose between adding a
  /// subject by hand or importing a whole timetable from a photo/PDF/text.
  void _showAddOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text('Add subjects', style: theme.textTheme.titleLarge),
              ),
              ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: const Text('Add subject'),
                subtitle: const Text('Enter a subject and its details by hand'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openEditor(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner_rounded),
                title: const Text('Import through photo'),
                subtitle:
                    const Text('Scan a timetable image, PDF or text with AI'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openPhotoImport(context);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectsAsync = ref.watch(subjectsStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Subjects')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddOptions(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: subjectsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(subjectsStreamProvider),
        ),
        data: (subjects) {
          if (subjects.isEmpty) {
            return EmptyState(
              icon: PhosphorIcons.books(),
              title: 'No subjects yet',
              message:
                  'Add your first subject to start tracking attendance and classes.',
              actionLabel: 'Add subject',
              onAction: () => _openEditor(context),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            itemCount: subjects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final subject = subjects[i];
              return _SubjectCard(subject: subject).listEntrance(i, slide: 0.08);
            },
          );
        },
      ),
    );
  }
}

class _SubjectCard extends ConsumerWidget {
  final Subject subject;
  const _SubjectCard({required this.subject});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(subjectStatsProvider(subject.id));
    final color = Color(subject.colorHex);
    final pct = stats.held == 0 ? null : stats.percent;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SubjectDetailScreen(subjectId: subject.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(SubjectIcons.resolve(subject.iconKey),
                    color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.name,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      subject.professor?.isNotEmpty == true
                          ? subject.professor!
                          : 'Tap to view details',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _MiniPercent(percent: pct),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPercent extends StatelessWidget {
  final double? percent;
  const _MiniPercent({this.percent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (percent == null) {
      return Text('—',
          style: theme.textTheme.titleMedium
              ?.copyWith(color: theme.textTheme.bodySmall?.color));
    }
    final color = percent! >= 75
        ? const Color(0xFF16A34A)
        : percent! >= 60
            ? const Color(0xFFF59E0B)
            : const Color(0xFFDC2626);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('${percent!.toStringAsFixed(0)}%',
            style: theme.textTheme.titleLarge?.copyWith(color: color)),
        Text('attendance', style: theme.textTheme.bodySmall),
      ],
    );
  }
}
