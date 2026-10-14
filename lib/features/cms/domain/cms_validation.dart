import '../../opportunities/domain/resource.dart';
import '../../opportunities/domain/resource_status.dart';
import 'cms_metrics.dart' show isValidHttpUrl;

/// A single validation finding, tied to an editor field key where possible.
class CmsIssue {
  /// Field key (e.g. 'title', 'applicationUrl') or a logical group.
  final String field;
  final String message;
  const CmsIssue(this.field, this.message);
}

/// Content-quality report for a [Resource]: publish-blocking [errors],
/// advisory [warnings] and a 0–100 [score].
///
/// Pure and Flutter-free so it can be unit-tested and reused by the editor,
/// the resource list and (later) bulk-publish. Mirrors — and supersets — the
/// server rule `publishableIfVisible`; the Firestore rule remains the
/// authoritative gate, this only drives friendly UX.
class CmsQualityReport {
  final List<CmsIssue> errors;
  final List<CmsIssue> warnings;
  final int score;

  const CmsQualityReport({
    required this.errors,
    required this.warnings,
    required this.score,
  });

  /// Publishing is allowed only when there are no blocking errors.
  bool get canPublish => errors.isEmpty;
}

/// Evaluates [r] for publish-readiness and overall content quality.
///
/// ERRORS block publishing (never draft saving):
///  • title, organization, description present;
///  • an application or affiliate/redemption link present;
///  • for opportunities (non-discounts): benefits and how-to-apply present;
///  • date relationships consistent (deadline not before start).
///
/// WARNINGS are advisory (do not block): short description, missing deadline,
/// missing eligibility, missing logo/image, no country targeting (shows
/// globally), and syntactically invalid URLs.
CmsQualityReport evaluateResource(Resource r) {
  final errors = <CmsIssue>[];
  final warnings = <CmsIssue>[];

  // ── Errors (publish-critical) ──────────────────────────────────────────
  if (r.title.trim().isEmpty) {
    errors.add(const CmsIssue('title', 'Title is required.'));
  }
  if (r.organization.trim().isEmpty) {
    errors.add(
      const CmsIssue(
        'organization',
        'Organization / company is required to publish.',
      ),
    );
  }
  if (r.description.trim().isEmpty) {
    errors.add(const CmsIssue('description', 'A description is required.'));
  }

  final hasApp = (r.applicationUrl?.trim().isNotEmpty ?? false);
  final hasAff = (r.affiliateUrl?.trim().isNotEmpty ?? false);
  if (!hasApp && !hasAff) {
    errors.add(
      const CmsIssue(
        'applicationUrl',
        'An application or affiliate/redemption link is required to publish.',
      ),
    );
  }

  // Opportunities (everything except discounts) must spell out what the
  // student gets and how to apply before they can go live.
  if (!r.type.isDiscount) {
    if (r.benefits?.trim().isEmpty ?? true) {
      errors.add(
        const CmsIssue(
          'benefits',
          'Benefits are required to publish an opportunity.',
        ),
      );
    }
    if (r.howToApply?.trim().isEmpty ?? true) {
      errors.add(
        const CmsIssue(
          'howToApply',
          'How to apply is required to publish an opportunity.',
        ),
      );
    }
  }

  if (r.startDate != null &&
      r.deadline != null &&
      r.deadline!.isBefore(r.startDate!)) {
    errors.add(
      const CmsIssue('deadline', 'Deadline cannot be before the start date.'),
    );
  }

  if (r.scheduledPublishAt != null &&
      r.scheduledUnpublishAt != null &&
      !r.scheduledUnpublishAt!.isAfter(r.scheduledPublishAt!)) {
    errors.add(
      const CmsIssue(
        'scheduledUnpublishAt',
        'Scheduled unpublish time must be after the publish time.',
      ),
    );
  }

  // ── Warnings (advisory) ────────────────────────────────────────────────
  if (r.description.trim().isNotEmpty && r.description.trim().length < 60) {
    warnings.add(
      const CmsIssue('description', 'Description is short — add more detail.'),
    );
  }
  if (r.deadline == null && !r.type.isDiscount) {
    warnings.add(const CmsIssue('deadline', 'No deadline set.'));
  }
  if ((r.eligibility?.trim().isEmpty ?? true)) {
    warnings.add(const CmsIssue('eligibility', 'No eligibility information.'));
  }
  if ((r.logoUrl?.trim().isEmpty ?? true) &&
      (r.imageUrl?.trim().isEmpty ?? true)) {
    warnings.add(const CmsIssue('logoUrl', 'No logo or image.'));
  }
  if (r.countries.isEmpty) {
    warnings.add(
      const CmsIssue(
        'countries',
        'No country targeting — this shows globally.',
      ),
    );
  }

  // Syntactically invalid URLs (only when a value is present).
  for (final entry in <String, String?>{
    'applicationUrl': r.applicationUrl,
    'affiliateUrl': r.affiliateUrl,
    'imageUrl': r.imageUrl,
    'logoUrl': r.logoUrl,
  }.entries) {
    final v = entry.value?.trim() ?? '';
    if (v.isNotEmpty && !isValidHttpUrl(v)) {
      warnings.add(CmsIssue(entry.key, 'URL may be invalid: ${entry.key}.'));
    }
  }

  // ── Score: 100 − 20/error − 6/warning, clamped to 0..100 ───────────────
  final raw = 100 - errors.length * 20 - warnings.length * 6;
  final score = raw < 0 ? 0 : (raw > 100 ? 100 : raw);

  return CmsQualityReport(errors: errors, warnings: warnings, score: score);
}

/// Convenience: is this resource publishable to a student-visible [status]?
/// Drafts/hidden are always allowed; visible statuses require no errors.
bool canPublishAt(Resource r, ResourceStatus status) {
  if (!status.isVisibleToStudents) return true;
  return evaluateResource(r).canPublish;
}
