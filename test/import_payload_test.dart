// Client side of photo/PDF import: real MIME detection, the callable timeout,
// and the large-file Storage route — the pieces that made imports fail.
import 'dart:typed_data';

import 'package:classtrack/services/gemini_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _b(List<int> head, [int pad = 32]) =>
    Uint8List.fromList([...head, ...List.filled(pad, 0)]);

class _CapturingFunctions implements FirebaseFunctions {
  String? name;
  HttpsCallableOptions? options;
  Map<String, dynamic>? payload;

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) {
    this.name = name;
    this.options = options;
    return _Callable(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Callable implements HttpsCallable {
  _Callable(this.f);
  final _CapturingFunctions f;
  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    f.payload = Map<String, dynamic>.from(parameters as Map);
    return _Result<T>({
      'subjects': [
        {
          'name': 'Maths',
          'sessions': [
            {'day': 'Monday', 'start': '09:00', 'end': '10:00', 'room': null}
          ]
        }
      ],
      'confidence': 'high',
    } as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Result<T> implements HttpsCallableResult<T> {
  _Result(this.data);
  @override
  final T data;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('sniffMimeType', () {
    test('detects the formats galleries actually return', () {
      expect(sniffMimeType(_b([0xFF, 0xD8, 0xFF]), 'x'), 'image/jpeg');
      expect(sniffMimeType(_b([0x89, 0x50, 0x4E, 0x47]), 'x'), 'image/png');
      expect(sniffMimeType(_b([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]), 'x'), 'image/webp');
      expect(sniffMimeType(_b([0, 0, 0, 0x18, ...'ftypheic'.codeUnits]), 'x'), 'image/heic');
      expect(sniffMimeType(_b('%PDF-1.7'.codeUnits), 'x'), 'application/pdf');
      expect(sniffMimeType(_b([1, 2, 3]), 'fallback'), 'fallback');
      expect(sniffMimeType(Uint8List(0), 'fallback'), 'fallback');
    });
  });

  group('parseSchedule request', () {
    test('a PNG screenshot is labelled PNG (not jpeg) and sent inline', () async {
      final f = _CapturingFunctions();
      final s = GeminiService(f);
      final r = await s.parseSchedule(imageBytes: _b([0x89, 0x50, 0x4E, 0x47]));
      expect(f.payload!['sourceType'], 'image');
      expect(f.payload!['mimeType'], 'image/png');
      expect(f.payload!['inlineData'], isA<String>());
      expect(r.subjects.single.name, 'Maths');
    });

    test('uses a long timeout (the SDK default 60s cut off big PDFs)', () async {
      final f = _CapturingFunctions();
      await GeminiService(f).parseSchedule(pdfBytes: _b('%PDF-1.4'.codeUnits));
      expect(f.name, 'parseSchedule');
      expect(f.options?.timeout, greaterThanOrEqualTo(const Duration(seconds: 180)));
      expect(f.payload!['mimeType'], 'application/pdf');
      expect(f.payload!['sourceType'], 'pdf');
    });

    test('large files fall back to inline when Storage is unavailable', () async {
      final f = _CapturingFunctions();
      final big = _b('%PDF-1.4'.codeUnits, GeminiService.inlineLimitBytes + 10);
      await GeminiService(f).parseSchedule(pdfBytes: big);
      expect(f.payload!.containsKey('inlineData'), isTrue);
      expect(f.payload!.containsKey('storagePath'), isFalse);
    });
  });
}
