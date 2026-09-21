import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_settings_provider.dart';

/// Canonical set of Home "Quick tools" keys, in their default display order.
/// The visual registry (label/icon/colour/destination) lives in the dashboard;
/// this list is the single source of truth for *which* tools exist and their
/// default ordering. Keys are stable — never rename one (only add/remove).
const List<String> kDefaultQuickToolOrder = <String>[
  'attendance',
  'tasks',
  'exams',
  'grades',
  'notes',
  'calendar',
  'habits',
  'expenses',
  'perks',
];

/// The user's personalised Quick-tools configuration: an explicit [order] over
/// every known key plus the set of [hidden] keys. [visible] is the ordered list
/// of keys the Home grid should render.
class QuickToolsState {
  final List<String> order;
  final Set<String> hidden;
  const QuickToolsState({required this.order, required this.hidden});

  List<String> get visible =>
      order.where((k) => !hidden.contains(k)).toList(growable: false);

  QuickToolsState copyWith({List<String>? order, Set<String>? hidden}) =>
      QuickToolsState(order: order ?? this.order, hidden: hidden ?? this.hidden);
}

/// Persists the Home Quick-tools order + visibility per signed-in user.
///
/// Stored as two CSV strings (order, hidden) via [ScopedPrefs]. On load it
/// reconciles the stored order with [kDefaultQuickToolOrder] so tools added in
/// a future release automatically appear (appended), and removed/unknown keys
/// are dropped — the config never goes stale across updates.
class QuickToolsController extends StateNotifier<QuickToolsState> {
  final ScopedPrefs _prefs;
  QuickToolsController(this._prefs) : super(_load(_prefs));

  static QuickToolsState _load(ScopedPrefs prefs) {
    final storedOrder = _split(prefs.getString(AppConstants.prefsQuickToolsOrder));
    final hidden = _split(prefs.getString(AppConstants.prefsQuickToolsHidden))
        .where(kDefaultQuickToolOrder.contains)
        .toSet();

    // Keep stored order (valid keys only), then append any newly-added tools.
    final order = <String>[
      ...storedOrder.where(kDefaultQuickToolOrder.contains),
    ];
    for (final k in kDefaultQuickToolOrder) {
      if (!order.contains(k)) order.add(k);
    }
    return QuickToolsState(order: order, hidden: hidden);
  }

  static List<String> _split(String? csv) => (csv == null || csv.isEmpty)
      ? const []
      : csv.split(',').where((e) => e.isNotEmpty).toList();

  Future<void> _persist() async {
    await _prefs.setString(
        AppConstants.prefsQuickToolsOrder, state.order.join(','));
    await _prefs.setString(
        AppConstants.prefsQuickToolsHidden, state.hidden.join(','));
  }

  /// Move the tool at [oldIndex] to [newIndex] within the full ordered list.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final order = [...state.order];
    if (oldIndex < 0 || oldIndex >= order.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, order.length - 1);
    final item = order.removeAt(oldIndex);
    order.insert(newIndex, item);
    state = state.copyWith(order: order);
    await _persist();
  }

  Future<void> setHidden(String key, bool hidden) async {
    final set = {...state.hidden};
    if (hidden) {
      set.add(key);
    } else {
      set.remove(key);
    }
    state = state.copyWith(hidden: set);
    await _persist();
  }

  /// Restore the default order with everything visible.
  Future<void> reset() async {
    state = const QuickToolsState(
        order: kDefaultQuickToolOrder, hidden: <String>{});
    await _persist();
  }
}

final quickToolsProvider =
    StateNotifierProvider<QuickToolsController, QuickToolsState>((ref) {
  return QuickToolsController(ref.watch(scopedPrefsProvider));
});
