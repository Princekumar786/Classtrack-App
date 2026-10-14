/// Pure helpers behind "Build your own plan": will the student's topics fit
/// before the deadline, what would fix it, and turning a pasted syllabus into
/// topic rows. Mirrors how [LearningPlanGenerator] schedules (study dates from
/// today through the deadline, on the chosen weekdays).
library;

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

/// Study dates from [from] (today) through [target], on [weekdays]
/// (DateTime.monday..sunday).
int studyDaysBetween(DateTime from, DateTime target, Set<int> weekdays) {
  if (weekdays.isEmpty) return 0;
  var n = 0;
  var c = _d(from);
  final end = _d(target);
  while (!c.isAfter(end)) {
    if (weekdays.contains(c.weekday)) n++;
    c = c.add(const Duration(days: 1));
  }
  return n;
}

enum FitStatus { empty, fits, tight, overflow }

/// The live "will this work?" verdict shown while building.
class PlanFit {
  final int totalMinutes;
  final int studyDays;
  final int dailyMinutes;
  const PlanFit(this.totalMinutes, this.studyDays, this.dailyMinutes);

  int get capacity => studyDays * dailyMinutes;

  /// Minutes per study day actually needed to finish on time.
  int get neededPerDay =>
      studyDays == 0 ? totalMinutes : (totalMinutes / studyDays).ceil();

  /// Study days needed at the chosen daily time.
  int get daysNeeded =>
      dailyMinutes <= 0 ? 0 : (totalMinutes / dailyMinutes).ceil();

  /// Fill of the available time (can exceed 1).
  double get load =>
      capacity == 0 ? (totalMinutes > 0 ? 2 : 0) : totalMinutes / capacity;

  FitStatus get status {
    if (totalMinutes == 0) return FitStatus.empty;
    if (load <= 0.85) return FitStatus.fits;
    if (load <= 1.0) return FitStatus.tight;
    return FitStatus.overflow;
  }
}

/// Smallest option in [options] that covers [neededPerDay], or null if none.
int? suggestDailyMinutes(int neededPerDay, List<int> options) {
  for (final o in [...options]..sort()) {
    if (o >= neededPerDay) return o;
  }
  return null;
}

/// Earliest deadline (from [from]) that gives [daysNeeded] study days on
/// [weekdays]. Capped at ~2 years.
DateTime? earliestFinish(DateTime from, int daysNeeded, Set<int> weekdays) {
  if (weekdays.isEmpty || daysNeeded <= 0) return null;
  var c = _d(from);
  var n = 0;
  for (var i = 0; i < 730; i++) {
    if (weekdays.contains(c.weekday)) {
      n++;
      if (n >= daysNeeded) return c;
    }
    c = c.add(const Duration(days: 1));
  }
  return null;
}

/// One topic parsed from a pasted list, with any sub-points under it.
typedef ParsedTopic = ({String title, int? minutes, List<String> subtopics});

final _bullet = RegExp(r'^\s*(?:[-*•·▪◦>]+|\(?\d{1,3}[.)\]:]|[a-zA-Z][.)])\s+');
final _subBullet = RegExp(r'^\s*[◦▪‣–]\s+');
final _indent = RegExp(r'^(?:\t| {2,})\S');
final _duration = RegExp(
  r'[\s\-–—:,(\[]*(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour|hours|m|min|mins|minute|minutes)\s*[)\]]?\s*$',
  caseSensitive: false,
);

/// Turns a pasted syllabus / list into topics. Strips bullets and numbering,
/// drops blanks and duplicates, and reads an optional trailing duration
/// ("Arrays - 45 min", "Graphs (1.5h)"). Indented lines (or ◦ ▪ – bullets)
/// under a topic become its subtopics:
///   1. Kinematics
///      - Displacement
///      - Velocity
List<ParsedTopic> parseTopicList(String text, {int maxTopics = 60}) {
  final out = <({String title, int? minutes, List<String> subtopics})>[];
  final seen = <String>{};
  for (final raw in text.split(RegExp(r'[\r\n]+'))) {
    final isSub = out.isNotEmpty &&
        (_indent.hasMatch(raw) || _subBullet.hasMatch(raw));
    var line = raw.replaceFirst(_bullet, '').trim();
    if (line.isEmpty) continue;
    if (isSub) {
      line = line.replaceAll(RegExp(r'\s+'), ' ');
      if (line.length > 120) line = line.substring(0, 120).trim();
      final subs = out.last.subtopics;
      if (subs.length < 30 &&
          !subs.any((s) => s.toLowerCase() == line.toLowerCase())) {
        subs.add(line);
      }
      continue;
    }
    int? minutes;
    final m = _duration.firstMatch(line);
    if (m != null) {
      final v = double.parse(m.group(1)!);
      final unit = m.group(2)!.toLowerCase();
      final mins = unit.startsWith('h') ? (v * 60).round() : v.round();
      final rest = line.substring(0, m.start).trim();
      if (rest.isNotEmpty && mins > 0 && mins <= 600) {
        minutes = mins;
        line = rest;
      }
    }
    line = line.replaceAll(RegExp(r'\s+'), ' ');
    if (line.length > 120) line = line.substring(0, 120).trim();
    if (!seen.add(line.toLowerCase())) continue;
    out.add((title: line, minutes: minutes, subtopics: <String>[]));
    if (out.length >= maxTopics) break;
  }
  return out;
}
