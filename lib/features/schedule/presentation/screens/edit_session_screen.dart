import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../../subjects/presentation/screens/edit_subject_screen.dart';
import '../../domain/class_session.dart';
import '../providers/schedule_providers.dart';

/// Sentinel value for the "Create new subject" entry in the subject dropdown.
const _kNewSubjectValue = '__new_subject__';

/// Add or edit a [ClassSession]. Optionally pre-select [subjectId] and pass an
/// existing [session] to edit.
class EditSessionScreen extends ConsumerStatefulWidget {  final String? subjectId;
  final ClassSession? session;
  const EditSessionScreen({super.key, this.subjectId, this.session});

  @override
  ConsumerState<EditSessionScreen> createState() => _EditSessionScreenState();
}

class _EditSessionScreenState extends ConsumerState<EditSessionScreen> {
  String? _subjectId;
  bool _recurring = true;
  final Set<int> _days = {}; // 0..6 (Mon..Sun) selected weekdays
  DateTime _specificDate = DateTime.now();
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 10, minute: 0);
  final _room = TextEditingController();
  bool _saving = false;

  bool get _isEdit => widget.session != null;

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _subjectId = widget.subjectId ?? s?.subjectId;
    if (s != null) {
      _recurring = s.recurring;
      _days.add(s.dayOfWeek ?? (DateTime.now().weekday - 1));
      _specificDate = s.specificDate ?? DateTime.now();
      _start = DateUtilsX.parseTime24(s.startTime) ?? _start;
      _end = DateUtilsX.parseTime24(s.endTime) ?? _end;
      _room.text = s.room ?? '';
    } else {
      _days.add(DateTime.now().weekday - 1);
    }
  }

  String _daysLabel() {
    final sorted = _days.toList()..sort();
    return sorted.map((d) => Weekdays.short[d]).join(', ');
  }

  @override
  void dispose() {
    _room.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _start = picked;
        } else {
          _end = picked;
        }
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _specificDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _specificDate = picked);
  }

  /// Deletes this class from the timetable (edit mode only), after confirming.
  Future<void> _delete() async {
    final s = widget.session;
    final repo = ref.read(sessionRepositoryProvider);
    if (s == null || repo == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this class?'),
        content: const Text(
            'This removes the class from your timetable. This cannot be '
            'undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await repo.delete(s.subjectId, s.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Class deleted')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Opens the subject editor so a class can be created even when no subjects
  /// exist yet (or the user wants a brand-new one). The newly created subject
  /// is auto-selected when we return, so every subject is reachable as a class.
  Future<void> _createSubjectInline() async {
    final before = (ref.read(subjectsStreamProvider).valueOrNull ?? const [])
        .map((s) => s.id)
        .toSet();
    await Navigator.of(context).push(
      MaterialPageRoute(settings: const RouteSettings(name: 'Edit Subject'), builder: (_) => const EditSubjectScreen()),
    );
    if (!mounted) return;
    // The subjects stream (Firestore with local latency compensation) usually
    // reflects the new subject almost immediately; poll briefly to be safe.
    for (var i = 0; i < 20; i++) {
      final subjects = ref.read(subjectsStreamProvider).valueOrNull ?? const [];
      final added = subjects.where((s) => !before.contains(s.id)).toList();
      if (added.isNotEmpty) {
        setState(() => _subjectId = added.first.id);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _save() async {
    if (_subjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a subject first.')),
      );
      return;
    }
    if (_recurring && _days.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one day.')),
      );
      return;
    }
    final repo = ref.read(sessionRepositoryProvider);
    if (repo == null) return;

    setState(() => _saving = true);

    ClassSession build(int? day) => ClassSession(
          id: widget.session?.id ?? '',
          subjectId: _subjectId!,
          recurring: _recurring,
          dayOfWeek: _recurring ? day : null,
          specificDate: _recurring ? null : _specificDate,
          startTime: DateUtilsX.formatTime24(_start),
          endTime: DateUtilsX.formatTime24(_end),
          room: _room.text.trim().isEmpty ? null : _room.text.trim(),
          cancelledOn: widget.session?.cancelledOn ?? const [],
        );

    try {
      if (!_recurring) {
        // One-off class on a specific date.
        if (_isEdit) {
          await repo.update(build(null));
        } else {
          await repo.add(_subjectId!, build(null));
        }
      } else {
        final days = _days.toList()..sort();
        // Existing signatures guard against writing identical duplicates.
        final existing = await repo.getForSubject(_subjectId!);
        final seen = existing.map((s) => s.signature).toSet();
        ClassSession weekly(int d) => ClassSession(
              id: '',
              subjectId: _subjectId!,
              recurring: true,
              dayOfWeek: d,
              startTime: DateUtilsX.formatTime24(_start),
              endTime: DateUtilsX.formatTime24(_end),
              room: _room.text.trim().isEmpty ? null : _room.text.trim(),
            );
        if (_isEdit) {
          // Keep editing the existing session on the first day, then add the
          // remaining selected days as new weekly sessions (skipping dups).
          final first = build(days.first);
          seen.add(first.signature);
          await repo.update(first);
          for (final d in days.skip(1)) {
            final s = weekly(d);
            if (!seen.add(s.signature)) continue;
            await repo.add(_subjectId!, s);
          }
        } else {
          // New class: one weekly session per selected day (skipping dups).
          for (final d in days) {
            final s = weekly(d);
            if (!seen.add(s.signature)) continue;
            await repo.add(_subjectId!, s);
          }
        }
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit class' : 'Add class'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete class',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _subjectId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Subject',
              hintText: 'Select or create a subject',
            ),
            items: [
              ...subjects.map((s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(s.name, overflow: TextOverflow.ellipsis),
                  )),
              const DropdownMenuItem(
                value: _kNewSubjectValue,
                child: Row(
                  children: [
                    Icon(Icons.add_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Create new subject'),
                  ],
                ),
              ),
            ],
            onChanged: (v) {
              if (v == _kNewSubjectValue) {
                _createSubjectInline();
              } else {
                setState(() => _subjectId = v);
              }
            },
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repeats weekly'),
            subtitle: Text(_recurring
                ? 'Every ${_daysLabel()}'
                : 'One-off class'),
            value: _recurring,
            onChanged: (v) => setState(() => _recurring = v),
          ),
          const SizedBox(height: 8),
          if (_recurring) ...[
            Text('On these days',
                style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(7, (i) {
                final selected = _days.contains(i);
                return FilterChip(
                  label: Text(Weekdays.short[i]),
                  selected: selected,
                  showCheckmark: true,
                  onSelected: (on) => setState(() {
                    if (on) {
                      _days.add(i);
                    } else if (_days.length > 1) {
                      _days.remove(i);
                    }
                  }),
                );
              }),
            ),
            if (_days.length > 1) ...[
              const SizedBox(height: 8),
              Text('${_days.length} classes/week will be created',
                  style: theme.textTheme.bodySmall),
            ],
          ] else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_rounded),
              title: const Text('Date'),
              subtitle: Text(DateUtilsX.prettyFullDate(_specificDate)),
              trailing: TextButton(onPressed: _pickDate, child: const Text('Pick')),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _timeField(theme, 'Start', _start, () => _pickTime(true)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _timeField(theme, 'End', _end, () => _pickTime(false)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _room,
            decoration: const InputDecoration(
              labelText: 'Room / location (optional)',
              prefixIcon: Icon(Icons.meeting_room_outlined),
            ),
          ),
          const SizedBox(height: 32),
          LoadingButton(
            label: _isEdit ? 'Save class' : 'Add class',
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _timeField(ThemeData theme, String label, TimeOfDay time, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(time.format(context), style: theme.textTheme.bodyLarge),
      ),
    );
  }
}
