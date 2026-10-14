import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../services/error_reporter.dart';

/// Defensive Firestore document parsing.
///
/// A single malformed document (e.g. a mistyped field entered in the CMS, or a
/// half-written record) must never blank an entire screen. These helpers parse
/// each document in isolation: a bad one is skipped and reported to Crashlytics
/// as a NON-FATAL (so we still learn about the data-quality issue) while the
/// rest of the list renders normally.
///
/// Use [mapDocsSafely] at every `snapshot.docs.map(Model.fromMap)` call site.
List<T> mapDocsSafely<T>(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  T Function(QueryDocumentSnapshot<Map<String, dynamic>> doc) parse, {
  String? context,
}) {
  final out = <T>[];
  for (final doc in docs) {
    try {
      out.add(parse(doc));
    } catch (e, st) {
      _reportBadDoc(e, st, context: context, path: doc.reference.path);
    }
  }
  return out;
}

/// Like [mapDocsSafely] but for the common `Model.fromMap(id, data)` shape,
/// so callers don't have to unpack the snapshot themselves.
List<T> parseDocsSafely<T>(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  T Function(String id, Map<String, dynamic> data) fromMap, {
  String? context,
}) {
  return mapDocsSafely(
    docs,
    (doc) => fromMap(doc.id, doc.data()),
    context: context,
  );
}

void _reportBadDoc(
  Object error,
  StackTrace stack, {
  String? context,
  String? path,
}) {
  if (kDebugMode) {
    debugPrint('Skipped malformed document'
        '${path != null ? ' at $path' : ''}'
        '${context != null ? ' ($context)' : ''}: $error');
  }
  // Best-effort, non-blocking, never fatal: both Crashlytics and PostHog.
  ErrorReporter.report(
    error,
    stack,
    reason: 'bad_doc:${context ?? 'unknown'}',
    extra: {if (path != null) 'doc_path': path},
  );
}
