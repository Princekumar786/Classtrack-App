import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../services/rating_prompt_service.dart';
import '../../../../shared/widgets/progress_ring.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../subjects/presentation/providers/subject_providers.dart';
import '../providers/study_providers.dart';

enum _Phase { focus, breakTime }

class FocusScreen extends ConsumerStatefulWidget {
  const FocusScreen({super.key});

  @override
  ConsumerState<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends ConsumerState<FocusScreen> {
  int _focusMin = 25;
  final int _breakMin = 5;
  _Phase _phase = _Phase.focus;
  late int _remaining = _focusMin * 60; // seconds
  bool _running = false;
  Timer? _timer;
  DateTime? _sessionStart;
  String? _subjectId;

  bool get _isIdle => !_running && _sessionStart == null;
  int get _phaseTotal => (_phase == _Phase.focus ? _focusMin : _breakMin) * 60;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _sessionStart ??= DateTime.now();
    setState(() => _running = true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _complete();
      } else {
        setState(() => _remaining--);
      }
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  void _complete() {
    _timer?.cancel();
    HapticFeedback.mediumImpact();
    if (_phase == _Phase.focus) {
      _log(_focusMin);
      _snack('Nice! Logged $_focusMin min. Time for a break ☕');
      unawaited(ref.read(ratingPromptProvider).onHappyMoment(HappyMoment.focusSessionDone));
      setState(() {
        _phase = _Phase.breakTime;
        _remaining = _breakMin * 60;
        _running = false;
        _sessionStart = null;
      });
    } else {
      _snack('Break over — ready for another focus session?');
      setState(() {
        _phase = _Phase.focus;
        _remaining = _focusMin * 60;
        _running = false;
        _sessionStart = null;
      });
    }
  }

  /// Stop early. Logs elapsed focus time (if >= 1 min) then resets to idle.
  void _stop() {
    _timer?.cancel();
    if (_phase == _Phase.focus) {
      final elapsedMin = ((_focusMin * 60 - _remaining) / 60).floor();
      if (elapsedMin >= 1) {
        _log(elapsedMin);
        _snack('Logged $elapsedMin min of focus.');
      }
    }
    setState(() {
      _phase = _Phase.focus;
      _remaining = _focusMin * 60;
      _running = false;
      _sessionStart = null;
    });
  }

  void _log(int minutes) {
    ref.read(studyControllerProvider).logSession(
          minutes: minutes,
          subjectId: _subjectId,
          startedAt: _sessionStart,
        );
  }

  void _adjustFocus(int delta) {
    if (!_isIdle || _phase != _Phase.focus) return;
    setState(() {
      _focusMin = (_focusMin + delta).clamp(5, 120);
      _remaining = _focusMin * 60;
    });
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  String get _timeLabel {
    final m = (_remaining ~/ 60).toString().padLeft(2, '0');
    final s = (_remaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjects = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
    final stats = ref.watch(studyStatsProvider);
    final phaseColor =
        _phase == _Phase.focus ? AppColors.primary : AppColors.success;
    final percent = _phaseTotal == 0
        ? 0.0
        : ((_phaseTotal - _remaining) / _phaseTotal) * 100;
    final subjectName = _subjectId == null
        ? null
        : subjects
            .where((s) => s.id == _subjectId)
            .map((s) => s.name)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            Row(
              children: [
                RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 12),
                Text('Focus timer', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: ProgressRing(
                percent: percent.toDouble(),
                size: 240,
                strokeWidth: 16,
                color: phaseColor,
                centerLabel: _timeLabel,
                subLabel: _phase == _Phase.focus ? 'Focus' : 'Break',
              ),
            ),
            const SizedBox(height: 20),
            if (_isIdle && _phase == _Phase.focus) ...[
              _durationRow(theme),
              const SizedBox(height: 14),
              _subjectPicker(context, subjects),
              const SizedBox(height: 20),
            ],
            _controls(theme),
            const SizedBox(height: 8),
            if (subjectName != null)
              Center(
                child: Text('Studying · $subjectName',
                    style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 24),
            _statsCard(theme, stats),
            const SizedBox(height: 20),
            _recentSessions(context),
          ],
        ),
      ),
    );
  }

  Widget _durationRow(ThemeData theme) {
    Widget preset(int m) {
      final selected = _focusMin == m;
      return GestureDetector(
        onTap: () => setState(() {
          _focusMin = m;
          _remaining = m * 60;
        }),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : theme.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text('$m',
              style: TextStyle(
                  color: selected ? Colors.white : null,
                  fontWeight: FontWeight.w700)),
        ),
      );
    }

    return Column(
      children: [
        Text('Focus length (minutes)', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => _adjustFocus(-5),
              icon: const Icon(Icons.remove_circle_outline_rounded),
            ),
            preset(25),
            preset(45),
            preset(60),
            IconButton(
              onPressed: () => _adjustFocus(5),
              icon: const Icon(Icons.add_circle_outline_rounded),
            ),
          ],
        ),
      ],
    );
  }

  Widget _subjectPicker(BuildContext context, List subjects) {
    return DropdownButtonFormField<String?>(
      initialValue: _subjectId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Subject (optional)'),
      items: [
        const DropdownMenuItem<String?>(
            value: null, child: Text('No subject')),
        for (final s in subjects)
          DropdownMenuItem<String?>(
              value: s.id,
              child: Text(s.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => setState(() => _subjectId = v),
    );
  }

  Widget _controls(ThemeData theme) {
    if (_isIdle) {
      return FilledButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(_phase == _Phase.focus ? 'Start focus' : 'Start break'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _running ? _pause : _start,
            icon: Icon(
                _running ? Icons.pause_rounded : Icons.play_arrow_rounded),
            label: Text(_running ? 'Pause' : 'Resume'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('End'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: AppColors.danger),
          ),
        ),
      ],
    );
  }

  Widget _statsCard(ThemeData theme, StudyStats stats) {
    Widget stat(String value, String label, IconData icon, Color color) {
      return Expanded(
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 8),
            Text(value,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: softCard(context),
      child: Row(
        children: [
          stat(_hm(stats.todayMinutes), 'Today', Icons.today_rounded,
              AppColors.primary),
          stat(_hm(stats.weekMinutes), 'This week',
              Icons.calendar_view_week_rounded, AppColors.info),
          stat('${stats.streakDays}d', 'Streak',
              Icons.local_fire_department_rounded, AppColors.coral),
          stat('${stats.todaySessions}', 'Sessions',
              Icons.timer_rounded, AppColors.success),
        ],
      ),
    );
  }

  Widget _recentSessions(BuildContext context) {
    final theme = Theme.of(context);
    final sessions =
        ref.watch(studySessionsStreamProvider).valueOrNull ?? const [];
    final byId = ref.watch(subjectsByIdProvider);
    if (sessions.isEmpty) return const SizedBox.shrink();
    final recent = sessions.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Recent sessions'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: softCard(context),
          child: Column(
            children: [
              for (final s in recent)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 18, color: AppColors.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.subjectId != null && byId[s.subjectId] != null
                              ? byId[s.subjectId]!.name
                              : 'Focus session',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(_hm(s.minutes),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _hm(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
