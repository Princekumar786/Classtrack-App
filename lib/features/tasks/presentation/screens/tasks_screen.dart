import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/feature_tip_banner.dart';
import '../../../../shared/widgets/placement_slot.dart';
import '../../../../shared/widgets/states.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../cms/domain/marketing.dart';
import '../../../subjects/domain/subject.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../../domain/task_buckets.dart';
import '../../domain/task_item.dart';
import '../providers/task_providers.dart';
import '../widgets/task_card.dart';
import '../widgets/task_editor_sheet.dart';

// Older code imports TaskEditorSheet from this file — keep that working.
export '../widgets/task_editor_sheet.dart';

/// How the active list is ordered. [smart] groups by date
/// (Overdue → Today → Tomorrow → Next 7 days → Later → No date).
enum TaskSort { smart, priority, created }

extension on TaskSort {
  String get label => switch (this) {
        TaskSort.smart => 'Smart (by date)',
        TaskSort.priority => 'Priority',
        TaskSort.created => 'Recently added',
      };

  IconData get icon => switch (this) {
        TaskSort.smart => Icons.auto_awesome_rounded,
        TaskSort.priority => Icons.flag_rounded,
        TaskSort.created => Icons.schedule_rounded,
      };
}

/// Tasks & Assignments.
///
/// Layout, top to bottom:
///   • header with a live summary line, search and a sort/filter menu,
///   • an overview card: progress ring + Overdue / Today / Next 7 days tiles
///     (each tile is a one-tap filter),
///   • type tabs (All · Assignments · To-dos · Events · Videos) with counts,
///   • on Assignments: a subject filter row,
///   • a quick-add bar (type a title, press enter),
///   • the list, grouped by date, then a collapsible Completed section.
///
/// [initialType] opens straight into one tab — Home's "Assignments" quick
/// tool uses `TaskType.assignment`.
class TasksScreen extends ConsumerStatefulWidget {
  final TaskType? initialType;
  const TasksScreen({super.key, this.initialType});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  late TaskType? _type = widget.initialType;
  TaskSort _sort = TaskSort.smart;
  TaskPriority? _priorityFilter;
  TaskBucket? _bucketFilter;
  String? _subjectFilter;
  String _query = '';
  bool _searching = false;
  final _quickAdd = TextEditingController();
  final _quickAddFocus = FocusNode();

  @override
  void dispose() {
    _quickAdd.dispose();
    _quickAddFocus.dispose();
    super.dispose();
  }

  bool get _assignmentsOnly => _type == TaskType.assignment;

  /// The type new items get from this view (the "All" tab → plain task).
  TaskType get _newType => _type ?? TaskType.task;

  /// Due date implied by the active date filter, so a quick-added item lands
  /// in the list the student is looking at.
  DateTime? get _impliedDue {
    final now = DateTime.now();
    return switch (_bucketFilter) {
      TaskBucket.today => DateTime(now.year, now.month, now.day),
      TaskBucket.tomorrow => DateTime(now.year, now.month, now.day + 1),
      _ => null,
    };
  }

  void _openEditor({TaskItem? task, String? title}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => TaskEditorSheet(
        task: task,
        initialType: _newType,
        initialDue: _impliedDue,
        initialSubjectId: _subjectFilter,
        initialTitle: title,
      ),
    );
  }

  Future<void> _submitQuickAdd() async {
    final title = _quickAdd.text.trim();
    if (title.isEmpty) return;
    HapticFeedback.selectionClick();
    _quickAdd.clear();
    await ref.read(taskControllerProvider).add(TaskItem(
          id: '',
          title: title,
          type: _newType,
          subjectId: _subjectFilter,
          dueDate: _impliedDue,
        ));
    if (!mounted) return;
    showQuickFeedback(context, 'Added “$title”');
  }

  Future<void> _clearCompleted(List<TaskItem> done) async {
    if (done.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear completed?'),
        content: Text('Delete ${done.length} completed '
            'item${done.length == 1 ? '' : 's'}? This cannot be undone.'),
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

  void _deleteWithUndo(TaskItem task) {
    final ctrl = ref.read(taskControllerProvider);
    ctrl.delete(task.id);
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Text('Deleted “${task.title}”'),
      action: SnackBarAction(label: 'Undo', onPressed: () => ctrl.add(task)),
    ));
  }

  // ── Filtering ───────────────────────────────────────────────────────────
  bool _matchesQuery(TaskItem t, Map<String, Subject> subjects) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final subject = t.subjectId == null ? null : subjects[t.subjectId];
    return t.title.toLowerCase().contains(q) ||
        (t.note?.toLowerCase().contains(q) ?? false) ||
        (subject?.name.toLowerCase().contains(q) ?? false);
  }

  /// Everything in the current tab (type + subject + search), done or not.
  List<TaskItem> _scoped(List<TaskItem> all, Map<String, Subject> subjects) =>
      all
          .where((t) => _type == null || t.type == _type)
          .where((t) => _subjectFilter == null || t.subjectId == _subjectFilter)
          .where((t) => _matchesQuery(t, subjects))
          .toList();

  int _byPriority(TaskItem a, TaskItem b) {
    if (a.priority != b.priority) {
      return b.priority.index.compareTo(a.priority.index);
    }
    return compareByDueThenPriority(a, b);
  }

  int _byCreated(TaskItem a, TaskItem b) {
    final ac = a.createdAt, bc = b.createdAt;
    if (ac == null && bc == null) return 0;
    if (ac == null) return -1; // just added locally → newest
    if (bc == null) return 1;
    return bc.compareTo(ac);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasksAsync = ref.watch(tasksStreamProvider);
    final all = tasksAsync.valueOrNull ?? const <TaskItem>[];
    final subjects = ref.watch(subjectsByIdProvider);
    final canPop = Navigator.of(context).canPop();
    final title = _assignmentsOnly ? 'Assignments' : 'Tasks';

    return Scaffold(
      floatingActionButton: canPop
          ? FloatingActionButton.extended(
              heroTag: 'tasks_fab',
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_rounded),
              label: Text('New ${_newType.label.toLowerCase()}'),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(theme, canPop, title, all),
            if (_searching) _searchField(),
            Expanded(
              child: tasksAsync.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(tasksStreamProvider)),
                data: (tasks) => _body(theme, tasks, subjects),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────
  Widget _header(
      ThemeData theme, bool canPop, String title, List<TaskItem> all) {
    final scoped = all.where((t) => _type == null || t.type == _type);
    final s = TaskSummary.of(scoped, DateTime.now());
    final parts = <String>[
      if (s.overdue > 0) '${s.overdue} overdue',
      if (s.dueToday > 0) '${s.dueToday} due today',
      if (s.overdue == 0 && s.dueToday == 0 && s.pending > 0)
        '${s.pending} pending',
    ];
    final subtitle = s.total == 0
        ? (_assignmentsOnly
            ? 'Homework, lab records and projects'
            : 'Stay organised. Get things done.')
        : (parts.isEmpty ? 'All caught up 🎉' : parts.join(' · '));
    final done = all
        .where((t) => t.done && (_type == null || t.type == _type))
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          if (canPop) ...[
            RoundIconButton(
              icon: Icons.arrow_back_rounded,
              semanticLabel: 'Back',
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: s.overdue > 0
                            ? AppColors.danger
                            : theme.hintColor,
                        fontWeight:
                            s.overdue > 0 ? FontWeight.w600 : null)),
              ],
            ),
          ),
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
            icon: Icon(
                _searching ? Icons.search_off_rounded : Icons.search_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Sort & filter',
            icon: Badge(
              isLabelVisible:
                  _priorityFilter != null || _sort != TaskSort.smart,
              smallSize: 8,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.tune_rounded),
            ),
            onSelected: (v) {
              if (v == 'clear') {
                _clearCompleted(done);
              } else if (v.startsWith('sort:')) {
                setState(() => _sort = TaskSort.values.byName(v.substring(5)));
              } else if (v.startsWith('prio:')) {
                final name = v.substring(5);
                setState(() => _priorityFilter = name == 'any'
                    ? null
                    : TaskPriorityX.parse(name));
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem<String>(
                  enabled: false, height: 32, child: Text('SORT BY')),
              for (final s in TaskSort.values)
                _menuItem(theme, 'sort:${s.name}', s.icon, s.label,
                    selected: s == _sort),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                  enabled: false, height: 32, child: Text('PRIORITY')),
              _menuItem(theme, 'prio:any', Icons.all_inclusive_rounded,
                  'Any priority',
                  selected: _priorityFilter == null),
              for (final p in TaskPriority.values.reversed)
                _menuItem(theme, 'prio:${p.name}', Icons.flag_rounded,
                    '${p.label} only',
                    selected: _priorityFilter == p, color: p.color),
              if (done.isNotEmpty) ...[
                const PopupMenuDivider(),
                _menuItem(theme, 'clear', Icons.delete_sweep_rounded,
                    'Clear completed (${done.length})',
                    color: AppColors.danger),
              ],
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      ThemeData theme, String value, IconData icon, String label,
      {bool selected = false, Color? color}) {
    final c = selected ? AppColors.primary : (color ?? theme.hintColor);
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.primary : null)),
          ),
          if (selected)
            const Icon(Icons.check_rounded,
                size: 18, color: AppColors.primary),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: TextField(
        autofocus: true,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: _assignmentsOnly
              ? 'Search assignments or subjects'
              : 'Search by title, note or subject',
          prefixIcon: const Icon(Icons.search_rounded),
          isDense: true,
          suffixIcon: IconButton(
            tooltip: 'Close search',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => setState(() {
              _query = '';
              _searching = false;
            }),
          ),
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────
  Widget _body(
      ThemeData theme, List<TaskItem> all, Map<String, Subject> subjects) {
    final now = DateTime.now();
    final scoped = _scoped(all, subjects);
    final summary = TaskSummary.of(scoped, now);

    var pending = scoped.where((t) => !t.done).toList();
    if (_priorityFilter != null) {
      pending = pending.where((t) => t.priority == _priorityFilter).toList();
    }
    if (_bucketFilter != null) {
      pending = pending.where((t) {
        final b = bucketFor(t, now);
        // "Next 7 days" tile includes today + tomorrow, like its count.
        if (_bucketFilter == TaskBucket.thisWeek) {
          return b == TaskBucket.today ||
              b == TaskBucket.tomorrow ||
              b == TaskBucket.thisWeek;
        }
        return b == _bucketFilter;
      }).toList();
    }
    final completed = scoped.where((t) => t.done).toList()
      ..sort(_byCreated);

    // Subjects that actually have items in this tab (for the subject row).
    final subjectIds = <String>{
      for (final t in all)
        if ((_type == null || t.type == _type) &&
            t.subjectId != null &&
            subjects.containsKey(t.subjectId))
          t.subjectId!,
    };

    final children = <Widget>[
      const FeatureTipBanner(
        prefsKey: AppConstants.prefsTipTasks,
        message:
            'Share any YouTube video to ClassTrack to create a task instantly.',
      ),
      const PlacementSlot(placement: Placements.tasks),
      const SizedBox(height: 6),
      _OverviewCard(
        summary: summary,
        assignments: _assignmentsOnly,
        selected: _bucketFilter,
        onSelect: (b) => setState(
            () => _bucketFilter = _bucketFilter == b ? null : b),
      ),
      const SizedBox(height: 16),
      _typeTabs(all),
      if (_assignmentsOnly && subjectIds.isNotEmpty) ...[
        const SizedBox(height: 10),
        _subjectRow(subjectIds.map((id) => subjects[id]!).toList()),
      ],
      const SizedBox(height: 14),
      _quickAddBar(theme),
      if (_priorityFilter != null || _bucketFilter != null) ...[
        const SizedBox(height: 12),
        _activeFilters(theme),
      ],
      const SizedBox(height: 8),
    ];

    if (all.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 24),
        child: EmptyState(
          icon: _assignmentsOnly
              ? Icons.assignment_rounded
              : Icons.check_circle_rounded,
          title: _assignmentsOnly ? 'No assignments yet' : 'No tasks yet',
          message: _assignmentsOnly
              ? 'Add homework, lab records and projects with a subject and a '
                  'due date. You’ll get a reminder before each one is due.'
              : 'Add assignments, deadlines and to-dos. They’ll show up on '
                  'your calendar and dashboard.',
          actionLabel:
              _assignmentsOnly ? 'Add assignment' : 'Add task',
          onAction: () => _openEditor(),
        ),
      ));
    } else if (pending.isEmpty) {
      children.add(_EmptyList(
        caughtUp: _query.isEmpty &&
            _priorityFilter == null &&
            _bucketFilter == null &&
            summary.pending == 0,
        searching: _query.trim().isNotEmpty,
        noun: _type?.pluralLabel.toLowerCase() ?? 'tasks',
      ));
    } else if (_sort == TaskSort.smart) {
      final groups = groupPendingTasks(pending, now);
      var index = 0;
      for (final entry in groups.entries) {
        children.add(_GroupHeader(bucket: entry.key, count: entry.value.length));
        for (final t in entry.value) {
          children.add(_swipeable(t).listEntrance(index++));
        }
      }
    } else {
      final sorted = [...pending]
        ..sort(_sort == TaskSort.priority ? _byPriority : _byCreated);
      children.add(const SizedBox(height: 6));
      for (var i = 0; i < sorted.length; i++) {
        children.add(_swipeable(sorted[i]).listEntrance(i));
      }
    }

    if (completed.isNotEmpty) {
      children.add(const SizedBox(height: 10));
      children.add(_CompletedSection(
        tasks: completed,
        cardBuilder: _swipeable,
      ));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
      children: children,
    );
  }

  // ── Type tabs ──────────────────────────────────────────────────────────
  Widget _typeTabs(List<TaskItem> all) {
    int countOf(TaskType? type) =>
        all.where((t) => !t.done && (type == null || t.type == type)).length;

    Widget tab(TaskType? type) {
      final n = countOf(type);
      final label = type?.pluralLabel ?? 'All';
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          label: '$label, $n pending',
          selected: _type == type,
          button: true,
          excludeSemantics: true,
          child: FilterPill(
            label: n > 0 ? '$label  $n' : label,
            icon: type?.icon ?? Icons.layers_rounded,
            accent: type?.color,
            selected: _type == type,
            onTap: () => setState(() {
              _type = type;
              _subjectFilter = null;
            }),
          ),
        ),
      );
    }

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        children: [
          tab(null),
          // Assignments first: it's the most common student item.
          tab(TaskType.assignment),
          tab(TaskType.task),
          tab(TaskType.event),
          tab(TaskType.video),
        ],
      ),
    );
  }

  Widget _subjectRow(List<Subject> subjects) {
    subjects.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _SubjectChip(
              label: 'All subjects',
              color: AppColors.accent,
              selected: _subjectFilter == null,
              onTap: () => setState(() => _subjectFilter = null),
            ),
          ),
          for (final s in subjects)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SubjectChip(
                label: s.name,
                color: Color(s.colorHex),
                selected: _subjectFilter == s.id,
                onTap: () => setState(() =>
                    _subjectFilter = _subjectFilter == s.id ? null : s.id),
              ),
            ),
        ],
      ),
    );
  }

  // ── Quick add ──────────────────────────────────────────────────────────
  Widget _quickAddBar(ThemeData theme) {
    final color = _newType.color;
    final hint = switch (_bucketFilter) {
      TaskBucket.today => 'Add ${_article(_newType)} for today…',
      TaskBucket.tomorrow => 'Add ${_article(_newType)} for tomorrow…',
      _ => 'Add ${_article(_newType)}…',
    };
    return Container(
      decoration: softCard(context, radius: 18),
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      child: Row(
        children: [
          Icon(Icons.add_circle_rounded, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _quickAdd,
              focusNode: _quickAddFocus,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) async {
                await _submitQuickAdd();
                // Keep the keyboard up so several items can be typed in a row.
                if (mounted) _quickAddFocus.requestFocus();
              },
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Add with details',
            icon: Icon(Icons.open_in_full_rounded,
                size: 20, color: theme.hintColor),
            onPressed: () {
              final text = _quickAdd.text.trim();
              _quickAdd.clear();
              _openEditor(title: text.isEmpty ? null : text);
            },
          ),
        ],
      ),
    );
  }

  static String _article(TaskType t) => switch (t) {
        TaskType.assignment => 'an assignment',
        TaskType.event => 'an event',
        TaskType.video => 'a video',
        TaskType.task => 'a task',
      };

  Widget _activeFilters(ThemeData theme) {
    Widget chip(String label, Color color, VoidCallback onClear) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InputChip(
            label: Text(label),
            labelStyle: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 12),
            backgroundColor: color.withValues(alpha: 0.12),
            side: BorderSide.none,
            deleteIconColor: color,
            onDeleted: onClear,
            visualDensity: VisualDensity.compact,
          ),
        );
    return Wrap(
      children: [
        if (_bucketFilter != null)
          chip(_bucketFilter!.label, _bucketColor(_bucketFilter!),
              () => setState(() => _bucketFilter = null)),
        if (_priorityFilter != null)
          chip('${_priorityFilter!.label} priority', _priorityFilter!.color,
              () => setState(() => _priorityFilter = null)),
      ],
    );
  }

  // ── Rows ───────────────────────────────────────────────────────────────
  Widget _swipeable(TaskItem task) {
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
          HapticFeedback.selectionClick();
          ref.read(taskControllerProvider).toggle(task);
          return false;
        }
        return true;
      },
      onDismissed: (_) => _deleteWithUndo(task),
      child: TaskCard(task: task, onOpen: () => _openEditor(task: task)),
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
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

Color _bucketColor(TaskBucket b) => switch (b) {
      TaskBucket.overdue => AppColors.danger,
      TaskBucket.today => AppColors.warning,
      TaskBucket.tomorrow => AppColors.info,
      TaskBucket.thisWeek => AppColors.primary,
      TaskBucket.later => AppColors.primaryLight,
      TaskBucket.noDate => AppColors.cancelled,
    };

/// The gradient overview card: progress ring + three tappable count tiles.
class _OverviewCard extends StatelessWidget {
  final TaskSummary summary;
  final bool assignments;
  final TaskBucket? selected;
  final ValueChanged<TaskBucket> onSelect;

  const _OverviewCard({
    required this.summary,
    required this.assignments,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    final pct = (s.progress * 100).round();
    final noun = assignments
        ? (s.pending == 1 ? 'assignment' : 'assignments')
        : (s.pending == 1 ? 'task' : 'tasks');
    final headline = s.pending == 0
        ? (s.total == 0 ? 'Nothing planned yet' : 'All caught up!')
        : '${s.pending} $noun to do';
    final sub = s.total == 0
        ? 'Add your first one below.'
        : '${s.completed} of ${s.total} done';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: assignments
              ? const [Color(0xFFF7A93B), Color(0xFFEA7A2B)]
              : const [AppColors.primaryLight, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: theme.brightness == Brightness.light
            ? AppColors.softShadow(opacity: 0.20, blur: 20)
            : null,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.15)),
                    const SizedBox(height: 4),
                    Text(sub,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9))),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                label: '$pct percent done',
                excludeSemantics: true,
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: s.progress),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) => CircularProgressIndicator(
                          value: v,
                          strokeWidth: 7,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Colors.white.withValues(alpha: 0.25),
                          valueColor:
                              const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      Center(
                        child: Text('$pct%',
                            style: theme.textTheme.titleSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _tile(context, TaskBucket.overdue, 'Overdue', s.overdue,
                  Icons.error_outline_rounded),
              const SizedBox(width: 8),
              _tile(context, TaskBucket.today, 'Today', s.dueToday,
                  Icons.wb_sunny_rounded),
              const SizedBox(width: 8),
              _tile(context, TaskBucket.thisWeek, 'Next 7 days',
                  s.dueThisWeek, Icons.date_range_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, TaskBucket bucket, String label,
      int count, IconData icon) {
    final theme = Theme.of(context);
    final active = selected == bucket;
    final alert = bucket == TaskBucket.overdue && count > 0;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: '$label, $count. Tap to filter',
        excludeSemantics: true,
        child: Material(
          color: active
              ? Colors.white
              : Colors.white.withValues(alpha: alert ? 0.24 : 0.16),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelect(bucket),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon,
                          size: 14,
                          color: active ? _bucketColor(bucket) : Colors.white),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: active
                                    ? AppColors.ink
                                    : Colors.white.withValues(alpha: 0.92),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('$count',
                      style: theme.textTheme.titleLarge?.copyWith(
                          color: active ? _bucketColor(bucket) : Colors.white,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section title inside the smart list ("Overdue · 2").
class _GroupHeader extends StatelessWidget {
  final TaskBucket bucket;
  final int count;
  const _GroupHeader({required this.bucket, required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _bucketColor(bucket);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(bucket.label,
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: bucket == TaskBucket.overdue ? color : null)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: color, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: theme.dividerColor, height: 1)),
          ],
        ),
      ),
    );
  }
}

class _SubjectChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _SubjectChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? color.withValues(alpha: 0.16) : theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color: selected ? color : theme.dividerColor, width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when the current filters leave nothing pending.
class _EmptyList extends StatelessWidget {
  final bool caughtUp;
  final bool searching;
  final String noun;
  const _EmptyList(
      {required this.caughtUp, required this.searching, required this.noun});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, body) = searching
        ? (Icons.search_off_rounded, 'No matches', 'Try another word.')
        : caughtUp
            ? (
                Icons.celebration_rounded,
                'All caught up!',
                'No pending $noun. Enjoy the break — or add the next one above.'
              )
            : (
                Icons.filter_alt_off_rounded,
                'Nothing here',
                'No pending $noun match these filters.'
              );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: (caughtUp ? AppColors.success : AppColors.primary)
                  .withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 30,
                color: caughtUp ? AppColors.success : AppColors.primary),
          ),
          const SizedBox(height: 12),
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        ],
      ),
    );
  }
}

/// A collapsible "Completed (N)" section at the end of the list.
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
        Semantics(
          button: true,
          expanded: _expanded,
          child: Material(
            color: AppColors.success.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: AppColors.success),
                    ),
                  ],
                ),
              ),
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
