import 'package:cloud_functions/cloud_functions.dart';

import '../../subscription/domain/pro_constants.dart';

/// How a failed AI call should be presented. The backend tags its errors with
/// a `details.reason` (see `enforceFreeAllowance` in functions/index.js) so the
/// app can tell "free allowance used → upgrade" apart from Pro's safety caps,
/// which also arrive as `resource-exhausted`.
enum ChatErrorKind { freeLimit, proDailyCap, emailUnverified, other }

/// Shown whenever a free user has used this month's AI messages.
const String freeChatLimitMessage =
    "You've used all ${ProConstants.freeMonthlyChatLimit} free AI messages "
    'this month. Upgrade to ClassTrack Pro for unlimited chats. 💜';

/// The `details.reason` the backend attached to an error, if any.
String? aiErrorReason(Object error) {
  if (error is! FirebaseFunctionsException) return null;
  final d = error.details;
  return d is Map ? d['reason']?.toString() : null;
}

ChatErrorKind classifyChatError(Object error, {required bool isPro}) {
  final reason = aiErrorReason(error);
  if (reason == 'email_unverified') return ChatErrorKind.emailUnverified;
  if (reason == 'free_limit') return ChatErrorKind.freeLimit;

  final code = error is FirebaseFunctionsException
      ? error.code
      : error.toString().toLowerCase();
  if (code.contains('resource-exhausted')) {
    // Older backends send no reason: a free user hitting a limit is the
    // monthly allowance; a Pro user is hitting the daily safety cap.
    return isPro ? ChatErrorKind.proDailyCap : ChatErrorKind.freeLimit;
  }
  return ChatErrorKind.other;
}
