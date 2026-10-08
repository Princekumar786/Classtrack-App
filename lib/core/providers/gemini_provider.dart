import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/gemini_service.dart';
import 'firebase_providers.dart';

/// Gemini service that talks to the app's auth-gated Cloud Functions. The API
/// key never leaves the server, so there is nothing to extract from the app.
final geminiServiceProvider = Provider<GeminiService>((ref) {
  return GeminiService(
    ref.watch(firebaseFunctionsProvider),
    // Large photos/PDFs upload through the user's own Storage folder.
    storage: ref.watch(firebaseStorageProvider),
    uid: () => ref.read(currentUidProvider),
  );
});
