import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../features/import/domain/parsed_schedule.dart';

/// Real MIME type from a file's first bytes (galleries return PNG, WebP and
/// HEIC as well as JPEG; labelling them all "image/jpeg" made the AI reject or
/// misread some photos). Falls back to [fallback] when unrecognised.
String sniffMimeType(Uint8List b, String fallback) {
  bool at(int i, List<int> sig) {
    if (b.length < i + sig.length) return false;
    for (var k = 0; k < sig.length; k++) {
      if (b[i + k] != sig[k]) return false;
    }
    return true;
  }

  if (at(0, [0xFF, 0xD8])) return 'image/jpeg';
  if (at(0, [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) return 'image/webp';
  if (at(0, '%PDF'.codeUnits)) return 'application/pdf';
  if (at(4, 'ftyp'.codeUnits) && b.length >= 12) {
    final brand = String.fromCharCodes(b.sublist(8, 12));
    if (['heic', 'heix', 'hevc', 'hevx'].contains(brand)) return 'image/heic';
    if (['mif1', 'msf1', 'heif'].contains(brand)) return 'image/heif';
  }
  return fallback;
}

/// Gemini access that goes through auth-gated Cloud Functions. The API key
/// lives ONLY server-side (GEMINI_API_KEY secret) and is never shipped in the
/// app, so it cannot be extracted from the binary.
class GeminiService {
  final FirebaseFunctions _functions;
  final FirebaseStorage? _storage;
  final String? Function()? _uid;

  GeminiService(this._functions, {FirebaseStorage? storage, String? Function()? uid})
      : _storage = storage,
        _uid = uid;

  /// Files above this go through Cloud Storage (a resumable upload) instead
  /// of inside the function call, which is slower and size-capped on mobile.
  static const int inlineLimitBytes = 6 * 1024 * 1024;

  /// A photo/PDF parse can legitimately take a minute or more (multi-page
  /// PDFs, dense photos). The SDK's default callable timeout is 60s, which
  /// made the app give up while the server was still working ("network
  /// hiccup"). Slightly above the function's own 180s limit.
  static const Duration parseTimeout = Duration(seconds: 190);

  /// Always "configured" — the key is managed by the backend.
  bool get isConfigured => true;

  /// One-shot structured timetable parse from text and/or an image, via the
  /// `parseSchedule` Cloud Function (which validates + sanitizes server-side).
  Future<ParsedSchedule> parseSchedule({
    String? text,
    Uint8List? imageBytes,
    Uint8List? pdfBytes,
  }) async {
    final Future<Map<String, dynamic>> Function() buildPayload;
    if (text != null && text.trim().isNotEmpty) {
      buildPayload = () async => {'sourceType': 'text', 'text': text};
    } else if (pdfBytes != null || imageBytes != null) {
      final isPdf = pdfBytes != null;
      final bytes = (pdfBytes ?? imageBytes)!;
      final mime = sniffMimeType(bytes, isPdf ? 'application/pdf' : 'image/jpeg');
      buildPayload = () async => {
            'sourceType': isPdf ? 'pdf' : 'image',
            'mimeType': mime,
            ...await _fileField(bytes, mime),
          };
    } else {
      return ParsedSchedule(subjects: const [], confidence: 'low');
    }

    final callable = _functions.httpsCallable(
      'parseSchedule',
      options: HttpsCallableOptions(timeout: parseTimeout),
    );
    final res = await callWithRetry(
      // Re-builds the payload each time: a large file's Storage copy is
      // deleted by the server after it's read, so a retry re-uploads it.
      () async => callable.call(await buildPayload()),
    );
    // Deep-convert the callable result into plain JSON maps/lists.
    final map = jsonDecode(jsonEncode(res.data)) as Map<String, dynamic>;
    return ParsedSchedule.fromJson(map);
  }

  /// Max automatic retries when the backend is overloaded.
  static const int maxBusyRetries = 2;

  /// Runs [call], retrying ONLY when the server says it's overloaded
  /// (`unavailable` / Cloud Run's 429-style `resource-exhausted` without a
  /// quota reason). Waits a random 3–8 s (then 6–16 s) so thousands of phones
  /// never retry in lock-step. Quota, invalid-input and auth errors are
  /// returned straight away. [sleep] is injectable for tests.
  static Future<T> callWithRetry<T>(
    Future<T> Function() call, {
    Future<void> Function(Duration)? sleep,
    Random? random,
  }) async {
    final wait = sleep ?? Future<void>.delayed;
    final rnd = random ?? Random();
    for (var attempt = 0;; attempt++) {
      try {
        return await call();
      } on FirebaseFunctionsException catch (e) {
        if (attempt >= maxBusyRetries || !isRetryableBusyError(e)) rethrow;
        final baseMs = 3000 * (1 << attempt); // 3 s, 6 s
        await wait(Duration(milliseconds: baseMs + rnd.nextInt(baseMs * 5 ~/ 3)));
      }
    }
  }

  /// Whether a callable error means "server overloaded, try again soon".
  static bool isRetryableBusyError(FirebaseFunctionsException e) {
    final d = e.details;
    final reason = d is Map ? d['reason']?.toString() : null;
    if (e.code == 'unavailable') return true;
    // Cloud Run "no instance available" arrives as resource-exhausted with NO
    // reason; our own quota errors always carry one (free_limit, rate_limit).
    return e.code == 'resource-exhausted' && reason == null;
  }

  /// `inlineData` for normal files; for large ones, uploads to the user's own
  /// Storage folder and returns `storagePath` (the function reads it, then
  /// deletes it). Falls back to inline if Storage isn't available.
  Future<Map<String, dynamic>> _fileField(Uint8List bytes, String mime) async {
    final uid = _uid?.call();
    if (bytes.length > inlineLimitBytes && _storage != null && uid != null) {
      final ext = switch (mime) {
        'application/pdf' => 'pdf',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/heic' || 'image/heif' => 'heic',
        _ => 'jpg',
      };
      final path = 'users/$uid/imports/${const Uuid().v4()}.$ext';
      await _storage.ref(path).putData(bytes, SettableMetadata(contentType: mime));
      return {'storagePath': path};
    }
    return {'inlineData': base64Encode(bytes)};
  }

  /// Multi-turn chat via the `chat` Cloud Function. [history] is a serializable
  /// list of {role, parts:[{text}|{inlineData:{data,mimeType}}]}. [context] is
  /// an optional plain-text summary of the user's app data.
  Future<String> chat(List<Map<String, dynamic>> history,
      {String? context}) async {
    final callable = _functions.httpsCallable('chat');
    final res = await callable.call({
      'history': history,
      if (context != null && context.isNotEmpty) 'context': context,
    });
    final data = res.data;
    if (data is Map && data['text'] is String) return data['text'] as String;
    return "Sorry, I couldn't come up with a reply.";
  }

  // --- Reply parsing helpers (client-side, no network) -----------------------

  static ParsedSchedule _parseScheduleJson(String raw) {
    final cleaned =
        raw.trim().replaceAll(RegExp(r'```(json|schedule)?'), '').trim();
    try {
      final map = jsonDecode(cleaned) as Map<String, dynamic>;
      return ParsedSchedule.fromJson(map);
    } catch (_) {
      return ParsedSchedule(subjects: const [], confidence: 'low');
    }
  }

  static ParsedSchedule? extractScheduleFromReply(String reply) {
    final match = RegExp(r'```schedule\s*([\s\S]*?)```', multiLine: true)
        .firstMatch(reply);
    if (match == null) return null;
    final json = match.group(1)?.trim() ?? '';
    if (json.isEmpty) return null;
    final parsed = _parseScheduleJson(json);
    return parsed.isEmpty ? null : parsed;
  }

  static String stripScheduleBlock(String reply) => reply
      .replaceAll(RegExp(r'```schedule[\s\S]*?```', multiLine: true), '')
      .trim();

  // --- Action ("invisible function calling") parsing --------------------------

  /// Pulls the list of structured actions out of an `actions` fenced block, if
  /// present. Returns an empty list when there's nothing to run.
  static List<Map<String, dynamic>> extractActionsFromReply(String reply) {
    final match = RegExp(r'```actions\s*([\s\S]*?)```', multiLine: true)
        .firstMatch(reply);
    if (match == null) return const [];
    final json = match.group(1)?.trim() ?? '';
    if (json.isEmpty) return const [];
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final list = map['actions'];
      if (list is! List) return const [];
      return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Removes the `actions` block so it never shows in the chat bubble.
  static String stripActionsBlock(String reply) => reply
      .replaceAll(RegExp(r'```actions[\s\S]*?```', multiLine: true), '')
      .trim();

  /// Removes ANY remaining fenced code block (```lang … ```), so raw JSON or
  /// script the model sometimes echoes alongside its actions — e.g. a
  /// ```json duplicate of the delete list — never shows in the plain-text chat
  /// bubble. (The functional `actions`/`schedule` blocks are extracted from the
  /// original reply beforehand, so removing them here only affects display.)
  static String stripAllCodeFences(String reply) => reply
      .replaceAll(RegExp(r'```[\s\S]*?```', multiLine: true), '')
      // A trailing, unclosed fence (truncated response) — drop from the fence
      // marker to the end so a half-printed code block can't leak through.
      .replaceAll(RegExp(r'```[a-zA-Z]*[\s\S]*$'), '')
      .trim();

  /// Removes a bare (unfenced) actions/schedule JSON object the model sometimes
  /// writes straight into the prose, e.g. `{ "actions": [ … ] }`.
  static String stripBareActionsJson(String reply) => reply
      .replaceAll(
          RegExp(r'\{\s*"(actions|subjects|schedule)"\s*:[\s\S]*\}',
              multiLine: true),
          '')
      .trim();
}
