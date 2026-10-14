import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../semesters/domain/semester.dart';
import '../../../semesters/presentation/screens/wrap_up_semester_screen.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../domain/parsed_schedule.dart';
import '../../data/import_draft_store.dart';
import '../../data/import_repository.dart';
import '../providers/import_providers.dart';

/// Editable review of the Gemini-parsed schedule. Nothing is written to
/// Firestore until the user taps "Add to ClassTrack".
class ReviewScreen extends ConsumerStatefulWidget {
  final ParsedSchedule schedule;
  const ReviewScreen({super.key, required this.schedule});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen>
    with WidgetsBindingObserver {
  late ParsedSchedule _schedule;
  bool _saving = false;

  /// Unsaved-import draft (see [ImportDraftStore]). Cached so it can still be
  /// flushed from [dispose], when `ref` must no longer be used.
  late final ImportDraftStore _drafts;
  Timer? _persistTimer;

  /// True once the import is saved or discarded: stop writing the draft.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _schedule = widget.schedule;
    _drafts = ref.read(importDraftProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    _schedulePersist();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistTimer?.cancel();
    // Leaving with unsaved edits (e.g. a back gesture we didn't intercept):
    // keep the latest version.
    if (!_finished) _drafts.saveSoon(_schedule);
    super.dispose();
  }

  /// Every UI change in this screen goes through setState, so autosave hooks
  /// in here (debounced) instead of at each of the many edit points.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _schedulePersist();
  }

  void _schedulePersist() {
    if (_finished) return;
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 600), _persistNow);
  }

  void _persistNow() {
    _persistTimer?.cancel();
    if (_finished) return;
    _drafts.save(_schedule);
  }

  /// The OS may kill a backgrounded app without warning: flush immediately.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _persistNow();
  }

  /// Back without saving: keep the draft for later, discard it, or stay.
  Future<void> _onBack() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text(
            'Your scanned timetable isn’t in ClassTrack yet. Keep it to finish '
            'later, or discard it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard',
                  style: TextStyle(color: AppColors.danger))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'keep'),
              child: const Text('Keep for later')),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'discard') {
      _finished = true;
      _persistTimer?.cancel();
      await _drafts.clear();
      ref.read(analyticsProvider).log('import_draft_discarded');
    } else {
      _persistNow();
    }
    if (mounted) Navigator.of(context).pop();
  }

  Color _confidenceColor() => switch (_schedule.confidence) {
    'high' => AppColors.success,
    'medium' => AppColors.warning,
    _ => AppColors.danger,
  };

  /// The model told us it wasn't fully sure about this parse.
  bool get _lowConfidence => _schedule.confidence != 'high';

  /// Parses "HH:MM" into minutes-since-midnight, or null when malformed.
  int? _minutesOf(String hhmm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }

  /// Field-level confidence: returns a short reason this session's time should
  /// be double-checked, or null when it looks fine. Concrete problems (bad
  /// format, end-before-start) are always flagged; when the model's overall
  /// confidence is low/medium we also nudge the user to verify every time.
  String? _timeIssue(ParsedSession s) {
    final start = _minutesOf(s.start);
    final end = _minutesOf(s.end);
    if (start == null || end == null) return 'Check the time format';
    if (end <= start) return 'End time is before start';
    if (_lowConfidence) return 'AI wasn’t sure — please verify';
    return null;
  }

  /// How many sessions across all subjects are flagged for a quick check.
  int get _flaggedCount => _schedule.subjects
      .expand((s) => s.sessions)
      .where((s) => _timeIssue(s) != null)
      .length;

  /// Asked once per review: a reply of "add anyway" isn't asked again.
  bool _semesterAsked = false;

  /// When the import looks like a NEW semester's timetable while old subjects
  /// are still current, offer to wrap up the old semester first (Pro).
  /// Returns false when the save should stop (user cancelled, or went to the
  /// wrap-up screen and backed out).
  Future<bool> _maybeOfferWrapUp() async {
    if (_semesterAsked) return true;
    var current = ref.read(subjectsStreamProvider).valueOrNull;
    if (current == null) {
      try {
        current = await ref
            .read(subjectsStreamProvider.future)
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        return true; // can't tell: never block the import
      }
      if (!mounted) return false;
    }
    final existing = current;
    final incoming = [
      for (final s in _schedule.subjects)
        if (s.include) s.name,
    ];
    if (!looksLikeNewSemester(
        existingNames: existing.map((s) => s.name),
        incomingNames: incoming)) {
      return true;
    }
    _semesterAsked = true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Starting a new semester?'),
        content: Text(
            'You still have ${existing.length} subject'
            '${existing.length == 1 ? '' : 's'} from your current semester. '
            'Wrap it up first to save its marks, exams and attendance '
            'separately, so your new timetable and GPA start fresh.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'add'),
              child: const Text('Just add these')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'wrap'),
              child: const Text('Wrap up first')),
        ],
      ),
    );
    if (!mounted) return false;
    ref.read(analyticsProvider).log('import_new_semester_prompt',
        {'choice': choice ?? 'dismissed'});
    if (choice == 'add') return true;
    if (choice != 'wrap') {
      _semesterAsked = false; // dismissed: ask again next time
      return false;
    }
    final wrapped = await startSemesterWrapUp(context, ref, returnWhenDone: true);
    // Wrapped up → import into the fresh semester. Backed out → stay here.
    return wrapped && mounted;
  }

  Future<void> _commit() async {
    final repo = ref.read(importRepositoryProvider);
    if (repo == null) return;
    if (!await _maybeOfferWrapUp()) return;
    setState(() => _saving = true);
    try {
      final result = await repo.commit(_schedule);
      // Saved to Firestore (syncs everywhere): the local draft is done.
      _finished = true;
      _persistTimer?.cancel();
      await _drafts.clear();
      if (!mounted) return;
      ref
          .read(analyticsProvider)
          .importReviewSaved(
            subjects: result.subjects,
            sessions: result.sessions,
            tasks: result.tasks,
          );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_summaryMessage(result))));
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _summaryMessage(ImportResult r) {
    if (r.total == 0) {
      return 'Nothing new to add — already up to date.';
    }
    final parts = <String>[];
    if (r.subjects > 0) {
      parts.add('${r.subjects} subject${r.subjects == 1 ? '' : 's'}');
    }
    if (r.sessions > 0) {
      parts.add('${r.sessions} class${r.sessions == 1 ? '' : 'es'}');
    }
    if (r.tasks > 0) {
      parts.add('${r.tasks} task${r.tasks == 1 ? '' : 's'}');
    }
    return 'Added ${parts.join(', ')} to ClassTrack.';
  }

  Future<void> _editSession(
    ParsedSubject subject,
    ParsedSession session,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) =>
          _SessionEditor(session: session, onChanged: () => setState(() {})),
    );
  }

  Future<void> _pickStart(ParsedSubject subject) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: subject.startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2031),
    );
    if (picked != null) {
      setState(() {
        subject.startDate = picked;
        if (subject.endDate != null && subject.endDate!.isBefore(picked)) {
          subject.endDate = null;
        }
      });
    }
  }

  Future<void> _pickEnd(ParsedSubject subject) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          subject.endDate ??
          (subject.startDate ?? DateTime.now()).add(const Duration(days: 120)),
      firstDate: subject.startDate ?? DateTime(2020),
      lastDate: DateTime(2032),
    );
    if (picked != null) setState(() => subject.endDate = picked);
  }

  Widget _dateTile(String label, DateTime? date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          prefixIcon: const Icon(Icons.event_rounded),
        ),
        child: Text(date == null ? 'Not set' : DateUtilsX.prettyDate(date)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('Review & confirm')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _confidenceColor().withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_outlined, color: _confidenceColor()),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _flaggedCount > 0
                        ? 'AI confidence: ${_schedule.confidence.toUpperCase()}. '
                              '$_flaggedCount time${_flaggedCount == 1 ? '' : 's'} '
                              'marked below need a quick check before saving.'
                        : 'AI confidence: ${_schedule.confidence.toUpperCase()}. '
                              'Please double-check times and rooms before saving.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._schedule.subjects.asMap().entries.map((entry) {
            final subject = entry.value;
            return _subjectCard(theme, subject, entry.key);
          }),
          if (_schedule.tasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Tasks & deadlines', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'One-off items detected as assignments — added to your Tasks, '
              'not attendance.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            ..._schedule.tasks.asMap().entries.map(
              (e) => _taskCard(theme, e.value, e.key),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LoadingButton(
            label: 'Add to ClassTrack',
            loading: _saving,
            icon: Icons.check_rounded,
            onPressed: _commit,
          ),
        ),
      ),
      ),
    );
  }

  Widget _taskCard(ThemeData theme, ParsedTask task, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            Checkbox(
              value: task.include,
              onChanged: (v) => setState(() => task.include = v ?? true),
            ),
            Expanded(
              child: TextFormField(
                initialValue: task.title,
                style: theme.textTheme.titleMedium,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Task title',
                  helperText: task.due == null
                      ? 'No due date'
                      : 'Due ${DateUtilsX.prettyDate(task.due!)}',
                ),
                onChanged: (v) {
                  task.title = v;
                  _schedulePersist();
                },
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.danger,
              ),
              onPressed: () => setState(() => _schedule.tasks.removeAt(index)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subjectCard(ThemeData theme, ParsedSubject subject, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: subject.include,
                  onChanged: (v) => setState(() => subject.include = v ?? true),
                ),
                Expanded(
                  child: TextFormField(
                    initialValue: subject.name,
                    style: theme.textTheme.titleMedium,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Subject name',
                    ),
                    onChanged: (v) {
                      subject.name = v;
                      _schedulePersist();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.danger,
                  ),
                  onPressed: () =>
                      setState(() => _schedule.subjects.removeAt(index)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: subject.professor ?? '',
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Professor (optional)',
                prefixIcon: Icon(Icons.school_outlined),
              ),
              onChanged: (v) {
                subject.professor = v;
                _schedulePersist();
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: subject.classLink ?? '',
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Class link (Zoom / Meet / Teams)',
                prefixIcon: Icon(Icons.videocam_outlined),
              ),
              onChanged: (v) {
                subject.classLink = v;
                _schedulePersist();
              },
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _dateTile(
                    'Term start',
                    subject.startDate,
                    () => _pickStart(subject),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateTile(
                    'Term end',
                    subject.endDate,
                    () => _pickEnd(subject),
                  ),
                ),
              ],
            ),
            if (subject.startDate != null || subject.endDate != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() {
                    subject.startDate = null;
                    subject.endDate = null;
                  }),
                  child: const Text('Clear dates'),
                ),
              ),
            const SizedBox(height: 10),
            ...subject.sessions.asMap().entries.map((e) {
              final session = e.value;
              final issue = _timeIssue(session);
              final flagged = issue != null;
              final timeText = session.date != null
                  ? '${DateUtilsX.prettyDate(session.date!)}  ·  ${session.start}–${session.end}'
                  : '${session.day}  ·  ${session.start}–${session.end}';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  flagged
                      ? Icons.error_outline_rounded
                      : Icons.schedule_rounded,
                  size: 20,
                  color: flagged ? AppColors.warning : null,
                ),
                title: Text(
                  timeText,
                  style: flagged
                      ? theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
                ),
                subtitle: flagged
                    ? Text(
                        issue,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                        ),
                      )
                    : (session.room != null && session.room!.isNotEmpty
                          ? Text('Room ${session.room}')
                          : null),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Edit session',
                      onPressed: () => _editSession(subject, session),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Remove session',
                      onPressed: () =>
                          setState(() => subject.sessions.removeAt(e.key)),
                    ),
                  ],
                ),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(
                () => subject.sessions.add(
                  ParsedSession(day: 'Monday', start: '09:00', end: '10:00'),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add session'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionEditor extends StatefulWidget {
  final ParsedSession session;
  final VoidCallback onChanged;
  const _SessionEditor({required this.session, required this.onChanged});

  @override
  State<_SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<_SessionEditor> {
  late final TextEditingController _start;
  late final TextEditingController _end;
  late final TextEditingController _room;
  late String _day;

  @override
  void initState() {
    super.initState();
    _start = TextEditingController(text: widget.session.start);
    _end = TextEditingController(text: widget.session.end);
    _room = TextEditingController(text: widget.session.room ?? '');
    _day = widget.session.day;
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    _room.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Edit session', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: Weekdays.full.contains(_day) ? _day : 'Monday',
            decoration: const InputDecoration(labelText: 'Day'),
            items: Weekdays.full
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) => setState(() => _day = v ?? 'Monday'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _start,
                  decoration: const InputDecoration(labelText: 'Start (HH:MM)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _end,
                  decoration: const InputDecoration(labelText: 'End (HH:MM)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _room,
            decoration: const InputDecoration(labelText: 'Room (optional)'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              widget.session
                ..day = _day
                ..start = _start.text.trim()
                ..end = _end.text.trim()
                ..room = _room.text.trim().isEmpty ? null : _room.text.trim();
              widget.onChanged();
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
