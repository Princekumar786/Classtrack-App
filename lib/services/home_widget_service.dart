import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';

import '../core/utils/date_utils.dart';
import '../features/schedule/presentation/providers/schedule_providers.dart';
import '../features/tasks/presentation/providers/task_providers.dart';

/// Pushes a compact "today" snapshot to the Android home-screen widget.
///
/// The native widget (ClassTrackWidgetProvider) reads the saved keys. Every
/// method is wrapped in try/catch so a device without the widget (or iOS
/// without the extension configured) never crashes the app.
class HomeWidgetService {
  static const String androidProvider = 'ClassTrackWidgetProvider';

  /// Last snapshot pushed, so unchanged data (e.g. every attendance tap
  /// re-running the sync) doesn't cost four platform calls each time.
  String? _lastPushed;

  Future<void> update({
    required String title,
    required String line1,
    required String line2,
  }) async {
    final sig = '$title\n$line1\n$line2';
    if (sig == _lastPushed) return;
    _lastPushed = sig;
    try {
      await HomeWidget.saveWidgetData<String>('title', title);
      await HomeWidget.saveWidgetData<String>('line1', line1);
      await HomeWidget.saveWidgetData<String>('line2', line2);
      await HomeWidget.updateWidget(androidName: androidProvider);
    } catch (_) {
      _lastPushed = null; // retry next time
      // No widget installed / unsupported platform — safe to ignore.
    }
  }
}

final homeWidgetServiceProvider =
    Provider<HomeWidgetService>((ref) => HomeWidgetService());

/// Keeps the home-screen widget in sync with today's schedule + tasks while the
/// app is open. Watch once (in HomeShell). Safe no-op if no widget is placed.
final homeWidgetSyncProvider = Provider<void>((ref) {
  final service = ref.watch(homeWidgetServiceProvider);
  final now = DateTime.now();

  final scheduledClasses = ref.watch(allSessionsProvider);
  final today = scheduledClasses
      .where((c) => c.session.occursOn(now))
      .toList()
    ..sort((a, b) => DateUtilsX.minutesOfDay(a.session.startTime)
        .compareTo(DateUtilsX.minutesOfDay(b.session.startTime)));

  final tasks = ref.watch(tasksStreamProvider).valueOrNull ?? const [];
  final dueToday = tasks
      .where((t) =>
          !t.done && t.dueDate != null && DateUtilsX.isSameDay(t.dueDate!, now))
      .length;

  final title = 'Today · ${today.length} class${today.length == 1 ? '' : 'es'}';
  final line1 = today.isEmpty
      ? 'No classes today 🎉'
      : 'Next: ${today.first.subject.name} at ${today.first.session.startTime}';
  final line2 = dueToday == 0
      ? 'No tasks due'
      : '$dueToday task${dueToday == 1 ? '' : 's'} due today';

  service.update(title: title, line1: line1, line2: line2);
});
