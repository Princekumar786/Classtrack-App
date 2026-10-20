import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/checklist_item.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../domain/task_item.dart';
import '../providers/task_providers.dart';

/// Bottom-sheet editor for adding/editing a task, assignment, event or video.
class TaskEditorSheet extends ConsumerStatefulWidget {
  final TaskItem? task;
  final TaskType? initialType;
  final DateTime? initialDue;

  /// Pre-selected subject for a brand-new item (e.g. the subject filter that
  /// was active on the Assignments view). Ignored when editing.
  final String? initialSubjectId;

  /// Pre-fill values for a brand-new item (e.g. from the Android share sheet).
  /// Ignored when editing an existing [task]. All remain fully editable.
  final String? initialTitle;
  final String? initialNote;
  final String? initialLink;
  final String? initialThumbnail;

  const TaskEditorSheet({
    super.key,
    this.task,
    this.initialType,
    this.initialDue,
    this.initialSubjectId,
    this.initialTitle,
    this.initialNote,
    this.initialLink,
    this.initialThumbnail,
  });

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _link;
  String? _subjectId;
  DateTime? _due;
  TaskPriority _priority = TaskPriority.medium;
  TaskType _type = TaskType.task;
  String? _thumbnail;
  final List<_SubtaskField> _subtasks = [];

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? widget.initialTitle ?? '');
    _note = TextEditingController(text: t?.note ?? widget.initialNote ?? '');
    _link = TextEditingController(text: t?.link ?? widget.initialLink ?? '');
    _subjectId = t != null ? t.subjectId : widget.initialSubjectId;
    _due = t?.dueDate ?? widget.initialDue;
    _priority = t?.priority ?? TaskPriority.medium;
    _type = t?.type ?? widget.initialType ?? TaskType.task;
    _thumbnail = t?.thumbnail ?? widget.initialThumbnail;
    _subtasks.addAll((t?.subtasks ?? const [])
        .map((s) => _SubtaskField(text: s.text, done: s.done)));
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _link.dispose();
    for (final s in _subtasks) {
      s.dispose();
    }
    super.dispose();
  }

  List<ChecklistItem> _buildSubtasks() => _subtasks
      .where((s) => s.controller.text.trim().isNotEmpty)
      .map((s) => ChecklistItem(text: s.controller.text.trim(), done: s.done))
      .toList();

  void _addSubtask() => setState(() => _subtasks.add(_SubtaskField()));

  Widget _subtasksSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Checklist', style: theme.textTheme.labelLarge),
            const Spacer(),
            TextButton.icon(
              onPressed: _addSubtask,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add step'),
            ),
          ],
        ),
        for (var i = 0; i < _subtasks.length; i++)
          _subtaskRow(i, _subtasks[i]),
      ],
    );
  }

  Widget _subtaskRow(int i, _SubtaskField s) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => s.done = !s.done),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: s.done ? AppColors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                    color: s.done ? AppColors.primary : theme.dividerColor,
                    width: 2),
              ),
              child: s.done
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: s.controller,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Step',
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: theme.hintColor),
            onPressed: () => setState(() {
              s.dispose();
              _subtasks.removeAt(i);
            }),
          ),
        ],
      ),
    );
  }

  Widget _thumbnailPreview(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              _thumbnail!,
              fit: BoxFit.cover,
              cacheWidth: 800,
              // Keep the sheet usable if the preview can't load — just hide it.
              errorBuilder: (_, __, ___) => Container(
                color: theme.scaffoldBackgroundColor,
                alignment: Alignment.center,
                child: Icon(_type.icon, size: 36, color: theme.hintColor),
              ),
              loadingBuilder: (ctx, child, progress) => progress == null
                  ? child
                  : Container(
                      color: theme.scaffoldBackgroundColor,
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => setState(() => _thumbnail = null),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child:
                      Icon(Icons.close_rounded, size: 18, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _dueHasTime =>
      _due != null && !(_due!.hour == 0 && _due!.minute == 0);

  Future<void> _pickDue() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      // Keep any time-of-day already chosen when only the date changes.
      final prev = _due;
      final keepTime = prev != null && !(prev.hour == 0 && prev.minute == 0);
      setState(() => _due = keepTime
          ? DateTime(picked.year, picked.month, picked.day, prev.hour,
              prev.minute)
          : picked);
    }
  }

  Future<void> _pickTime() async {
    final base = _due ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (picked != null) {
      final d = _due ?? DateTime.now();
      setState(() =>
          _due = DateTime(d.year, d.month, d.day, picked.hour, picked.minute));
    }
  }

  void _save() {
    if (_title.text.trim().isEmpty) return;
    final link = _link.text.trim();
    final thumb = link.isEmpty ? null : _thumbnail;
    final controller = ref.read(taskControllerProvider);
    if (_isEdit) {
      controller.update(widget.task!.copyWith(
        title: _title.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        subjectId: _subjectId,
        dueDate: _due,
        priority: _priority,
        type: _type,
        link: link.isEmpty ? null : link,
        thumbnail: thumb,
        clearDue: _due == null,
        clearSubject: _subjectId == null,
        clearLink: link.isEmpty,
        subtasks: _buildSubtasks(),
      ));
    } else {
      controller.add(TaskItem(
        id: '',
        title: _title.text.trim(),
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        subjectId: _subjectId,
        dueDate: _due,
        priority: _priority,
        type: _type,
        link: link.isEmpty ? null : link,
        thumbnail: thumb,
        subtasks: _buildSubtasks(),
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(
                _isEdit
                    ? 'Edit ${_type.label.toLowerCase()}'
                    : 'New ${_type.label.toLowerCase()}',
                style: theme.textTheme.titleLarge),
            if (_thumbnail != null && _thumbnail!.isNotEmpty) ...[
              const SizedBox(height: 14),
              _thumbnailPreview(theme),
            ],
            const SizedBox(height: 14),
            Row(
              children: TaskType.values.map((t) {
                final selected = t == _type;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        right: t == TaskType.values.last ? 0 : 6),
                    child: Semantics(
                      button: true,
                      selected: selected,
                      label: t.label,
                      child: GestureDetector(
                        onTap: () => setState(() => _type = t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                              vertical: 11, horizontal: 4),
                          decoration: BoxDecoration(
                            color: selected
                                ? t.color.withValues(alpha: 0.14)
                                : theme.scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected ? t.color : theme.dividerColor,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(t.icon,
                                  size: 20,
                                  color: selected ? t.color : theme.hintColor),
                              const SizedBox(height: 4),
                              // Four options share the row, so "Assignment"
                              // scales down instead of overflowing.
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(t.label,
                                    maxLines: 1,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                      color:
                                          selected ? t.color : theme.hintColor,
                                      fontWeight: FontWeight.w600,
                                    )),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: switch (_type) {
                  TaskType.assignment => 'e.g. DBMS assignment 2',
                  TaskType.event => 'e.g. Hackathon kick-off',
                  TaskType.video => 'e.g. Watch OS scheduling lecture',
                  TaskType.task => 'e.g. Print lab record',
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            const SizedBox(height: 14),
            _subtasksSection(theme),
            const SizedBox(height: 12),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: _type == TaskType.task
                    ? 'Link (optional)'
                    : '${_type.label} link',
                hintText: 'https://youtube.com/…',
                prefixIcon: const Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              // Guard against a subject that was deleted (or hasn't loaded
              // yet): a value missing from the items list would assert.
              initialValue: subjects.any((s) => s.id == _subjectId)
                  ? _subjectId
                  : null,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: _type == TaskType.assignment
                      ? 'Subject'
                      : 'Subject (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                ...subjects.map((s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) => setState(() => _subjectId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDue,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(_due == null
                        ? 'Set due date'
                        : DateUtilsX.prettyDate(_due!)),
                  ),
                ),
                if (_due != null)
                  IconButton(
                    tooltip: 'Clear date',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _due = null),
                  ),
              ],
            ),
            if (_due != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule_rounded, size: 18),
                      label: Text(_dueHasTime
                          ? TimeOfDay.fromDateTime(_due!).format(context)
                          : 'Add time (all day)'),
                    ),
                  ),
                  if (_dueHasTime)
                    IconButton(
                      tooltip: 'Clear time',
                      icon: const Icon(Icons.close_rounded),
                      // Reset to midnight → treated as an all-day item.
                      onPressed: () => setState(() => _due =
                          DateTime(_due!.year, _due!.month, _due!.day)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text('Priority', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: TaskPriority.values.map((p) {
                final selected = p == _priority;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _priority = p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected
                              ? p.color
                              : p.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: selected ? Colors.white : p.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              p.label,
                              style: TextStyle(
                                color: selected ? Colors.white : p.color,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                child: Text(
                    _isEdit ? 'Save' : 'Add ${_type.label.toLowerCase()}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editable subtask row backing (text field + done flag).
class _SubtaskField {
  final TextEditingController controller;
  bool done;
  _SubtaskField({String text = '', this.done = false})
      : controller = TextEditingController(text: text);
  void dispose() => controller.dispose();
}
