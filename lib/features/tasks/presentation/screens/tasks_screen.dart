import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/checklist_item.dart';
import '../../../../core/utils/date_utils.dart';
import '../../../../shared/widgets/feature_tip_banner.dart';
import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../../shared/widgets/placement_slot.dart';
import '../../../cms/domain/marketing.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../domain/task_item.dart';
import '../providers/task_providers.dart';
import '../widgets/task_card.dart';

/// The quick filters shown as chips on the Tasks page.
enum TaskFilter { all, dueToday, upcoming, completed }

extension on TaskFilter {
  String get label => switch (this) {
        TaskFilter.all => 'All',
        TaskFilter.dueToday => 'Due today',
        TaskFilter.upcoming => 'Upcoming',
        TaskFilter.completed => 'Completed',
      };

  IconData get icon => switch (this) {
        TaskFilter.all => Icons.format_list_bulleted_rounded,
        TaskFilter.dueToday => Icons.wb_sunny_rounded,
        TaskFilter.upcoming => Icons.calendar_month_rounded,
        TaskFilter.completed => Icons.check_circle_rounded,
      };
}

/// How the visible task list is ordered.
enum TaskSort { smart, due, priority, created }

extension on TaskSort {
  String get label => switch (this) {
        TaskSort.smart => 'Smart',
        TaskSort.due => 'Due date',
        TaskSort.priority => 'Priority',
        TaskSort.created => 'Recently added',
      };

  IconData get icon => switch (this) {
        TaskSort.smart => Icons.auto_awesome_rounded,
        TaskSort.due => Icons.event_rounded,
        TaskSort.priority => Icons.flag_rounded,
        TaskSort.created => Icons.schedule_rounded,
      };
}

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  TaskFilter _filter = TaskFilter.all;
  TaskSort _sort = TaskSort.priority;
  TaskPriority? _priorityFilter;
  String _query = '';
  bool _searching = false;

  static void openEditor(BuildContext context, {TaskItem? task}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TaskEditorSheet(task: task),
    );
  }

  // ── Sorting ────────────────────────────────────────────────────────────
  int _byDue(TaskItem a, TaskItem b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    final ad = a.dueDate, bd = b.dueDate;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  }

  int _byPriority(TaskItem a, TaskItem b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    if (a.priority != b.priority) {
      return b.priority.index.compareTo(a.priority.index);
    }
    return _byDue(a, b);
  }

  int _byCreated(TaskItem a, TaskItem b) {
    if (a.done != b.done) return a.done ? 1 : -1;
    final ac = a.createdAt, bc = b.createdAt;
    if (ac == null && bc == null) return 0;
    if (ac == null) return 1;
    if (bc == null) return -1;
    return bc.compareTo(ac);
  }

  List<TaskItem> _applySort(List<TaskItem> tasks) {
    switch (_sort) {
      case TaskSort.smart:
        return tasks;
      case TaskSort.due:
        return [...tasks]..sort(_byDue);
      case TaskSort.priority:
        return [...tasks]..sort(_byPriority);
      case TaskSort.created:
        return [...tasks]..sort(_byCreated);
    }
  }

  Future<void> _clearCompleted(
      BuildContext context, List<TaskItem> allTasks) async {
    final done = allTasks.where((t) => t.done).toList();
    if (done.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear completed?'),
        content: Text('Delete ${done.length} completed '
            'task${done.length == 1 ? '' : 's'}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final ctrl = ref.read(taskControllerProvider);
    for (final t in done) {
      await ctrl.delete(t.id);
    }
  }

  void _deleteWithUndo(BuildContext context, TaskItem task) {
    final ctrl = ref.read(taskControllerProvider);
    ctrl.delete(task.id);
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    // Let the SnackBar auto-dismiss on its own duration. The previous
    // Duration(days: 1) + manual Timer approach could leave the undo bar
    // stuck on screen until the tab was closed.
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Text('Deleted “${task.title}”'),
      action: SnackBarAction(label: 'Undo', onPressed: () => ctrl.add(task)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasksAsync = ref.watch(tasksStreamProvider);
    final allTasks = tasksAsync.valueOrNull ?? const <TaskItem>[];
    final doneCount = allTasks.where((t) => t.done).length;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      floatingActionButton: canPop
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              onPressed: () => openEditor(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New task'),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, canPop, doneCount, allTasks),
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search tasks',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _query = '';
                        _searching = false;
                      }),
                    ),
                  ),
                ),
              ),
            const FeatureTipBanner(
              prefsKey: AppConstants.prefsTipTasks,
              message:
                  'Share any YouTube video to ClassTrack to create a task instantly.',
            ),
            const SizedBox(height: 6),
            _filterChips(theme),
            const SizedBox(height: 6),
            Expanded(
              child: tasksAsync.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(tasksStreamProvider)),
                data: (tasks) {
                  if (tasks.isEmpty) {
                    return EmptyState(
                      icon: Icons.check_circle_rounded,
                      title: 'No tasks yet',
                      message:
                          'Add assignments, deadlines and to-dos. They’ll show up on your calendar and dashboard.',
                      actionLabel: 'Add task',
                      onAction: () => openEditor(context),
                    );
                  }
                  return _content(theme, tasks);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────
  Widget _header(
      ThemeData theme, bool canPop, int doneCount, List<TaskItem> allTasks) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
      child: Row(
        children: [
          if (canPop) ...[
            RoundIconButton(
              icon: Icons.arrow_back_rounded,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 10),
          ],
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.task_alt_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tasks',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text('Stay organized. Get things done.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
            icon: Icon(_searching ? Icons.search_off_rounded : Icons.search_rounded),
          ),
          PopupMenuButton<TaskSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.filter_list_rounded),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (ctx) => [
              for (final s in TaskSort.values)
                PopupMenuItem(
                  value: s,
                  child: Row(
                    children: [
                      Icon(s.icon,
                          size: 18,
                          color: s == _sort
                              ? AppColors.primary
                              : theme.hintColor),
                      const SizedBox(width: 10),
                      Text('Sort: ${s.label}',
                          style: TextStyle(
                              fontWeight: s == _sort
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: s == _sort ? AppColors.primary : null)),
                    ],
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'clear') _clearCompleted(context, allTasks);
              if (v == 'add') openEditor(context);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'add', child: Text('Add task')),
              if (doneCount > 0)
                const PopupMenuItem(
                    value: 'clear', child: Text('Clear completed')),
            ],
          ),
        ],
      ),
    );
  }

  // ── Filter chips ────────────────────────────────────────────────────────
  Widget _filterChips(ThemeData theme) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        physics: const BouncingScrollPhysics(),
        children: [
          for (final f in TaskFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterPill(
                label: f.label,
                icon: f.icon,
                selected: _filter == f,
                onTap: () => setState(() {
                  _filter = f;
                  _priorityFilter = null;
                }),
              ),
            ),
        ],
      ),
    );
  }

  // ── Body content ─────────────────────────────────────────────────────────
  // ── Body content ─────────────────────────────────────────────────────────
  Widget _content(ThemeData theme, List<TaskItem> tasks) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Search filter first.
    final q = _query.trim().toLowerCase();
    final searched = q.isEmpty
        ? tasks
        : tasks
            .where((t) =>
                t.title.toLowerCase().contains(q) ||
                (t.note?.toLowerCase().contains(q) ?? false))
            .toList();

    final pending = searched.where((t) => !t.done).toList();
    final completed = _applySort(searched.where((t) => t.done).toList());

    // The visible list depends on the active filter.
    List<TaskItem> visible;
    switch (_filter) {
      case TaskFilter.all:
        visible = pending;
        break;
      case TaskFilter.dueToday:
        visible = pending
            .where((t) =>
                t.dueDate != null && DateUtilsX.isSameDay(t.dueDate!, now))
            .toList();
        break;
      case TaskFilter.upcoming:
        visible = pending.where((t) {
          final d = t.dueDate;
          if (d == null) return false;
          return DateTime(d.year, d.month, d.day).isAfter(today);
        }).toList();
        break;
      case TaskFilter.completed:
        visible = completed;
        break;
    }
    if (_priorityFilter != null) {
      visible = visible.where((t) => t.priority == _priorityFilter).toList();
    }
    visible = _applySort(visible);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
      children: [
        const PlacementSlot(placement: Placements.tasks),
        // Priority section (only on the All filter).
        if (_filter == TaskFilter.all) ...[
          const SizedBox(height: 22),
          Row(
            children: [
              Text('Priority',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _sort = _sort == TaskSort.priority
                    ? TaskSort.due
                    : TaskSort.priority),
                child: Row(
                  children: [
                    const Icon(Icons.swap_vert_rounded,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 3),
                    Text('Reorder',
                        style: theme.textTheme.labelLarge?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final p in [
                TaskPriority.high,
                TaskPriority.medium,
                TaskPriority.low
              ]) ...[
                _priorityCard(
                    theme, p, pending.where((t) => t.priority == p).length),
                if (p != TaskPriority.low) const SizedBox(width: 10),
              ],
            ],
          ),
        ],
        const SizedBox(height: 22),
        // My tasks header.
        Row(
          children: [
            Text(
                _filter == TaskFilter.completed
                    ? 'Completed tasks'
                    : 'My tasks',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            if (_priorityFilter != null) ...[
              const SizedBox(width: 8),
              _clearPriorityChip(theme),
            ],
            const Spacer(),
            GestureDetector(
              onTap: () => openEditor(context),
              child: Row(
                children: [
                  const Icon(Icons.add_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Text('Add task',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                q.isNotEmpty ? 'No matches' : 'Nothing here yet',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              ),
            ),
          )
        else
          for (final t in visible) _taskCard(context, t),
        // Completed collapsible (only on All filter).
        if (_filter == TaskFilter.all && completed.isNotEmpty) ...[
          const SizedBox(height: 8),
          _CompletedSection(
            tasks: completed,
            cardBuilder: (t) => _taskCard(context, t),
          ),
        ],
      ],
    );
  }

  Widget _clearPriorityChip(ThemeData theme) {
    return GestureDetector(
      onTap: () => setState(() => _priorityFilter = null),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _priorityFilter!.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_priorityFilter!.label,
                style: TextStyle(
                    color: _priorityFilter!.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 3),
            Icon(Icons.close_rounded, size: 13, color: _priorityFilter!.color),
          ],
        ),
      ),
    );
  }

  Widget _priorityCard(ThemeData theme, TaskPriority p, int count) {
    final color = p.color;
    final active = _priorityFilter == p;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _priorityFilter = active ? null : p;
          _filter = TaskFilter.all;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: color.withValues(alpha: active ? 0.22 : 0.10),
            borderRadius: BorderRadius.circular(18),
            border: active ? Border.all(color: color, width: 1.4) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.flag_rounded, size: 15, color: color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text('${p.label} priority',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                            fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$count',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text('tasks',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.hintColor, fontSize: 11)),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 16, color: color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Task card (redesigned) ────────────────────────────────────────────────
  Widget _taskCard(BuildContext context, TaskItem task) {
    return Dismissible(
      key: ValueKey(task.id),
      background: _swipeBg(
          alignLeft: true,
          color: AppColors.success,
          icon: task.done ? Icons.undo_rounded : Icons.check_rounded,
          label: task.done ? 'Undo' : 'Done'),
      secondaryBackground: _swipeBg(
          alignLeft: false,
          color: AppColors.danger,
          icon: Icons.delete_outline_rounded,
          label: 'Delete'),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          ref.read(taskControllerProvider).toggle(task);
          return false;
        }
        return true;
      },
      onDismissed: (_) => _deleteWithUndo(context, task),
      child: TaskCard(
        task: task,
        onOpen: () => openEditor(context, task: task),
      ),
    );
  }

  Widget _swipeBg(
      {required bool alignLeft,
      required Color color,
      required IconData icon,
      required String label}) {
    return Container(
      alignment: alignLeft ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// A collapsible "Completed (N)" section shown at the end of the All view.
class _CompletedSection extends StatefulWidget {
  final List<TaskItem> tasks;
  final Widget Function(TaskItem) cardBuilder;
  const _CompletedSection({required this.tasks, required this.cardBuilder});

  @override
  State<_CompletedSection> createState() => _CompletedSectionState();
}

class _CompletedSectionState extends State<_CompletedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Text('Completed (${widget.tasks.length})',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.success)),
                const Spacer(),
                Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.success),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 12),
          for (final t in widget.tasks) widget.cardBuilder(t),
        ],
      ],
    );
  }
}

/// Bottom-sheet editor for adding/editing a task.
class TaskEditorSheet extends ConsumerStatefulWidget {
  final TaskItem? task;
  final TaskType? initialType;
  final DateTime? initialDue;

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
    _subjectId = t?.subjectId;
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
            Text(_isEdit ? 'Edit item' : 'New item',
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
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _type = t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 12),
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
                            Text(t.label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: selected ? t.color : theme.hintColor,
                                  fontWeight: FontWeight.w600,
                                )),
                          ],
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
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. DBMS assignment 2',
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
              initialValue: _subjectId,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Subject (optional)'),
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
