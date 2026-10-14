import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../domain/parsed_schedule.dart';

/// An imported timetable the student hasn't saved yet.
class ImportDraft {
  final ParsedSchedule schedule;
  final DateTime savedAt;
  const ImportDraft({required this.schedule, required this.savedAt});

  int get subjectCount => schedule.subjects.length;
}

/// Keeps ONE unsaved import per user on this device (per-user SharedPreferences
/// via [ScopedPrefs]), so a parsed timetable survives the app being
/// backgrounded and killed, or swiped away from recents, before the review is
/// saved. Local only on purpose: once saved, the timetable itself syncs to
/// every device through Firestore as normal.
class ImportDraftStore extends StateNotifier<ImportDraft?> {
  ImportDraftStore(this._prefs, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now,
        super(null) {
    state = _read();
  }

  static const key = 'importDraft';

  /// Drafts older than this are dropped, so a half-finished import from weeks
  /// ago doesn't pop up again.
  static const maxAge = Duration(days: 7);

  final ScopedPrefs _prefs;
  final DateTime Function() _now;

  ImportDraft? _read() {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse(map['savedAt'] as String? ?? '');
      final schedule = ParsedSchedule.fromDraftJson(
          map['schedule'] as Map<String, dynamic>);
      if (savedAt == null ||
          _now().difference(savedAt) > maxAge ||
          schedule.isEmpty) {
        _prefs.remove(key);
        return null;
      }
      return ImportDraft(schedule: schedule, savedAt: savedAt);
    } catch (_) {
      // Corrupt or from an incompatible version: drop it, never crash.
      _prefs.remove(key);
      return null;
    }
  }

  /// Saves (or overwrites) the draft. Safe to call often.
  Future<void> save(ParsedSchedule schedule) async {
    if (schedule.isEmpty) return clear();
    final draft = ImportDraft(schedule: schedule, savedAt: _now());
    state = draft;
    await _prefs.setString(
      key,
      jsonEncode({
        'savedAt': draft.savedAt.toIso8601String(),
        'schedule': schedule.toDraftJson(),
      }),
    );
  }

  Future<void> clear() async {
    state = null;
    await _prefs.remove(key);
  }

  /// [save] from places where provider state must not change synchronously
  /// (e.g. a widget's dispose, mid tree teardown): runs right after.
  void saveSoon(ParsedSchedule schedule) {
    Future.microtask(() {
      if (mounted) save(schedule);
    });
  }
}

/// The current user's unsaved import, or null. Rebuilds on account switch.
final importDraftProvider =
    StateNotifierProvider<ImportDraftStore, ImportDraft?>((ref) {
  return ImportDraftStore(ref.watch(scopedPrefsProvider));
});
