/// Pure, unit-tested helpers behind the AI assistant's actions. No Flutter or
/// Firestore here so the rules can be verified exactly.
library;

/// A class whose afternoon time was entered as a morning time — e.g. the
/// student typed "1:40–2:30" meaning PM, stored as 01:40–02:30 — gets moved to
/// the afternoon. Returns the corrected (start, end) in 24h "HH:MM", or null
/// when the class doesn't need fixing.
///
/// Only starts between 01:00 and 06:59 move: no college class realistically
/// starts then, while 07:00+ morning classes and anything already in the
/// afternoon/evening are left exactly as they are. The end moves with the
/// start when it's still in the morning, so a 01:40–02:30 class becomes
/// 13:40–14:30 (and an 11:30–01:00 class that crossed noon becomes 11:30–13:00
/// via the end-only rule below).
(String, String)? fixAmEnteredClassTime(String start, String end) {
  final s = _minutes(start);
  final e = _minutes(end);
  if (s == null || e == null) return null;
  const h = 60;
  if (s >= 1 * h && s < 7 * h) {
    final ns = s + 12 * h;
    var ne = e < 12 * h ? e + 12 * h : e;
    if (ne <= ns) ne = ns + h; // keep a sane duration
    if (ne >= 24 * h) ne = 23 * h + 59;
    return (_fmt(ns), _fmt(ne));
  }
  // Start is fine but the end was entered without PM (ends before it starts,
  // e.g. 11:30–01:00): move only the end.
  if (e <= s && e + 12 * h > s && e + 12 * h < 24 * h) {
    return (start, _fmt(e + 12 * h));
  }
  return null;
}

int? _minutes(String hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm.trim());
  if (m == null) return null;
  final hh = int.parse(m.group(1)!), mm = int.parse(m.group(2)!);
  if (hh > 23 || mm > 59) return null;
  return hh * 60 + mm;
}

String _fmt(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// An expense parsed straight from what the student typed.
class ParsedExpense {
  const ParsedExpense(this.amount, this.title, this.category);
  final double amount;
  final String title;

  /// One of the app's expense categories (food, transport, books, rent, fun,
  /// health, other).
  final String category;
}

/// Safety net for "I spent 120 on aws" / "paid ₹49 for Spotify" / "spent rs 20
/// on samosa": recognises a clear spend statement so it's logged even when
/// the model replies without an action. Returns null for anything ambiguous
/// (questions, plans, budgets, refunds, multiple amounts) — those stay with
/// the model.
ParsedExpense? parseSpendStatement(String message) {
  final text = message.trim();
  if (text.isEmpty || text.length > 160) return null;
  final lower = text.toLowerCase();
  // Not a log: questions, hypotheticals, budgets, income, refunds, deletes.
  if (lower.contains('?') ||
      RegExp(r'\b(how|what|should|can i|could|would|budget|earn|earned|got paid|salary|refund|delete|remove|undo|change|edit|update|last (week|month)|yesterday.*total)\b')
          .hasMatch(lower)) {
    return null;
  }
  final verb = RegExp(r'\b(spent|spend|paid|pay|bought|buy|purchased|shelled out)\b');
  if (!verb.hasMatch(lower)) return null;

  // Exactly one amount: digits with optional decimals, currency before/after.
  final amountRe = RegExp(
      r'(?:₹|rs\.?|inr|\$|usd|€|£)?\s*(\d{1,7}(?:[.,]\d{1,2})?)\s*(?:₹|rs\.?|rupees?|inr|\$|dollars?|usd|bucks|€|£|k\b)?',
      caseSensitive: false);
  final amounts = amountRe
      .allMatches(text)
      .where((m) => m.group(1) != null)
      .toList();
  if (amounts.length != 1) return null;
  final amount = double.tryParse(amounts.first.group(1)!.replaceAll(',', '.'));
  if (amount == null || amount <= 0) return null;

  // What it was for: the words after "on"/"for"; otherwise whatever's left
  // once the verb and amount are removed ("bought samosa 20").
  final amountText = amounts.first.group(0)!.trim();
  final onFor = RegExp(r'\b(?:on|for)\s+(?:a |an |the |my |some )?(.+)$',
          caseSensitive: false)
      .firstMatch(text);
  String clean(String s) => s
      .replaceFirst(amountText, ' ')
      .replaceAll(RegExp(r'^\s*(i|i have|i\x27ve)\s+', caseSensitive: false), '')
      .replaceAll(
          RegExp(r'\b(today|yesterday|just now|this morning|tonight|rs\.?|rupees?|inr|bucks|a|an|the|some|for|on)\b',
              caseSensitive: false),
          ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s,.-]+|[\s.!,]+$'), '')
      .trim();
  // "on X"/"for X" names the item — unless X is just the amount ("bought a
  // notebook for 60"), in which case the item is what was bought.
  var item = onFor == null ? '' : clean(onFor.group(1)!);
  if (item.isEmpty) item = clean(text.replaceFirst(verb, ''));
  if (item.isEmpty || item.length > 60) return null;
  final title = item[0].toUpperCase() + item.substring(1);
  return ParsedExpense(amount, title, categorizeExpense(item));
}

/// Maps a free-text item to an app expense category. Anything unrecognised —
/// cloud services, software, subscriptions, gadgets, fees — is "other".
String categorizeExpense(String item) {
  final s = item.toLowerCase();
  bool any(List<String> words) =>
      words.any((w) => RegExp('\\b${RegExp.escape(w)}').hasMatch(s));
  if (any(['food', 'lunch', 'dinner', 'breakfast', 'snack', 'samosa', 'chai', 'tea', 'coffee', 'pizza', 'burger', 'maggi', 'canteen', 'mess', 'restaurant', 'zomato', 'swiggy', 'groceries', 'grocery', 'fruit', 'juice', 'biryani', 'dosa', 'momo'])) {
    return 'food';
  }
  if (any(['uber', 'ola', 'rapido', 'auto', 'cab', 'taxi', 'bus', 'metro', 'train', 'petrol', 'fuel', 'diesel', 'parking', 'ticket', 'flight', 'travel', 'rickshaw'])) {
    return 'transport';
  }
  if (any(['book', 'notebook', 'stationery', 'pen', 'printout', 'print', 'xerox', 'photocopy', 'textbook', 'course', 'exam fee'])) {
    return 'books';
  }
  if (any(['rent', 'hostel', 'pg', 'room', 'electricity', 'wifi', 'internet bill', 'water bill'])) {
    return 'rent';
  }
  if (any(['movie', 'netflix', 'game', 'party', 'concert', 'outing', 'shopping', 'clothes', 'trip'])) {
    return 'fun';
  }
  if (any(['medicine', 'doctor', 'pharmacy', 'gym', 'hospital', 'clinic', 'health'])) {
    return 'health';
  }
  return 'other';
}


// ── Matching what the student refers to ─────────────────────────────────────

/// Words that describe the KIND of item or the request, not which item —
/// "mark complete the microsoft fabric video" names the task "Microsoft Fabric
/// …"; "video", "mark", "complete" must not stop the match.
const _fillerWords = {
  'the', 'a', 'an', 'my', 'me', 'to', 'of', 'for', 'on', 'in', 'at', 'and', 'is',
  'please', 'mark', 'as', 'done', 'complete', 'completed', 'finish', 'finished',
  'delete', 'remove', 'update', 'change', 'rename', 'set', 'it', 'that', 'this',
  'task', 'tasks', 'video', 'videos', 'event', 'events', 'item', 'items',
  'expense', 'expenses', 'spend', 'spent', 'spending', 'transaction', 'payment',
  'exam', 'exams', 'note', 'notes', 'habit', 'habits', 'grade', 'grades',
  'subject', 'subjects', 'class', 'classes', 'one', 'entry',
};

List<String> _tokens(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .toList();

/// Index of the item in [names] that [query] refers to, or null if none — or
/// if two items fit equally well (better to ask than to change the wrong one).
///
/// Order: exact title → one contains the other → keyword overlap, ignoring
/// filler words, with at least half the query's keywords present.
int? bestMatchIndex(List<String> names, String? query) {
  if (query == null || query.trim().isEmpty || names.isEmpty) return null;
  final q = query.toLowerCase().trim();
  for (var i = 0; i < names.length; i++) {
    if (names[i].toLowerCase().trim() == q) return i;
  }
  final contains = <int>[];
  for (var i = 0; i < names.length; i++) {
    final n = names[i].toLowerCase().trim();
    if (n.isNotEmpty && (n.contains(q) || q.contains(n))) contains.add(i);
  }
  if (contains.length == 1) return contains.single;

  final qWords = _tokens(q).where((t) => !_fillerWords.contains(t)).toSet();
  if (qWords.isEmpty) return null;
  var best = -1;
  var bestScore = 0.0;
  var tie = false;
  for (var i = 0; i < names.length; i++) {
    final nWords = _tokens(names[i]).toSet();
    final hit = qWords.where((w) => nWords.any((n) => n == w || (w.length >= 4 && n.startsWith(w)))).length;
    if (hit == 0) continue;
    final score = hit / qWords.length;
    if (score > bestScore) {
      bestScore = score;
      best = i;
      tie = false;
    } else if (score == bestScore) {
      tie = true;
    }
  }
  // Several items fit equally (e.g. "Maths quiz 1" and "Maths quiz 2" for
  // "maths quiz"): don't guess — the assistant asks which one.
  if (best < 0 || bestScore < 0.5 || tie) return null;
  return best;
}

/// Reads a yes/no the model may send as a bool, string or number.
bool? toBoolOrNull(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (['true', 'yes', 'done', 'complete', 'completed', '1'].contains(s)) return true;
    if (['false', 'no', 'pending', 'incomplete', 'not done', '0'].contains(s)) return false;
  }
  return null;
}

/// Normalises an `update` action from the model so field-name variants still
/// apply: "completed"/"complete"/"isDone"/"status": "done" → "done".
Map<String, dynamic> normalizeUpdateAction(Map<String, dynamic> a) {
  final out = Map<String, dynamic>.from(a);
  if (!out.containsKey('done') || out['done'] == null) {
    for (final k in ['completed', 'complete', 'isDone', 'is_done', 'finished']) {
      if (out[k] != null) {
        out['done'] = out[k];
        break;
      }
    }
    final status = out['status']?.toString().toLowerCase();
    if (out['done'] == null && status != null) {
      if (['done', 'complete', 'completed', 'finished'].contains(status)) out['done'] = true;
      if (['pending', 'todo', 'open', 'incomplete'].contains(status)) out['done'] = false;
    }
  }
  if (out['done'] != null) out['done'] = toBoolOrNull(out['done']);
  return out;
}

/// Keys of an `update` action that actually request a change. An update with
/// none of these (only "match") changes nothing and must not be reported as
/// done.
const updateChangeKeys = {
  'newTitle', 'newName', 'note', 'body', 'dueDate', 'date', 'time', 'priority',
  'taskType', 'done', 'newAmount', 'newCategory', 'score', 'maxScore', 'weight',
  'room', 'color', 'icon', 'startDate', 'endDate', 'start', 'end', 'newDay',
};

bool updateRequestsChange(Map<String, dynamic> a) =>
    updateChangeKeys.any((k) => a[k] != null && a[k].toString().trim().isNotEmpty);

/// True when the assistant's visible reply claims it already changed the
/// student's data ("Done — deleted…", "I've marked … as complete"). Used to
/// catch replies that say so without any action actually being sent.
bool claimsDataChange(String reply) {
  final s = reply.toLowerCase();
  if (s.trim().isEmpty) return false;
  const verbs = r'(deleted|removed|marked|updated|added|logged|changed|moved|renamed|created|completed|cleared|scheduled|set (?:it|your|the)|saved|recorded)';
  return RegExp(r'^\s*(done|all set|got it|okay|ok|sure|great)\b[^.?!]{0,80}\b' + verbs).hasMatch(s) ||
      RegExp(r"\b(i've|i have|i just|i)\s+(?:also\s+|now\s+|successfully\s+)?" + verbs).hasMatch(s) ||
      RegExp(r'\b(has|have) been\s+' + verbs).hasMatch(s) ||
      RegExp(r'\bis now (marked|complete|completed|done|deleted|updated)').hasMatch(s);
}

/// Reads a short typed answer to the delete-confirmation card.
/// Returns true for "yes"-type answers, false for "no"-type answers, and null
/// for anything else (a new question/request, which then goes to the AI).
/// Only short replies count, so "yes and also add a Maths exam" is not
/// treated as a plain confirmation.
bool? parseConfirmationReply(String text) {
  final s = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.isEmpty || s.split(' ').length > 5) return null;
  const no = r'^(no|nope|nah|cancel|stop|dont|don t|do not|wait|keep it|never mind|nevermind)\b';
  const yes = r'^(yes|yeah|yep|yup|ya|y|ok|okay|sure|confirm|confirmed|do it|go ahead|delete it|delete|remove it|please do|haan|ha|han)\b';
  if (RegExp(no).hasMatch(s)) return false;
  if (RegExp(yes).hasMatch(s)) return true;
  return null;
}

/// Fields the action handlers read as numbers, yes/no flags or lists.
const _numericActionKeys = {
  'amount', 'newAmount', 'score', 'maxScore', 'weight', 'minutes', 'dailyMinutes',
};
const _boolActionKeys = {'done', 'all', 'specificTopic'};

/// Makes a model-emitted action safe for the handlers, which read most fields
/// as text: numbers/bools sent where text is expected become text ("match": 2027
/// → "2027"), "true"/"false" strings in flag fields become bools, and numeric
/// strings in amount fields stay as-is (handlers parse those leniently).
/// Previously a stray number threw inside the handler and the reply still said
/// "Done".
Map<String, dynamic> coerceActionFields(Map<String, dynamic> a) {
  final out = <String, dynamic>{};
  a.forEach((k, v) {
    if (v == null || v is List || v is Map) {
      out[k] = v;
    } else if (_boolActionKeys.contains(k)) {
      out[k] = toBoolOrNull(v);
    } else if (_numericActionKeys.contains(k)) {
      out[k] = v;
    } else {
      out[k] = v is String ? v : v.toString();
    }
  });
  return out;
}
