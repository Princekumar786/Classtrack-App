import 'package:flutter_test/flutter_test.dart';

import 'package:classtrack/core/providers/notification_prefs_provider.dart';
import 'package:classtrack/features/schedule/domain/class_session.dart';
import 'package:classtrack/features/subjects/domain/subject.dart';
import 'package:classtrack/features/tasks/domain/task_item.dart';
import 'package:classtrack/services/reminder_scheduler.dart';
import 'package:classtrack/services/reminder_sync_runner.dart';

/// Guards the "app froze for ~2 minutes" fix: reminder re-scheduling must run
/// one job at a time, collapse bursts, and skip unchanged inputs — and an
/// attendance mark (counter change) must NOT count as a schedule change.
void main() {
  const tick = Duration(milliseconds: 10);
  Future<void> settle([int ms = 80]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('ReminderSyncRunner', () {
    test('a burst of submits runs only the latest job, once', () async {
      final runner = ReminderSyncRunner(debounce: tick);
      final ran = <String>[];
      for (var i = 0; i < 20; i++) {
        runner.submit('sig$i', () async => ran.add('sig$i'));
      }
      await settle();
      expect(ran, ['sig19']);
    });

    test('an unchanged signature is skipped', () async {
      final runner = ReminderSyncRunner(debounce: tick);
      var runs = 0;
      runner.submit('a', () async => runs++);
      await settle();
      runner.submit('a', () async => runs++);
      await settle();
      expect(runs, 1);
      expect(runner.appliedSignature, 'a');
    });

    test('jobs never overlap; a submit during a run is applied after it',
        () async {
      final runner = ReminderSyncRunner(debounce: tick);
      var active = 0, maxActive = 0;
      final order = <String>[];
      Future<void> Function() job(String name) => () async {
            active++;
            if (active > maxActive) maxActive = active;
            await Future<void>.delayed(const Duration(milliseconds: 100));
            order.add(name);
            active--;
          };
      runner.submit('a', job('a'));
      await settle(40); // 'a' is now running
      expect(runner.isRunning, isTrue);
      runner.submit('b', job('b'));
      runner.submit('c', job('c'));
      await settle(400);
      expect(order, ['a', 'c']);
      expect(maxActive, 1);
    });

    test('a failing job is reported and retried on the next submit',
        () async {
      final errors = <Object>[];
      final runner =
          ReminderSyncRunner(debounce: tick, onError: (e, _) => errors.add(e));
      runner.submit('a', () async => throw StateError('alarm limit'));
      await settle();
      expect(errors, hasLength(1));
      expect(runner.appliedSignature, isNull);
      var retried = false;
      runner.submit('a', () async => retried = true);
      await settle();
      expect(retried, isTrue);
    });

    test('reset forces the same signature to run again', () async {
      final runner = ReminderSyncRunner(debounce: tick);
      var runs = 0;
      runner.submit('a', () async => runs++);
      await settle();
      runner.reset();
      runner.submit('a', () async => runs++);
      await settle();
      expect(runs, 2);
    });
  });

  group('reminderScheduleSignature', () {
    const session = ClassSession(
      id: 'mon',
      subjectId: 's1',
      recurring: true,
      dayOfWeek: 0,
      startTime: '09:00',
      endTime: '10:00',
    );
    Subject subject({int attended = 0, int absent = 0, String name = 'DBMS'}) =>
        Subject(
          id: 's1',
          name: name,
          colorHex: 0xFF6C5CE7,
          attended: attended,
          absent: absent,
        );
    String sig({
      Subject? s,
      List<ClassSession> sessions = const [session],
      List<TaskItem> tasks = const [],
      NotificationPrefs prefs = const NotificationPrefs(),
    }) =>
        reminderScheduleSignature(
          prefs: prefs,
          lead: 10,
          classes: {'s1': (subject: s ?? subject(), sessions: sessions)},
          tasks: tasks,
          exams: const [],
          habits: const [],
        );

    test('marking attendance (counter change) does not change it', () {
      expect(sig(s: subject(attended: 5, absent: 1)), sig(s: subject()));
    });

    test('timetable, name, task and prefs changes do change it', () {
      final base = sig();
      expect(sig(sessions: [session.copyWith(startTime: '11:00')]),
          isNot(base));
      expect(sig(s: subject(name: 'OS')), isNot(base));
      expect(sig(tasks: const [TaskItem(id: 't', title: 'HW')]), isNot(base));
      expect(sig(prefs: const NotificationPrefs(classes: false)),
          isNot(base));
    });
  });
}
