import '../../opportunities/domain/resource_status.dart';
import 'audit_log.dart';

// Pure, unit-testable formatters turning raw audit entries into human-readable
// text for the CMS viewer (e.g. `resource_update` + statusTo:active →
// "Published \"Title\"  ·  Draft → Active  ·  by prince@…").

/// The friendly headline for an audit entry.
String auditHeadline(AuditLogEntry e) {
  final action = e.action;
  final title = (e.details['title'] as String?)?.trim();
  final target = (title != null && title.isNotEmpty)
      ? '"$title"'
      : (e.targetId.isNotEmpty
            ? '${e.targetType} ${e.targetId}'
            : e.targetType);

  if (action == 'set_user_role') {
    final to = e.details['to']?.toString();
    return (to == null || to == 'none')
        ? 'Revoked CMS role'
        : 'Set role to ${_prettyRole(to)}';
  }
  if (action == 'notification_sent') {
    final t = e.details['title']?.toString();
    return (t != null && t.isNotEmpty)
        ? 'Sent notification "$t"'
        : 'Sent a notification';
  }

  // Publishing a previously-draft resource reads better as "Published".
  final from = e.details['statusFrom']?.toString();
  final to = e.details['statusTo']?.toString();
  if (action.endsWith('_update') &&
      (from == 'draft' || from == 'hidden' || from == null) &&
      to != null &&
      _isVisible(to)) {
    return 'Published $target';
  }

  String verb;
  if (action.endsWith('_create')) {
    verb = 'Created';
  } else if (action.endsWith('_update')) {
    verb = 'Updated';
  } else if (action.endsWith('_delete')) {
    verb = 'Deleted';
  } else {
    verb = action.replaceAll('_', ' ');
  }
  return '$verb $target';
}

/// A status transition like "Draft → Active", or null when there was none.
String? auditStatusTransition(AuditLogEntry e) {
  final from = e.details['statusFrom']?.toString();
  final to = e.details['statusTo']?.toString();
  if (from == null && to == null) return null;
  if (from == to) return null;
  return '${_statusLabel(from)} → ${_statusLabel(to)}';
}

/// Who performed the action — email when known, else role (or "System").
String auditActor(AuditLogEntry e) {
  if (e.actorEmail != null && e.actorEmail!.isNotEmpty) return e.actorEmail!;
  if (e.actorUid == 'system') return 'System';
  if (e.actorUid == 'unknown') return _prettyRole(e.actorRole);
  final shortUid = e.actorUid.length > 6
      ? e.actorUid.substring(0, 6)
      : e.actorUid;
  return '${_prettyRole(e.actorRole)} · $shortUid';
}

String _statusLabel(String? key) =>
    key == null ? '—' : ResourceStatus.fromKey(key).label;

bool _isVisible(String key) => ResourceStatus.fromKey(key).isVisibleToStudents;

String _prettyRole(String key) => key
    .split('_')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');
