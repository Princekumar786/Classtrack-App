import 'package:cloud_firestore/cloud_firestore.dart';

/// Tracks how many AI assistant messages the user has sent in the current
/// calendar month. Stored at users/{uid}/usage/chat as { month, count }.
///
/// This is the client-side mirror of the server's authoritative monthly limit
/// (see functions/index.js). The server is the real guard; this copy powers the
/// UI (remaining count + paywall prompt) without an extra round-trip.
class ChatUsageRepository {
  final FirebaseFirestore db;
  final String uid;
  ChatUsageRepository({required this.db, required this.uid});

  DocumentReference<Map<String, dynamic>> get _doc =>
      db.collection('users').doc(uid).collection('usage').doc('chat');

  /// Current month key, e.g. "2026-07".
  static String currentMonth() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}';
  }

  static int _readCount(Map<String, dynamic>? data) {
    if (data == null || data['month'] != currentMonth()) return 0;
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  /// Live count for the current month (0 when a new month rolls over).
  Stream<int> watchCount() =>
      _doc.snapshots().map((s) => _readCount(s.data()));

  Future<int> currentCount() async => _readCount((await _doc.get()).data());

  /// Records one more used message, resetting on a new month.
  ///
  /// No transaction on purpose: this is only the UI mirror (the server keeps
  /// the real count), and FlutterFire transactions throw a noisy
  /// `MissingPluginException(cancel on …/firebase_firestore/transaction/…)`
  /// after each run. `FieldValue.increment` keeps same-month bumps atomic.
  Future<void> increment() async {
    final month = currentMonth();
    final data = (await _doc.get()).data();
    if (data == null || data['month'] != month) {
      await _doc.set({'month': month, 'count': 1});
    } else {
      await _doc.set({'count': FieldValue.increment(1)}, SetOptions(merge: true));
    }
  }

  /// Marks this month as fully used (the server reported the free limit even
  /// though the local mirror was behind — e.g. a re-created account). Never
  /// lowers an existing higher count.
  Future<void> markExhausted(int limit) async {
    final month = currentMonth();
    final current = _readCount((await _doc.get()).data());
    if (current >= limit) return;
    await _doc.set({'month': month, 'count': limit});
  }
}
