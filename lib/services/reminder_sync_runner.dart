import 'dart:async';

/// Runs reminder re-scheduling jobs ONE AT A TIME, skips jobs whose inputs
/// haven't changed, and collapses bursts into a single run.
///
/// ## Why this exists
/// `reminderSyncProvider` re-runs whenever the subjects stream emits — and
/// every attendance mark rewrites the subject's counters, so it emits on every
/// tap (twice: local write + server ack). Each run cancelled and re-scheduled
/// EVERY class reminder, check-in, task, exam and habit notification, without
/// awaiting. On Android each of those calls runs on the main thread and
/// rewrites the plugin's saved-notifications list, so a burst of marks (or a
/// batch of offline marks syncing at once) piled up hundreds of overlapping
/// calls. That clogged the platform channel that Firestore and navigation also
/// use, so the app looked frozen for a minute or two, and any failure inside
/// them escaped as an uncaught error (reported to PostHog/Crashlytics).
///
/// Pure Dart (no Flutter) so the ordering rules are unit-testable.
class ReminderSyncRunner {
  ReminderSyncRunner({
    this.debounce = const Duration(milliseconds: 400),
    this.onError,
  });

  /// Quiet period before a submitted job starts; later submits restart it.
  final Duration debounce;

  /// Called when a job throws. The job is then retried on the next submit.
  final void Function(Object error, StackTrace stack)? onError;

  String? _applied;
  String? _pendingSig;
  Future<void> Function()? _pendingJob;
  Timer? _timer;
  bool _running = false;
  bool _disposed = false;

  /// Signature of the last job that completed successfully.
  String? get appliedSignature => _applied;

  /// True while a job is executing.
  bool get isRunning => _running;

  /// Queues [job] for [signature]. Only the LATEST submitted job runs; it is
  /// skipped entirely when [signature] equals the last applied one.
  void submit(String signature, Future<void> Function() job) {
    if (_disposed) return;
    _pendingSig = signature;
    _pendingJob = job;
    _timer?.cancel();
    _timer = Timer(debounce, _drain);
  }

  /// Forgets the last applied signature so the next submit always runs (use
  /// when reminders were cleared elsewhere, e.g. turned off).
  void reset() {
    _applied = null;
    _pendingSig = null;
    _pendingJob = null;
    _timer?.cancel();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _pendingJob = null;
    _pendingSig = null;
  }

  Future<void> _drain() async {
    if (_running) return; // the active loop picks up the newest job
    _running = true;
    try {
      while (_pendingJob != null && !_disposed) {
        final sig = _pendingSig!;
        final job = _pendingJob!;
        _pendingSig = null;
        _pendingJob = null;
        if (sig == _applied) continue;
        try {
          await job();
          _applied = sig;
        } catch (e, st) {
          _applied = null; // retry next time
          onError?.call(e, st);
        }
      }
    } finally {
      _running = false;
    }
  }
}
