import 'package:classtrack/features/learning_planner/domain/learning_plan.dart';
import 'package:classtrack/features/learning_planner/domain/learning_plan_generator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Demo student used ONLY for store screenshots. Realistic, internally
/// consistent data (attendance %, grades, deadlines all line up) so every
/// screen tells the same believable story.

DateTime _d(int addDays, [int h = 0, int m = 0]) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + addDays, h, m);
}

String _dateId(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Weekday index used by ClassSession (Mon=0..Sun=6).
int _wd(int addDays) => _d(addDays).weekday - 1;

class _Subj {
  const _Subj(this.id, this.name, this.color, this.icon, this.prof, this.room,
      this.attended, this.absent, this.credits);
  final String id, name, prof, room, icon;
  final int color, attended, absent, credits;
}

const subjects = [
  _Subj('dsa', 'Data Structures & Algorithms', 0xFF6C5CE7, 'code', 'Dr. Ananya Rao', 'LH-204', 31, 3, 4),
  _Subj('os', 'Operating Systems', 0xFF0EA5E9, 'computer', 'Prof. Vikram Iyer', 'LH-112', 26, 5, 4),
  _Subj('la', 'Linear Algebra', 0xFFF59E0B, 'function', 'Dr. Meera Kulkarni', 'Block C-301', 20, 8, 3),
  _Subj('cn', 'Computer Networks', 0xFF22C55E, 'network', 'Prof. Arjun Menon', 'Lab 2', 24, 4, 4),
  _Subj('dbms', 'Database Systems', 0xFFEC4899, 'data', 'Dr. Kavya Shah', 'LH-210', 18, 2, 3),
];

const demoAssistantReply =
    'Here’s your Monday:\n\n'
    '• 9:00 – 10:00 · Data Structures & Algorithms (LH-204)\n'
    '• 11:00 – 12:00 · Linear Algebra (Block C-301)\n'
    '• 2:00 – 3:30 · Computer Networks lab (Lab 2)\n\n'
    'You’re free from 12:00 to 2:00 and after 3:30. Your OS assignment is due '
    'Tuesday, so the 12:00 gap is a good slot to finish it.\n\n'
    'Heads-up: Linear Algebra is at 71% — attend your next 4 classes to get '
    'back above your 75% target.';

/// Id of the seeded learning plan (set by [seedDemoAccount]).
String demoPlanId = '';

Future<void> seedDemoAccount(FirebaseFirestore db, String uid) async {
  final user = db.collection('users').doc(uid);
  await user.set({
    'displayName': 'Aarav Mehta',
    'email': 'aarav@example.edu',
    'avatarCharacter': 'icons8-aang-144.png',
    'targetAttendancePercent': 75.0,
    'monthlyBudget': 8000.0,
    'currency': '₹',
    'country': 'India',
    'degree': 'B.Tech',
    'department': 'Computer Science',
    'academicYear': 3,
    'careerGoal': 'Internship',
    'interests': ['AI', 'Programming', 'Data Science'],
    'createdAt': Timestamp.fromDate(_d(-60)),
  });

  // ── Subjects + weekly timetable ──────────────────────────────────────────
  // Today always has a full, realistic day regardless of the capture date.
  final timetable = <String, List<(int, String, String)>>{
    'dsa': [(_wd(0), '09:00', '10:00'), (_wd(2), '09:00', '10:00'), (_wd(4), '10:00', '11:00')],
    'la': [(_wd(0), '11:00', '12:00'), (_wd(3), '11:00', '12:00')],
    'cn': [(_wd(0), '14:00', '15:30'), (_wd(2), '14:00', '15:30')],
    'os': [(_wd(0), '16:00', '17:00'), (_wd(1), '10:00', '11:00'), (_wd(3), '09:00', '10:00')],
    'dbms': [(_wd(1), '12:00', '13:00'), (_wd(4), '14:00', '15:00')],
  };
  for (final s in subjects) {
    final ref = user.collection('subjects').doc(s.id);
    await ref.set({
      'name': s.name,
      'colorHex': s.color,
      'professor': s.prof,
      'credits': s.credits,
      'room': s.room,
      'resourceLinks': [],
      'attended': s.attended,
      'absent': s.absent,
      'held': s.attended + s.absent,
      'cancelled': 0,
      'targetPercent': null,
      'startDate': Timestamp.fromDate(_d(-70)),
      'endDate': Timestamp.fromDate(_d(50)),
      'iconKey': s.icon,
      'createdAt': Timestamp.fromDate(_d(-70)),
    });
    var i = 0;
    for (final (day, start, end) in timetable[s.id]!) {
      await ref.collection('sessions').doc('${s.id}_${i++}').set({
        'recurring': true,
        'dayOfWeek': day,
        'specificDate': null,
        'startTime': start,
        'endTime': end,
        'room': s.room,
        'cancelledOn': [],
      });
    }
  }
  // This morning's first class is already marked present.
  final today = _d(0);
  await user.collection('subjects').doc('dsa').collection('attendance')
      .doc('${_dateId(today)}__0900').set({
    'dateId': _dateId(today),
    'slot': '09:00',
    'date': Timestamp.fromDate(today),
    'status': 'present',
    'markedAt': Timestamp.fromDate(_d(0, 10, 2)),
  });

  // ── Tasks ────────────────────────────────────────────────────────────────
  final tasks = [
    ('t1', 'OS assignment: process scheduling', 'os', _d(1, 23, 59), 'high', false),
    ('t2', 'DBMS mini-project: ER diagram', 'dbms', _d(3, 18, 0), 'medium', false),
    ('t3', 'Networks lab record', 'cn', _d(0, 20, 0), 'medium', false),
    ('t4', 'Read Cormen ch. 15 — dynamic programming', 'dsa', _d(5, 21, 0), 'low', false),
    ('t5', 'Linear Algebra problem set 6', 'la', _d(-1, 17, 0), 'medium', true),
  ];
  for (final (id, title, subj, due, pri, done) in tasks) {
    await user.collection('tasks').doc(id).set({
      'title': title,
      'note': null,
      'subjectId': subj,
      'dueDate': Timestamp.fromDate(due),
      'done': done,
      'priority': pri,
      'type': 'task',
      'link': null,
      'thumbnail': null,
      'subtasks': id == 't1'
          ? [
              {'text': 'FCFS & SJF examples', 'done': true},
              {'text': 'Round-robin Gantt chart', 'done': true},
              {'text': 'Write-up', 'done': false},
            ]
          : [],
      'sourceId': null,
      'createdAt': Timestamp.fromDate(_d(-4)),
    });
  }

  // ── Exams ────────────────────────────────────────────────────────────────
  final exams = [
    ('e1', 'DSA mid-semester exam', 'dsa', _d(6, 10, 0), 'Exam Hall A',
        [('Trees & BSTs', true), ('Graphs', true), ('Dynamic programming', false), ('Greedy', false)]),
    ('e2', 'Linear Algebra quiz 3', 'la', _d(9, 11, 0), 'Block C-301',
        [('Eigenvalues', true), ('Diagonalisation', false)]),
    ('e3', 'Operating Systems mid-sem', 'os', _d(13, 14, 0), 'Exam Hall B',
        [('Processes & threads', true), ('Scheduling', true), ('Deadlocks', false), ('Memory', false)]),
  ];
  for (final (id, title, subj, date, room, topics) in exams) {
    await user.collection('exams').doc(id).set({
      'title': title,
      'subjectId': subj,
      'date': Timestamp.fromDate(date),
      'room': room,
      'note': null,
      'topics': [for (final (t, done) in topics) {'text': t, 'done': done}],
      'createdAt': Timestamp.fromDate(_d(-10)),
    });
  }

  // ── Grades ───────────────────────────────────────────────────────────────
  final grades = [
    ('g1', 'dsa', 'Quiz 1', 18.0, 20.0, 10.0),
    ('g2', 'dsa', 'Assignment 1', 46.0, 50.0, 15.0),
    ('g3', 'dsa', 'Lab evaluation', 27.0, 30.0, 15.0),
    ('g4', 'os', 'Quiz 1', 15.0, 20.0, 10.0),
    ('g5', 'os', 'Assignment 1', 41.0, 50.0, 15.0),
    ('g6', 'la', 'Quiz 1', 14.0, 20.0, 10.0),
    ('g7', 'la', 'Quiz 2', 16.0, 20.0, 10.0),
    ('g8', 'cn', 'Lab 1–4', 36.0, 40.0, 20.0),
    ('g9', 'cn', 'Quiz 1', 17.0, 20.0, 10.0),
    ('g10', 'dbms', 'Assignment 1', 44.0, 50.0, 15.0),
  ];
  var gi = 0;
  for (final (id, subj, title, score, max, weight) in grades) {
    await user.collection('grades').doc(id).set({
      'subjectId': subj,
      'title': title,
      'score': score,
      'maxScore': max,
      'weight': weight,
      'date': Timestamp.fromDate(_d(-30 + gi * 3)),
      'createdAt': Timestamp.fromDate(_d(-30 + gi++ * 3)),
    });
  }

  // ── Learning plan (built by the app's real on-device generator) ─────────
  final plan = const LearningPlanGenerator().generate(PlanRequest(
    subject: 'Machine Learning',
    specificTopic: false,
    level: KnowledgeLevel.basics,
    goal: LearningGoal.exam,
    dailyMinutes: 60,
    studyDays: {1, 2, 3, 4, 5, 6},
    targetDate: _d(42),
    region: StudyRegion.india,
    program: StudyProgram.undergraduate,
  ));
  await user.collection('learningPlans').doc(plan.id).set(plan.toJson());
  demoPlanId = plan.id;
  await user.set({'learningPlansCreatedCount': 1}, SetOptions(merge: true));

  // ── Opportunities & perks (generic, non-branded demo listings) ──────────
  final res = [
    ('r1', 'internship', 'Software Engineering Intern — Summer 2027', 'Northwind Labs',
        'A 10-week paid internship building backend services with mentorship from senior engineers.', 40, 95, true, true),
    ('r2', 'scholarship', 'Women in Computing Scholarship', 'Open Tech Foundation',
        'Merit-based award covering tuition for undergraduate women in CS and related fields.', 25, 90, false, null),
    ('r3', 'certification', 'Cloud Fundamentals Certification', 'Skyline Academy',
        'Free, self-paced certification covering compute, storage, networking and security basics.', 60, 85, true, false),
    ('r4', 'hackathon', 'Build for Campus — 36-hour Hackathon', 'Campus Devs Network',
        'Team up to build tools that make student life easier. Prizes, mentors and swag.', 14, 80, null, null),
    ('r5', 'discount', 'Design Suite — 60% off for students', 'Pixelcraft',
        'Pro design tools at a student price with a verified college email.', 120, 88, null, null),
    ('r6', 'discount', 'Coding Bootcamp Pass — free for 6 months', 'CodeTrail',
        'Interactive courses in Python, web and data — free for verified students.', 90, 84, null, null),
    ('r7', 'research', 'Undergraduate Research Fellowship', 'Institute of Applied AI',
        'An 8-week paid research fellowship in machine learning with a faculty mentor.', 30, 82, false, true),
  ];
  var ri = 0;
  for (final (id, type, title, org, desc, deadlineDays, pri, remote, paid) in res) {
    await db.collection('resources').doc(id).set({
      'type': type,
      'title': title,
      'organization': org,
      'company': type == 'discount' ? org : null,
      'discountText': type == 'discount' ? title.split('— ').last : null,
      'description': desc,
      'benefits': desc,
      'howToApply': 'Apply on the official website.',
      'countries': ['Global'],
      'status': 'active',
      'deadline': Timestamp.fromDate(_d(deadlineDays)),
      'startDate': Timestamp.fromDate(_d(-10)),
      'applicationUrl': 'https://example.com/$id',
      'priority': pri,
      'featured': ri == 0,
      'sponsored': false,
      'verified': true,
      'remote': remote,
      'paid': paid,
      'tags': <String>[],
      'categories': <String>[],
      'createdAt': Timestamp.fromDate(_d(-12 + ri)),
      'updatedAt': Timestamp.fromDate(_d(-6 + ri++)),
      'publishedAt': Timestamp.fromDate(_d(-12)),
    });
  }
}
