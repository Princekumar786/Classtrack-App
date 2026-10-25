import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_settings_provider.dart';

/// Per-user "seen" state for the Home notification bell.
///
/// [seenAt] is when the bell was last opened — anything published after it is
/// "new". [listSince] is fixed: when this account started getting
/// notifications on this device. Only opportunities/perks published after it
/// are listed, so items that were already live are never announced.
/// [seenAnnouncementIds] are the CMS announcement (banner) ids the user has
/// already dismissed. All persist per signed-in user via [ScopedPrefs]
/// (device-local).
class NotificationsSeenState {
  final DateTime seenAt;
  final Set<String> seenAnnouncementIds;
  final DateTime listSince;
  const NotificationsSeenState(this.seenAt, this.seenAnnouncementIds, this.listSince);
}

class NotificationsSeenController
    extends StateNotifier<NotificationsSeenState> {
  final ScopedPrefs _prefs;
  NotificationsSeenController(this._prefs) : super(_load(_prefs));

  /// Reads a stored timestamp, or stores "now" as the baseline on first read.
  static DateTime _baseline(ScopedPrefs prefs, String key) {
    final millis = prefs.getInt(key);
    if (millis != null) return DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    prefs.setInt(key, now.millisecondsSinceEpoch);
    return now;
  }

  static NotificationsSeenState _load(ScopedPrefs prefs) {
    // Baselines at first read so the bell never floods with items that were
    // published before this account started using the app (or before this
    // update, for existing users).
    final seenAt = _baseline(prefs, AppConstants.prefsNotifSeenAt);
    final listSince = _baseline(prefs, AppConstants.prefsNotifListSince);
    final ids = (prefs.getString(AppConstants.prefsAnnouncementsSeen) ?? '')
        .split(',')
        .where((e) => e.isNotEmpty)
        .toSet();
    return NotificationsSeenState(seenAt, ids, listSince);
  }

  /// Marks everything currently shown as seen: advances [seenAt] to now and
  /// records the given announcement ids. Called when the bell sheet closes.
  /// [listSince] never moves, so seen items stay listed (just not "New").
  Future<void> markSeen(Iterable<String> announcementIds) async {
    final now = DateTime.now();
    final ids = {...state.seenAnnouncementIds, ...announcementIds};
    state = NotificationsSeenState(now, ids, state.listSince);
    await _prefs.setInt(
        AppConstants.prefsNotifSeenAt, now.millisecondsSinceEpoch);
    await _prefs.setString(
        AppConstants.prefsAnnouncementsSeen, ids.join(','));
  }
}

final notificationsSeenProvider =
    StateNotifierProvider<NotificationsSeenController, NotificationsSeenState>(
        (ref) {
  return NotificationsSeenController(ref.watch(scopedPrefsProvider));
});
