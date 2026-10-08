// End-to-end chat behaviour against an in-memory Firestore with scripted AI
// replies — covers the reported failures: "spent 120 on aws" not logging,
// 12h/24h display requests, and fixing classes entered without PM.
import 'package:classtrack/core/providers/app_settings_provider.dart';
import 'package:classtrack/core/providers/firebase_providers.dart';
import 'package:classtrack/core/providers/gemini_provider.dart';
import 'package:classtrack/features/chat/presentation/providers/chat_providers.dart';
import 'package:classtrack/features/expenses/presentation/providers/expense_providers.dart';
import 'package:classtrack/features/schedule/presentation/providers/schedule_providers.dart';
import 'package:classtrack/features/subjects/presentation/providers/subject_providers.dart';
import 'package:classtrack/features/subscription/presentation/providers/subscription_providers.dart';
import 'package:classtrack/features/tasks/presentation/providers/task_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:classtrack/services/analytics_service.dart';
import 'package:classtrack/services/gemini_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _ScriptedGemini extends GeminiService {
  _ScriptedGemini(this.reply) : super(_NoFunctions());
  String reply;

  /// When set, successive calls return these in order (then [reply]).
  List<String> queue = [];
  int calls = 0;
  String? lastContext;
  @override
  Future<String> chat(List<Map<String, dynamic>> history, {String? context}) async {
    calls++;
    lastContext = context;
    return queue.isNotEmpty ? queue.removeAt(0) : reply;
  }
}

class _NoopAnalytics extends AnalyticsService {
  @override
  Future<void> log(String name, [Map<String, Object>? params]) async {}
}

const uid = 'u1';

Future<(ProviderContainer, FakeFirebaseFirestore, _ScriptedGemini)> _setup() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = FakeFirebaseFirestore();
  final subj = db.collection('users').doc(uid).collection('subjects').doc('la');
  await subj.set({'name': 'Linear Algebra', 'colorHex': 0xFF6C5CE7, 'attended': 10, 'absent': 2});
  // Entered as "1:40–2:30" meaning PM, stored as morning times.
  await subj.collection('sessions').doc('s1').set({
    'recurring': true, 'dayOfWeek': 0, 'startTime': '01:40', 'endTime': '02:30', 'cancelledOn': [],
  });
  // A genuine morning class that must not move.
  await subj.collection('sessions').doc('s2').set({
    'recurring': true, 'dayOfWeek': 2, 'startTime': '09:30', 'endTime': '10:20', 'cancelledOn': [],
  });
  final gemini = _ScriptedGemini('');
  // A video task and an AWS expense, as in the reported bugs.
  final user = db.collection('users').doc(uid);
  await user.collection('tasks').doc('t1').set({
    'title': 'Microsoft Fabric end-to-end tutorial', 'type': 'video', 'done': false,
    'priority': 'medium', 'subtasks': [],
  });
  await user.collection('tasks').doc('t2').set({
    'title': 'OS assignment', 'type': 'task', 'done': false, 'priority': 'high', 'subtasks': [],
  });
  await user.collection('expenses').doc('x1').set({
    'title': 'Aws', 'amount': 120, 'category': 'other', 'date': Timestamp.now(),
  });
  final c = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    currentUidProvider.overrideWithValue(uid),
    sharedPrefsProvider.overrideWithValue(prefs),
    geminiServiceProvider.overrideWithValue(gemini),
    analyticsProvider.overrideWithValue(_NoopAnalytics()),
    isProProvider.overrideWith((ref) => true),
  ]);
  // Keep the data streams alive like the chat screen does.
  c.listen(subjectsStreamProvider, (_, __) {});
  c.listen(expensesStreamProvider, (_, __) {});
  c.listen(tasksStreamProvider, (_, __) {});
  c.listen(sessionsForSubjectProvider('la'), (_, __) {});
  await Future<void>.delayed(const Duration(milliseconds: 50));
  return (c, db, gemini);
}

String _lastReply(ProviderContainer c) => c.read(chatControllerProvider).messages.last.text;

void main() {
  test('"spent 120 on aws" is logged even when the model only asks a question', () async {
    final (c, db, gemini) = await _setup();
    addTearDown(c.dispose);
    gemini.reply = 'Sure! Which category should I put that under?';

    await c.read(chatControllerProvider.notifier).send('spent 120 on aws');

    final rows = (await db.collection('users').doc(uid).collection('expenses').get())
        .docs.where((d) => d.id != 'x1').toList(); // x1 = the pre-seeded AWS spend
    expect(rows, hasLength(1));
    expect(rows.single['amount'], 120);
    expect(rows.single['category'], 'other');
    expect(_lastReply(c), contains('logged'));
    expect(_lastReply(c), contains('120'));
  });

  test('when the model DOES log the expense, it is not logged twice', () async {
    final (c, db, gemini) = await _setup();
    addTearDown(c.dispose);
    gemini.reply = 'Done — logged ₹20 for samosa.\n```actions\n'
        '{"actions":[{"type":"expense","title":"Samosa","amount":20,"category":"food"}]}\n```';

    await c.read(chatControllerProvider.notifier).send('I spent 20 on samosa');

    final rows = (await db.collection('users').doc(uid).collection('expenses').get())
        .docs.where((d) => d.id != 'x1').toList();
    expect(rows, hasLength(1));
  });

  test('"show my classes in 12h" switches the app time format', () async {
    final (c, _, gemini) = await _setup();
    addTearDown(c.dispose);
    gemini.reply = 'Done — times now show in 12-hour format.\n```actions\n'
        '{"actions":[{"type":"setting","timeFormat":"12h"}]}\n```';

    await c.read(chatControllerProvider.notifier).send('I want every class displayed in 12h format');

    expect(c.read(timeFormatProvider), TimeFormatPref.twelveHour);
    expect(c.read(timeFormatProvider).use24, isFalse);
  });

  test('"change all my PM classes" fixes AM-entered times and leaves mornings alone', () async {
    final (c, db, gemini) = await _setup();
    addTearDown(c.dispose);
    gemini.reply = 'Done — moved your afternoon classes to PM.\n```actions\n'
        '{"actions":[{"type":"fixClassTimes","subject":null,"day":null}]}\n```';

    await c.read(chatControllerProvider.notifier).send('Change all my PM classes to 24 hr format');

    final sessions = db.collection('users').doc(uid).collection('subjects').doc('la').collection('sessions');
    final s1 = await sessions.doc('s1').get();
    final s2 = await sessions.doc('s2').get();
    expect((s1['startTime'], s1['endTime']), ('13:40', '14:30'));
    expect((s2['startTime'], s2['endTime']), ('09:30', '10:20'));
    expect(_lastReply(c), isNot(contains("couldn't find")));
  });

  test('the AI is told the time format and about AM-entered classes', () async {
    final (c, _, gemini) = await _setup();
    addTearDown(c.dispose);
    gemini.reply = 'Hi!';
    await c.read(chatControllerProvider.notifier).send('hi');
    expect(gemini.lastContext, contains('App time format setting: Auto'));
    expect(gemini.lastContext, contains('likely afternoon times entered without PM'));
  });

  // ── Hallucinated "done" — the reported bugs ─────────────────────────────

  Future<Map<String, dynamic>> task(FakeFirebaseFirestore db, String id) async =>
      (await db.collection('users').doc(uid).collection('tasks').doc(id).get()).data()!;

  test('"mark complete the microsoft fabric video" really completes it '
      '(loose name + "completed" field)', () async {
    final (c, db, gemini) = await _setup();
    addTearDown(c.dispose);
    gemini.reply = 'Done — marked it complete! ✅\n```actions\n'
        '{"actions":[{"type":"update","entity":"task","match":"microsoft fabric video","completed":true}]}\n```';

    await c.read(chatControllerProvider.notifier).send('mark complete the microsoft fabric video');

    expect((await task(db, 't1'))['done'], isTrue);
    expect((await task(db, 't2'))['done'], isFalse); // the other task untouched
  });

  test('a "Done" with no action is retried, and the retry is executed', () async {
    final (c, db, gemini) = await _setup();
    addTearDown(c.dispose);
    gemini.queue = [
      "I've marked the Microsoft Fabric video as complete!", // no actions block
      'Done — marked complete.\n```actions\n'
          '{"actions":[{"type":"update","entity":"task","match":"Microsoft Fabric end-to-end tutorial","done":true}]}\n```',
    ];

    await c.read(chatControllerProvider.notifier).send('mark complete the microsoft fabric video');

    expect(gemini.calls, 2);
    expect((await task(db, 't1'))['done'], isTrue);
  });

  test('a "Done" with no action, even after the retry, is NOT shown as done', () async {
    final (c, db, gemini) = await _setup();
    addTearDown(c.dispose);
    gemini.reply = "Done — I've deleted the AWS expense.";

    await c.read(chatControllerProvider.notifier).send('delete the aws spend');

    expect(_lastReply(c), contains("haven't actually changed anything"));
    final rows = await db.collection('users').doc(uid).collection('expenses').get();
    expect(rows.docs, hasLength(1)); // still there — and the reply says so
  });

  test('deleting the AWS spend asks for confirmation, then really deletes', () async {
    final (c, db, gemini) = await _setup();
    addTearDown(c.dispose);
    gemini.reply = 'Deleting your AWS expense.\n```actions\n'
        '{"actions":[{"type":"delete","entity":"expense","match":"the aws spend","amount":120,"category":"other"}]}\n```';
    final ctrl = c.read(chatControllerProvider.notifier);

    await ctrl.send('delete the aws spend');
    final card = c.read(chatControllerProvider).messages.last;
    expect(card.hasPendingActions, isTrue);
    expect(card.text, contains('confirm'));

    await ctrl.confirmPendingActions(card);
    final rows = await db.collection('users').doc(uid).collection('expenses').get();
    expect(rows.docs, isEmpty);
    expect(_lastReply(c), contains('deleted 1 item'));
  });

  test('an update that changes nothing is reported honestly', () async {
    final (c, db, gemini) = await _setup();
    addTearDown(c.dispose);
    gemini.reply = 'Done!\n```actions\n'
        '{"actions":[{"type":"update","entity":"task","match":"OS assignment"}]}\n```';

    await c.read(chatControllerProvider.notifier).send('update my OS assignment');

    expect(_lastReply(c), contains('nothing was changed'));
  });

  test('ambiguous names are not guessed', () async {
    final (c, db, gemini) = await _setup();
    addTearDown(c.dispose);
    await db.collection('users').doc(uid).collection('tasks').doc('t3').set({
      'title': 'Microsoft Fabric quiz', 'type': 'task', 'done': false, 'priority': 'low', 'subtasks': [],
    });
    await Future<void>.delayed(const Duration(milliseconds: 30));
    gemini.reply = 'Done!\n```actions\n'
        '{"actions":[{"type":"update","entity":"task","match":"microsoft fabric","done":true}]}\n```';

    await c.read(chatControllerProvider.notifier).send('mark microsoft fabric done');

    expect((await task(db, 't1'))['done'], isFalse);
    expect((await task(db, 't3'))['done'], isFalse);
    expect(_lastReply(c), contains('nothing was changed'));
  });
}
