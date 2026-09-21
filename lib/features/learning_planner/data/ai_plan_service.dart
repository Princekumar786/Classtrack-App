import 'dart:convert';

import '../../../services/gemini_service.dart';
import '../domain/learning_plan.dart';
import '../domain/learning_plan_generator.dart';

/// Best-effort AI topic generation via the server-side Gemini (`chat` Cloud
/// Function). It asks the model for a strict JSON list of topics tailored to
/// the student's subject, region/jurisdiction, program and level — the exact
/// nuance a fixed on-device library can't cover (e.g. US vs India law, or
/// BA-LLB vs MBA framing of the same subject).
///
/// This ONLY produces the topic list ("what to learn" + estimates) — never
/// study material. The deterministic [LearningPlanGenerator] still sequences
/// everything into days/weeks and fits the deadline. Any failure returns null
/// so the caller can fall back to the offline library.
class AiPlanService {
  AiPlanService(this._gemini);

  final GeminiService _gemini;

  static int _seed = 0;
  static String _id() =>
      'ai_${DateTime.now().microsecondsSinceEpoch}_${_seed++}';

  /// Returns an ordered list of core topics, or null if the AI path is
  /// unavailable or the response couldn't be parsed.
  Future<List<LearningTopic>?> generateTopics(PlanRequest req) async {
    try {
      final reply = await _gemini
          .chat([
            {
              'role': 'user',
              'parts': [
                {'text': _buildPrompt(req)}
              ],
            }
          ])
          .timeout(const Duration(seconds: 25));
      return _parse(reply);
    } catch (_) {
      return null;
    }
  }

  String _buildPrompt(PlanRequest req) {
    final syllabus = req.hasSyllabus
        ? 'The student uploaded a syllabus with these topics — base the plan on them and keep their order where sensible:\n- ${req.syllabusTopics.join('\n- ')}\n'
        : '';
    return '''
You are an expert study planner. Build an ordered learning roadmap for a student.

Subject: "${req.subject}"
Country / jurisdiction: ${req.region.label}
Course / program: ${req.program.title}
Current level: ${req.level.title}
Goal: ${req.goal.title}
$syllabus
Rules:
- Return ONLY a JSON array, no prose, no markdown fences.
- 8 to 16 topics, ordered from foundational to advanced (respect prerequisites).
- Group topics into a few named curriculum units via a "unit" field (e.g. "Foundations", "Contract Law", "Revision").
- Tailor content to the jurisdiction (e.g. correct statutes/laws for that country) and to the program's depth and lens (an MBA gets an applied/managerial treatment; an undergraduate/professional course gets a doctrinal/detailed one).
- BE SPECIFIC AND CONCRETE. Every "objectives", "sections" and "points" entry MUST be unique to THAT topic and name the real concepts, terms, methods, formulas, cases or statutes involved. NEVER use generic filler like "work through examples", "connect the ideas", "understand the basics", "key terms", "recall the key points" or "test your understanding". If you can't name something specific, omit it.
- Each item: {"title": string, "unit": string, "estMinutes": integer 15-90, "difficulty": "easy"|"medium"|"hard", "objectives": [2-5 specific concept names], "sections": [{"title": string, "minutes": integer, "points": [2-4 specific subtopics]}], "completionCriteria": [2-4 concrete "Explain/Solve/Derive/Apply …" statements]}.
- objectives, sections and criteria describe WHAT to learn, NEVER the actual study material, notes or answers.

Example item (note how specific every line is):
{"title":"Normalization","unit":"Design","estMinutes":45,"difficulty":"hard","objectives":["Functional dependencies & closures","1NF, 2NF, 3NF","BCNF and when it differs from 3NF","Lossless-join & dependency preservation"],"sections":[{"title":"Functional dependencies","minutes":15,"points":["Definition of an FD","Armstrong's axioms","Attribute closure"]},{"title":"Normal forms","minutes":20,"points":["1NF, 2NF, 3NF conditions","Decomposing to BCNF"]},{"title":"Self-check","minutes":10,"points":["Normalize a sample relation to 3NF"]}],"completionCriteria":["Identify functional dependencies in a relation","Decompose a table into 3NF/BCNF"]}

JSON array:''';
  }

  List<LearningTopic>? _parse(String reply) {
    final jsonStr = _extractJsonArray(reply);
    if (jsonStr == null) return null;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! List || decoded.isEmpty) return null;
      final topics = <LearningTopic>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final title = (item['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final mins = _clampMinutes(item['estMinutes']);
        final objectives = (item['objectives'] is List)
            ? (item['objectives'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : <String>[];
        final unit = (item['unit'] ?? '').toString().trim();
        final sections = <TopicSection>[];
        if (item['sections'] is List) {
          for (final s in item['sections'] as List) {
            if (s is! Map) continue;
            final st = (s['title'] ?? '').toString().trim();
            if (st.isEmpty) continue;
            sections.add(TopicSection(
              title: st,
              minutes: _clampMinutes(s['minutes']),
              points: (s['points'] is List)
                  ? (s['points'] as List)
                      .map((e) => e.toString().trim())
                      .where((e) => e.isNotEmpty)
                      .toList()
                  : const [],
            ));
          }
        }
        final criteria = (item['completionCriteria'] is List)
            ? (item['completionCriteria'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : <String>[];
        topics.add(LearningTopic(
          id: _id(),
          title: title,
          estMinutes: mins,
          objectives: objectives,
          unit: unit.isEmpty ? 'Topics' : unit,
          sections: sections,
          completionCriteria: criteria,
          difficulty: _difficulty(item['difficulty']),
        ));
      }
      return topics.length >= 4 ? topics : null;
    } catch (_) {
      return null;
    }
  }

  /// Pulls the first top-level JSON array out of a reply, tolerating stray
  /// prose or ```json fences the model may add.
  static String? _extractJsonArray(String reply) {
    final start = reply.indexOf('[');
    final end = reply.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    return reply.substring(start, end + 1);
  }

  static int _clampMinutes(dynamic v) {
    final n = (v is num) ? v.toInt() : int.tryParse('$v') ?? 30;
    final snapped = (n / 5).round() * 5;
    return snapped.clamp(15, 90);
  }

  static TopicDifficulty _difficulty(dynamic v) {
    switch ('$v'.toLowerCase().trim()) {
      case 'easy':
        return TopicDifficulty.easy;
      case 'hard':
      case 'challenging':
        return TopicDifficulty.hard;
      default:
        return TopicDifficulty.medium;
    }
  }
}
