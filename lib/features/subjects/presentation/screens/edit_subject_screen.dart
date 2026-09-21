import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/subject_icons.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../schedule/domain/class_session.dart';
import '../../../schedule/presentation/providers/schedule_providers.dart';
import '../../domain/subject.dart';
import '../providers/subject_providers.dart';

/// Add or edit a subject. Simple by default: name, colour, and a "which days +
/// what time" schedule. Everything else lives under "More options".
class EditSubjectScreen extends ConsumerStatefulWidget {
  final Subject? subject;
  const EditSubjectScreen({super.key, this.subject});

  @override
  ConsumerState<EditSubjectScreen> createState() => _EditSubjectScreenState();
}

class _EditSubjectScreenState extends ConsumerState<EditSubjectScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _professor;
  late final TextEditingController _credits;
  late final TextEditingController _classLink;
  late final TextEditingController _room;
  late int _colorHex;
  late String _iconKey;
  late List<_LinkFields> _links;  final List<_TimeBlock> _blocks = [];
  DateTime? _start;
  DateTime? _end;
  double? _target; // null = follow global default
  bool _saving = false;
  bool _loadingSessions = false;

  bool get _isEdit => widget.subject != null;

  @override
  void initState() {
    super.initState();
    final s = widget.subject;
    _name = TextEditingController(text: s?.name ?? '');
    _professor = TextEditingController(text: s?.professor ?? '');
    _credits = TextEditingController(text: s?.credits?.toString() ?? '');
    _classLink = TextEditingController(text: s?.classLink ?? '');
    _room = TextEditingController(text: s?.room ?? '');
    _colorHex = s?.colorHex ?? AppColors.subjectPalette.first.toARGB32();
    _iconKey = s?.iconKey ?? SubjectIcons.defaultKey;
    _start = s?.startDate;
    _end = s?.endDate;
    _target = s?.targetPercent;
    _links = (s?.resourceLinks ?? [])
        .map((l) => _LinkFields(title: l.title, url: l.url))
        .toList();
    if (_isEdit) {
      // Load the subject's existing timetable so the form shows (and can
      // remove) the real schedule instead of an empty default block.
      _loadingSessions = true;
      _loadExistingSchedule();
    } else {
      // A subject represents a class, so start a new subject with a class on
      // today's weekday pre-selected. This means it shows up on the Home
      // screen and schedule straight away — the user can still change the day
      // or add more.
      _blocks.add(_TimeBlock(
        start: const TimeOfDay(hour: 9, minute: 0),
        end: const TimeOfDay(hour: 10, minute: 0),
      )..days.add(DateTime.now().weekday - 1));
    }
  }

  /// Fetch the subject's recurring sessions and group them into day/time
  /// blocks (a class meeting on several days becomes one block with multiple
  /// days selected). One-off sessions are left untouched by this screen.
  Future<void> _loadExistingSchedule() async {
    final repo = ref.read(sessionRepositoryProvider);
    final subjectId = widget.subject?.id;
    var sessions = const <ClassSession>[];
    if (repo != null && subjectId != null) {
      try {
        sessions = await repo.getForSubject(subjectId);
      } catch (_) {
        // Fall through to a default block if the schedule can't be loaded.
      }
    }
    if (!mounted) return;
    final recurring =
        sessions.where((s) => s.recurring && s.dayOfWeek != null).toList();
    final byKey = <String, _TimeBlock>{};
    for (final s in recurring) {
      final key = '${s.startTime}|${s.endTime}|${s.room ?? ''}';
      final block = byKey.putIfAbsent(key, () {
        final start = DateUtilsX.parseTime24(s.startTime) ??
            const TimeOfDay(hour: 9, minute: 0);
        final end = DateUtilsX.parseTime24(s.endTime) ??
            const TimeOfDay(hour: 10, minute: 0);
        return _TimeBlock(start: start, end: end, room: s.room ?? '');
      });
      block.days.add(s.dayOfWeek!);
    }
    setState(() {
      for (final b in _blocks) {
        b.dispose();
      }
      _blocks
        ..clear()
        ..addAll(byKey.values);
      if (_blocks.isEmpty) {
        _blocks.add(_TimeBlock(
          start: const TimeOfDay(hour: 9, minute: 0),
          end: const TimeOfDay(hour: 10, minute: 0),
        ));
      }
      _loadingSessions = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _professor.dispose();
    _credits.dispose();
    _classLink.dispose();
    _room.dispose();
    for (final l in _links) {
      l.dispose();
    }
    for (final b in _blocks) {
      b.dispose();
    }
    super.dispose();
  }

  void _addBlock() {
    setState(() => _blocks.add(_TimeBlock(
          start: const TimeOfDay(hour: 9, minute: 0),
          end: const TimeOfDay(hour: 10, minute: 0),
        )));
  }

  Future<void> _pickBlockTime(_TimeBlock b, bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? b.start : b.end,
    );
    if (picked != null) {
      setState(() => isStart ? b.start = picked : b.end = picked);
    }
  }

  Future<void> _pickIcon() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final swatch = Color(_colorHex);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose an icon',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: SubjectIcons.keys.map((key) {
                      final sel = key == _iconKey;
                      return GestureDetector(
                        onTap: () => Navigator.pop(ctx, key),
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: sel
                                ? swatch.withValues(alpha: 0.16)
                                : theme.scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: sel ? swatch : theme.dividerColor,
                              width: sel ? 2 : 1,
                            ),
                          ),
                          child: Icon(SubjectIcons.resolve(key),
                              size: 24,
                              color: sel ? swatch : theme.hintColor),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected != null) setState(() => _iconKey = selected);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(subjectRepositoryProvider);
    if (repo == null) return;

    setState(() => _saving = true);
    final links = _links
        .where((l) => l.url.text.trim().isNotEmpty)
        .map((l) => ResourceLink(
              title: l.title.text.trim().isEmpty
                  ? 'Resource'
                  : l.title.text.trim(),
              url: l.url.text.trim(),
            ))
        .toList();

    final subject = Subject(
      id: widget.subject?.id ?? '',
      name: _name.text.trim(),
      colorHex: _colorHex,
      professor:
          _professor.text.trim().isEmpty ? null : _professor.text.trim(),
      credits: int.tryParse(_credits.text.trim()),
      classLink:
          _classLink.text.trim().isEmpty ? null : _classLink.text.trim(),
      room: _room.text.trim().isEmpty ? null : _room.text.trim(),
      resourceLinks: links,
      attended: widget.subject?.attended ?? 0,
      absent: widget.subject?.absent ?? 0,
      cancelled: widget.subject?.cancelled ?? 0,
      targetPercent: _target,
      startDate: _start,
      endDate: _end,
      iconKey: _iconKey,
      createdAt: widget.subject?.createdAt,
    );

    try {
      final String subjectId;
      if (_isEdit) {
        await repo.update(subject);
        subjectId = subject.id;
      } else {
        subjectId = await repo.create(subject);
      }
      // Reconcile the recurring timetable with the day/time blocks.
      final sessionRepo = ref.read(sessionRepositoryProvider);
      if (sessionRepo != null) {
        final existing = _isEdit
            ? await sessionRepo.getForSubject(subjectId)
            : const <ClassSession>[];

        // Desired recurring sessions from the blocks (deduped by signature).
        final desired = <ClassSession>[];
        final desiredSigs = <String>{};
        for (final b in _blocks) {
          for (final day in b.days) {
            final session = ClassSession(
              id: '',
              subjectId: subjectId,
              recurring: true,
              dayOfWeek: day,
              startTime: DateUtilsX.formatTime24(b.start),
              endTime: DateUtilsX.formatTime24(b.end),
              room: b.room.text.trim().isEmpty ? null : b.room.text.trim(),
            );
            if (desiredSigs.add(session.signature)) desired.add(session);
          }
        }

        // A subject always represents at least one class. If a brand-new
        // subject was saved without any weekday selected, create a weekly
        // class on today's weekday so it appears on Home and the schedule.
        if (!_isEdit && desired.isEmpty) {
          final b = _blocks.isNotEmpty ? _blocks.first : null;
          final session = ClassSession(
            id: '',
            subjectId: subjectId,
            recurring: true,
            dayOfWeek: DateTime.now().weekday - 1,
            startTime:
                b != null ? DateUtilsX.formatTime24(b.start) : '09:00',
            endTime: b != null ? DateUtilsX.formatTime24(b.end) : '10:00',
            room: (b != null && b.room.text.trim().isNotEmpty)
                ? b.room.text.trim()
                : null,
          );
          desiredSigs.add(session.signature);
          desired.add(session);
        }

        final existingSigs = existing.map((s) => s.signature).toSet();

        // Delete recurring slots the user removed. Never touch one-off
        // (specificDate) sessions — those are managed from the schedule editor.
        for (final s in existing) {
          if (s.recurring &&
              s.dayOfWeek != null &&
              !desiredSigs.contains(s.signature)) {
            await sessionRepo.delete(subjectId, s.id);
          }
        }

        // Add newly-selected slots, skipping any that already exist.
        for (final session in desired) {
          if (existingSigs.contains(session.signature)) continue;
          await sessionRepo.add(subjectId, session);
        }
      }
      // Opened via Navigator.push, so dismiss through the real Navigator.
      // go_router's context.pop() here could empty the match list on the last
      // page → the "Bad state: No element" crash + black screen.
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final subject = widget.subject;
    if (subject == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete subject?'),
        content: Text(
            'This permanently removes "${subject.name}", its schedule and attendance history. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(subjectRepositoryProvider);
    if (repo == null) return;
    try {
      await repo.delete(subject.id);
      // Opened via Navigator.push, so dismiss through the real Navigator.
      // go_router's context.pop() here could empty the match list on the last
      // page → the "Bad state: No element" crash + black screen.
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit subject' : 'New subject'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete subject',
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Name + colour.
            Row(
              children: [
                GestureDetector(
                  onTap: _pickIcon,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Color(_colorHex),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        alignment: Alignment.center,
                        child: Icon(SubjectIcons.resolve(_iconKey),
                            color: Colors.white, size: 26),
                      ),
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Theme.of(context).dividerColor),
                          ),
                          child: const Icon(Icons.edit_rounded,
                              size: 12, color: AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Subject name',
                      hintText: 'e.g. Database Systems',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a name'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: AppColors.subjectPalette.map((c) {
                final selected = c.toARGB32() == _colorHex;
                return GestureDetector(
                  onTap: () => setState(() => _colorHex = c.toARGB32()),
                  child: Container(
                    height: 36,
                    width: 36,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      // Always keep a subtle outline so light/pastel swatches
                      // stay visible against the white background on
                      // low-brightness screens; a thicker ink ring marks the
                      // selected colour.
                      border: Border.all(
                        color: selected
                            ? theme.colorScheme.onSurface
                            : Colors.black.withValues(alpha: 0.18),
                        width: selected ? 3 : 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: selected
                        ? const Icon(Icons.check,
                            color: Colors.white, size: 18)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Schedule — the simple core.
            Text('When is this class?',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Pick the days and set the time.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            if (_loadingSessions)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              ..._blocks.asMap().entries.map((e) => _blockCard(e.key, e.value)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addBlock,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add another time'),
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Advanced, collapsed.
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text('More options (optional)',
                    style: theme.textTheme.titleMedium),
                children: [
                  TextFormField(
                    controller: _professor,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Professor',
                      prefixIcon: Icon(Icons.school_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _credits,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Credits',
                      prefixIcon: Icon(Icons.star_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _classLink,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Class link (Zoom / Meet / Teams)',
                      prefixIcon: Icon(Icons.videocam_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _room,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Room / location (optional)',
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                          child: _dateTile('Term start', _start, _pickStart)),
                      const SizedBox(width: 12),
                      Expanded(child: _dateTile('Term end', _end, _pickEnd)),
                    ],
                  ),
                  if (_start != null || _end != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() {
                          _start = null;
                          _end = null;
                        }),
                        child: const Text('Clear dates'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _targetSection(theme),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Resource links',
                            style: theme.textTheme.titleSmall),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _links.add(_LinkFields.empty())),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  ..._links
                      .asMap()
                      .entries
                      .map((e) => _linkRow(e.key, e.value)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            LoadingButton(
              label: _isEdit ? 'Save changes' : 'Create subject',
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockCard(int index, _TimeBlock b) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 7; i++) _dayChip(b, i),
              if (_blocks.length > 1)
                GestureDetector(
                  onTap: () => setState(() {
                    b.dispose();
                    _blocks.removeAt(index);
                  }),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.close_rounded,
                        size: 18, color: AppColors.danger),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _timeField(
                      'Start', b.start, () => _pickBlockTime(b, true))),
              const SizedBox(width: 10),
              Expanded(
                  child: _timeField(
                      'End', b.end, () => _pickBlockTime(b, false))),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: b.room,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Room (optional)', isDense: true),
          ),
        ],
      ),
    );
  }

  Widget _dayChip(_TimeBlock b, int i) {
    final theme = Theme.of(context);
    final selected = b.days.contains(i);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() =>
            selected ? b.days.remove(i) : b.days.add(i)),
        child: Container(
          margin: const EdgeInsets.only(right: 4),
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : theme.scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? AppColors.primary : theme.dividerColor),
          ),
          child: Text(
            Weekdays.short[i].substring(0, 1),
            style: TextStyle(
              color: selected ? Colors.white : theme.textTheme.bodySmall?.color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeField(String label, TimeOfDay t, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          prefixIcon: const Icon(Icons.schedule_rounded, size: 18),
        ),
        child: Text(t.format(context)),
      ),
    );
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2031),
    );
    if (picked != null) {
      setState(() {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = null;
      });
    }
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _end ?? (_start ?? DateTime.now()).add(const Duration(days: 120)),
      firstDate: _start ?? DateTime(2020),
      lastDate: DateTime(2032),
    );
    if (picked != null) setState(() => _end = picked);
  }

  Widget _dateTile(String label, DateTime? date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_rounded),
          isDense: true,
        ),
        child: Text(date == null ? 'Not set' : DateUtilsX.prettyDate(date)),
      ),
    );
  }

  Widget _targetSection(ThemeData theme) {
    final custom = _target != null;
    const globalDefault = AppConstants.defaultTargetAttendance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attendance target',
                      style: theme.textTheme.titleSmall),
                  Text(
                    custom
                        ? 'Custom for this subject'
                        : 'Following your global target',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Switch(
              value: custom,
              onChanged: (on) =>
                  setState(() => _target = on ? (_target ?? globalDefault) : null),
            ),
          ],
        ),
        if (custom)
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _target!.clamp(50, 100),
                  min: 50,
                  max: 100,
                  divisions: 50,
                  label: '${_target!.round()}%',
                  activeColor: AppColors.primary,
                  onChanged: (v) => setState(() => _target = v),
                ),
              ),
              SizedBox(
                width: 46,
                child: Text('${_target!.round()}%',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
      ],
    );
  }

  Widget _linkRow(int index, _LinkFields fields) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                TextFormField(
                  controller: fields.title,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: fields.url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'URL',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.danger),
            onPressed: () {
              setState(() {
                fields.dispose();
                _links.removeAt(index);
              });
            },
          ),
        ],
      ),
    );
  }
}

class _LinkFields {
  final TextEditingController title;
  final TextEditingController url;
  _LinkFields({required String title, required String url})
      : title = TextEditingController(text: title),
        url = TextEditingController(text: url);
  factory _LinkFields.empty() => _LinkFields(title: '', url: '');
  void dispose() {
    title.dispose();
    url.dispose();
  }
}

/// A "these days at this time" block. Creates one recurring class per day.
class _TimeBlock {
  final Set<int> days = {}; // 0..6 (Mon..Sun)
  TimeOfDay start;
  TimeOfDay end;
  final TextEditingController room;
  _TimeBlock({required this.start, required this.end, String room = ''})
      : room = TextEditingController(text: room);
  void dispose() => room.dispose();
}
