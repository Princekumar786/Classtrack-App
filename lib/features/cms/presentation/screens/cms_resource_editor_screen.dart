import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/providers/firebase_providers.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../../opportunities/domain/resource.dart';
import '../../../opportunities/domain/resource_status.dart';
import '../../../opportunities/domain/resource_type.dart';
import '../../domain/cms_category.dart';
import '../../domain/cms_metrics.dart';
import '../../domain/cms_validation.dart';
import '../providers/cms_category_providers.dart';
import '../providers/cms_resource_providers.dart';
import 'cms_media_screen.dart';
import 'cms_resource_preview_screen.dart';

/// Create / edit a [Resource]. Reuses the shared model + [ResourceType]/
/// [ResourceStatus]; writes go through [CmsResourceRepository] (which stamps
/// `updatedBy` and enforces publish validation, mirrored by Firestore rules).
class CmsResourceEditorScreen extends ConsumerStatefulWidget {
  final Resource? existing;
  const CmsResourceEditorScreen({super.key, this.existing});

  @override
  ConsumerState<CmsResourceEditorScreen> createState() =>
      _CmsResourceEditorScreenState();
}

class _CmsResourceEditorScreenState
    extends ConsumerState<CmsResourceEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late final Map<String, TextEditingController> _c;
  ResourceType _type = ResourceType.scholarship;
  ResourceStatus _status = ResourceStatus.draft;
  DateTime? _startDate;
  DateTime? _deadline;
  bool _featured = false;
  bool _sponsored = false;
  bool _verified = false;
  bool _remote = false;
  bool _paid = false;
  bool _verificationRequired = false;
  bool _saving = false;
  bool _homepageEligible = false;
  bool _recommendationEligible = true;
  DateTime? _scheduledPublishAt;
  DateTime? _scheduledUnpublishAt;
  bool _checkingLinks = false;
  bool _aiDrafting = false;
  final TextEditingController _catInput = TextEditingController();

  /// Editable per-country offer variants (price + link overrides).
  final List<_RegionalDraft> _regional = [];

  /// Signature of the form at load; compared against the live signature to
  /// detect unsaved edits (drives the discard-changes guard).
  late final String _initialSig;

  Resource? get existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final r = existing;
    _c = {
      for (final k in [
        'title',
        'organization',
        'description',
        'countries',
        'eligibility',
        'applicationUrl',
        'affiliateUrl',
        'imageUrl',
        'logoUrl',
        'tags',
        'categories',
        'priority',
        'slug',
        'company',
        'discountText',
        'redemptionInstructions',
        'terms',
        'degrees',
        'departments',
        'interests',
        'careerGoals',
        'years',
        'fullDescription',
        'officialWebsite',
        'benefits',
        'howToApply',
        'requirements',
        'discountCode',
        'discountPercent',
        'relatedIds',
      ])
        k: TextEditingController(),
    };
    if (r != null) {
      _type = r.type;
      _status = r.status;
      _startDate = r.startDate;
      _deadline = r.deadline;
      _featured = r.featured;
      _sponsored = r.sponsored;
      _verified = r.verified;
      _remote = r.remote ?? false;
      _paid = r.paid ?? false;
      _verificationRequired = r.verificationRequired;
      _c['title']!.text = r.title;
      _c['organization']!.text = r.organization;
      _c['description']!.text = r.description;
      _c['countries']!.text = r.countries.join(', ');
      _c['eligibility']!.text = r.eligibility ?? '';
      _c['applicationUrl']!.text = r.applicationUrl ?? '';
      _c['affiliateUrl']!.text = r.affiliateUrl ?? '';
      _c['imageUrl']!.text = r.imageUrl ?? '';
      _c['logoUrl']!.text = r.logoUrl ?? '';
      _c['tags']!.text = r.tags.join(', ');
      _c['categories']!.text = r.categories.join(', ');
      _c['priority']!.text = r.priority.toString();
      _c['slug']!.text = r.slug ?? '';
      _c['company']!.text = r.company ?? '';
      _c['discountText']!.text = r.discountText ?? '';
      _c['redemptionInstructions']!.text = r.redemptionInstructions ?? '';
      _c['terms']!.text = r.terms ?? '';
      _c['degrees']!.text = r.targetDegrees.join(', ');
      _c['departments']!.text = r.targetDepartments.join(', ');
      _c['interests']!.text = r.targetInterests.join(', ');
      _c['careerGoals']!.text = r.targetCareerGoals.join(', ');
      _c['years']!.text = r.targetAcademicYears.join(', ');
      _c['fullDescription']!.text = r.fullDescription ?? '';
      _c['officialWebsite']!.text = r.officialWebsite ?? '';
      _c['benefits']!.text = r.benefits ?? '';
      _c['howToApply']!.text = r.howToApply ?? '';
      _c['requirements']!.text = r.requirements ?? '';
      _c['discountCode']!.text = r.discountCode ?? '';
      _c['discountPercent']!.text =
          r.discountPercent?.toString() ?? '';
      _c['relatedIds']!.text = r.relatedResourceIds.join(', ');
      _homepageEligible = r.homepageEligible;
      _recommendationEligible = r.recommendationEligible;
      _scheduledPublishAt = r.scheduledPublishAt;
      _scheduledUnpublishAt = r.scheduledUnpublishAt;
      for (final v in r.regionalVariants) {
        _regional.add(_RegionalDraft.fromOffer(v));
      }
    }
    _initialSig = _signature();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    for (final d in _regional) {
      d.dispose();
    }
    _catInput.dispose();
    super.dispose();
  }

  /// A cheap, stable snapshot of every editable value, used to detect edits.
  String _signature() {
    final b = StringBuffer();
    for (final e in _c.entries) {
      b
        ..write(e.key)
        ..write('=')
        ..write(e.value.text)
        ..write(';');
    }
    b.write('type=${_type.key};status=${_status.key};');
    b.write(
        'start=${_startDate?.toIso8601String()};dl=${_deadline?.toIso8601String()};');
    b.write(
        'sched=${_scheduledPublishAt?.toIso8601String()}/${_scheduledUnpublishAt?.toIso8601String()};');
    b.write(
        'flags=$_featured$_sponsored$_verified$_remote$_paid$_verificationRequired$_homepageEligible$_recommendationEligible');
    for (final d in _regional) {
      b.write('|rv=${d.signature()}');
    }
    return b.toString();
  }

  bool get _isDirty => _signature() != _initialSig;

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
            'You have unsaved changes. If you leave now they will be lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep editing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  List<String> _list(String s) => s
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  List<int> _intList(String s) => s
      .split(',')
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .toList();

  String? _nullIf(String s) => s.trim().isEmpty ? null : s.trim();

  Resource _build() {
    return Resource(
      id: existing?.id ?? '',
      type: _type,
      title: _c['title']!.text.trim(),
      organization: _c['organization']!.text.trim(),
      description: _c['description']!.text.trim(),
      countries: _list(_c['countries']!.text),
      eligibility: _nullIf(_c['eligibility']!.text),
      startDate: _startDate,
      deadline: _deadline,
      applicationUrl: _nullIf(_c['applicationUrl']!.text),
      affiliateUrl: _nullIf(_c['affiliateUrl']!.text),
      imageUrl: _nullIf(_c['imageUrl']!.text),
      logoUrl: _nullIf(_c['logoUrl']!.text),
      tags: _list(_c['tags']!.text),
      categories: _list(_c['categories']!.text),
      status: _status,
      featured: _featured,
      sponsored: _sponsored,
      verified: _verified,
      remote: _remote,
      paid: _paid,
      verificationRequired: _verificationRequired,
      priority: int.tryParse(_c['priority']!.text.trim()) ?? 0,
      slug: _nullIf(_c['slug']!.text),
      company: _nullIf(_c['company']!.text),
      discountText: _nullIf(_c['discountText']!.text),
      redemptionInstructions: _nullIf(_c['redemptionInstructions']!.text),
      terms: _nullIf(_c['terms']!.text),
      targetDegrees: _list(_c['degrees']!.text),
      targetDepartments: _list(_c['departments']!.text),
      targetInterests: _list(_c['interests']!.text),
      targetCareerGoals: _list(_c['careerGoals']!.text),
      targetAcademicYears: _intList(_c['years']!.text),
      fullDescription: _nullIf(_c['fullDescription']!.text),
      officialWebsite: _nullIf(_c['officialWebsite']!.text),
      benefits: _nullIf(_c['benefits']!.text),
      howToApply: _nullIf(_c['howToApply']!.text),
      requirements: _nullIf(_c['requirements']!.text),
      discountCode: _nullIf(_c['discountCode']!.text),
      discountPercent: num.tryParse(_c['discountPercent']!.text.trim()),
      // redemptionUrl field was removed from the editor (duplicate of the
      // "Deal / redemption link" affiliateUrl field). Preserve any stored value.
      redemptionUrl: existing?.redemptionUrl,
      // regionalVariants are managed by the Regional offers editor below.
      regionalVariants: _regional
          .map((d) => d.toOffer())
          .where((o) => o.countries.isNotEmpty)
          .toList(),
      scheduledPublishAt: _scheduledPublishAt,
      scheduledUnpublishAt: _scheduledUnpublishAt,
      homepageEligible: _homepageEligible,
      recommendationEligible: _recommendationEligible,
      relatedResourceIds: _list(_c['relatedIds']!.text),
      createdAt: existing?.createdAt,
      publishedAt: existing?.publishedAt,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    // Inline field validators (incl. publish rules) surface errors next to the
    // relevant fields; the repository re-checks as an authoritative backstop.
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repo = ref.read(cmsResourceRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final r = _build();

    setState(() => _saving = true);
    try {
      if (existing == null || existing!.id.isEmpty) {
        await repo.create(r);
      } else {
        await repo.update(r);
      }
      messenger.showSnackBar(const SnackBar(content: Text('Saved ✓')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e is ArgumentError
            ? e.message.toString()
            : 'Could not save: $e'),
        backgroundColor: AppColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Duplicates the *saved* resource as a fresh draft, then returns to the list.
  Future<void> _duplicate() async {
    if (_saving || existing == null || existing!.id.isEmpty) return;
    final repo = ref.read(cmsResourceRepositoryProvider);
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await repo.duplicate(existing!);
      messenger.showSnackBar(
          const SnackBar(content: Text('Duplicated as draft ✓')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not duplicate: $e'),
          backgroundColor: AppColors.danger));
    }
  }

  /// On-demand server-side link health check (editing an existing resource).
  Future<void> _checkLinks() async {
    if (existing == null || existing!.id.isEmpty) return;
    setState(() => _checkingLinks = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ref
          .read(firebaseFunctionsProvider)
          .httpsCallable('checkResourceUrls')
          .call({'resourceId': existing!.id});
      final health = (res.data?['health'] as Map?) ?? const {};
      final broken = health.entries
          .where((e) => (e.value as Map)['state'] == 'broken')
          .map((e) => e.key)
          .toList();
      messenger.showSnackBar(SnackBar(
        content: Text(broken.isEmpty
            ? 'All ${health.length} link(s) look OK ✓'
            : '${broken.length} link(s) may be broken: ${broken.join(', ')}'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text('Could not check links: $e'),
          backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _checkingLinks = false);
    }
  }

  /// Asks the editor for the raw details to hand to the AI drafter.
  Future<String?> _promptForAiDetails() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Draft with AI'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste everything you know about this opportunity or perk — a '
                'blurb, an email, notes, a link description. The AI fills the '
                'fields; you review before publishing.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                minLines: 5,
                maxLines: 12,
                decoration: const InputDecoration(
                  hintText:
                      'e.g. Google Summer of Code 2026 — stipended open-source '
                      'internship, applications open in March…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('Generate draft'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  /// Sends the pasted details to the `draftResource` Cloud Function and applies
  /// the returned draft into the form for review. Never publishes — the editor
  /// still reviews and saves through the normal, rules-gated path.
  Future<void> _draftWithAi() async {
    if (_saving || _aiDrafting) return;
    final messenger = ScaffoldMessenger.of(context);
    final details = await _promptForAiDetails();
    if (details == null || details.trim().length < 3) return;
    setState(() => _aiDrafting = true);
    try {
      final res = await ref
          .read(firebaseFunctionsProvider)
          .httpsCallable('draftResource')
          .call({'details': details.trim(), 'type': _type.key});
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? const {};
      _applyAiDraft(data);
      final conf = (data['confidence'] as String?) ?? 'medium';
      final notes = (data['notes'] as String?)?.trim() ?? '';
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(
          'AI draft applied ($conf confidence). Review every field before '
          'publishing.${notes.isNotEmpty ? '\n$notes' : ''}',
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('AI draft failed: $e'),
        backgroundColor: AppColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _aiDrafting = false);
    }
  }

  /// Applies a sanitized AI draft (from `draftResource`) into the form. Only
  /// non-empty values overwrite fields, so an editor's existing input for
  /// anything the AI left blank is preserved. Editorial flags (status,
  /// sponsored, featured, verified) are intentionally never touched by the AI.
  void _applyAiDraft(Map<String, dynamic> d) {
    void setText(String key, dynamic v) {
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isEmpty) return;
      _c[key]!.text = s;
    }

    void setList(String key, dynamic v) {
      if (v is List) {
        final items = v
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (items.isNotEmpty) _c[key]!.text = items.join(', ');
      }
    }

    DateTime? parseYmd(dynamic v) {
      if (v is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v.trim())) {
        return DateTime.tryParse(v.trim());
      }
      return null;
    }

    setState(() {
      final typeKey = d['type'];
      if (typeKey is String && typeKey.isNotEmpty) {
        _type = ResourceType.fromKey(typeKey);
      }

      setText('title', d['title']);
      setText('organization', d['organization']);
      setText('description', d['description']);
      setText('fullDescription', d['fullDescription']);
      setText('eligibility', d['eligibility']);
      setText('benefits', d['benefits']);
      setText('howToApply', d['howToApply']);
      setText('requirements', d['requirements']);
      setText('officialWebsite', d['officialWebsite']);
      setText('applicationUrl', d['applicationUrl']);
      setText('affiliateUrl', d['affiliateUrl']);
      setText('company', d['company']);
      setText('discountText', d['discountText']);
      setText('discountCode', d['discountCode']);
      setText('redemptionInstructions', d['redemptionInstructions']);
      setText('terms', d['terms']);
      final pct = d['discountPercent'];
      if (pct is num) _c['discountPercent']!.text = pct.toString();

      setList('countries', d['countries']);
      setList('tags', d['tags']);
      setList('categories', d['categories']);
      setList('degrees', d['targetDegrees']);
      setList('departments', d['targetDepartments']);
      setList('interests', d['targetInterests']);
      setList('careerGoals', d['targetCareerGoals']);
      final years = d['targetAcademicYears'];
      if (years is List) {
        final ys = years
            .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
            .whereType<int>()
            .toList();
        if (ys.isNotEmpty) _c['years']!.text = ys.join(', ');
      }

      final start = parseYmd(d['startDate']);
      if (start != null) _startDate = start;
      final dl = parseYmd(d['deadline']);
      if (dl != null) _deadline = dl;

      if (d['remote'] is bool) _remote = d['remote'] as bool;
      if (d['paid'] is bool) _paid = d['paid'] as bool;
    });
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  Widget _linkHealthPanel(ThemeData theme) {
    final health = existing?.urlHealth ?? const <String, UrlHealth>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in health.entries) _healthRow(theme, e.key, e.value),
        if (health.isNotEmpty) const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _checkingLinks ? null : _checkLinks,
            icon: _checkingLinks
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.link_rounded, size: 18),
            label: Text(_checkingLinks ? 'Checking…' : 'Check links now'),
          ),
        ),
      ],
    );
  }

  Widget _healthRow(ThemeData theme, String field, UrlHealth h) {
    final color = h.isOk
        ? AppColors.success
        : (h.isBroken ? AppColors.danger : AppColors.warning);
    final label = h.isOk
        ? 'Working'
        : (h.isBroken
            ? 'May be broken${h.httpStatus != null ? ' (HTTP ${h.httpStatus})' : ''}'
            : 'Unknown');
    final when = h.checkedAt != null ? ' · checked ${_ago(h.checkedAt!)}' : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(h.isOk ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$field: $label$when',
                style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDiscount = _type.isDiscount;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final leave = _isDirty ? await _confirmDiscard() : true;
        if (leave) navigator.pop();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
            if (!_saving) _save();
          },
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
            if (!_saving) _save();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? 'New resource' : 'Edit resource'),
        actions: [
          IconButton(
            tooltip: 'Draft with AI',
            icon: _aiDrafting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            onPressed: (_saving || _aiDrafting) ? null : _draftWithAi,
          ),
          IconButton(
            tooltip: 'Preview as student',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: _saving
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        CmsResourcePreviewScreen(resource: _build()))),
          ),
          if (existing != null && existing!.id.isNotEmpty)
            IconButton(
              tooltip: 'Duplicate as draft',
              icon: const Icon(Icons.copy_all_rounded),
              onPressed: _saving ? null : _duplicate,
            ),
        ],
      ),
      // A sticky action bar keeps Save reachable at all times — on a long form
      // (especially on mobile) the user shouldn't have to hunt for it.
      bottomNavigationBar: CmsSaveBar(
        saving: _saving,
        isNew: existing == null,
        label: 'resource',
        onSave: _saving ? null : _save,
      ),
      body: CmsFormBody(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              _QualityCard(
                report: evaluateResource(_build()),
                publishing: _status.isVisibleToStudents,
              ),
              _card(theme, 'Basics', 'Type, title and a short summary.', [
                Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<ResourceType>(
                          initialValue: _type,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Type'),
                          items: [
                            for (final t in ResourceType.values)
                              DropdownMenuItem(value: t, child: Text(t.label)),
                          ],
                          onChanged: (t) => setState(() => _type = t ?? _type),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DropdownButtonFormField<ResourceStatus>(
                          initialValue: _status,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Status'),
                          items: [
                            for (final s in ResourceStatus.values)
                              DropdownMenuItem(value: s, child: Text(s.label)),
                          ],
                          onChanged: (s) => setState(() => _status = s ?? _status),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _field('title', 'Title',
                      required: true, onChanged: (_) => setState(() {})),
                  _field('organization', 'Organization',
                      onChanged: (_) => setState(() {}),
                      validator: (v) =>
                          (_status.isVisibleToStudents &&
                                  (v == null || v.trim().isEmpty))
                              ? 'Required to publish (set status to Draft to '
                                  'save an incomplete resource).'
                              : null),
                  _field('description', 'Description',
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                      validator: (v) =>
                          (_status.isVisibleToStudents &&
                                  (v == null || v.trim().isEmpty))
                              ? 'A description is required to publish.'
                              : null),
                  _field('fullDescription', 'Full description (optional)',
                      maxLines: 6),
                ]),
                _categoriesCard(theme),
                _card(theme, 'Links & media',
                    isDiscount
                        ? 'The deal link and imagery shown in the app.'
                        : 'Where students apply and the imagery shown in the app.',
                    [
                  if (!isDiscount)
                    _field('applicationUrl', 'Application URL',
                        onChanged: (_) => setState(() {}), validator: (v) {
                      final val = (v ?? '').trim();
                      if (val.isNotEmpty && !isValidHttpUrl(val)) {
                        return 'Enter a valid http(s) URL.';
                      }
                      if (_status.isVisibleToStudents &&
                          _c['applicationUrl']!.text.trim().isEmpty &&
                          _c['affiliateUrl']!.text.trim().isEmpty) {
                        return 'An application link is required to publish.';
                      }
                      return null;
                    }),
                  if (isDiscount)
                    _field('affiliateUrl', 'Deal / redemption link',
                        onChanged: (_) => setState(() {}), validator: (v) {
                      final val = (v ?? '').trim();
                      if (val.isNotEmpty && !isValidHttpUrl(val)) {
                        return 'Enter a valid http(s) URL.';
                      }
                      if (_status.isVisibleToStudents &&
                          _c['applicationUrl']!.text.trim().isEmpty &&
                          _c['affiliateUrl']!.text.trim().isEmpty) {
                        return 'A deal / redemption link is required to publish.';
                      }
                      return null;
                    }),
                  _field('officialWebsite', 'Official website (optional)'),
                  _imageField('imageUrl', 'Image URL'),
                  _imageField('logoUrl', 'Logo URL'),
                  _field('slug', 'SEO slug (optional)'),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        _c['slug']!.text = slugify(_c['title']!.text);
                        setState(() {});
                      },
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                      label: const Text('Generate slug from title'),
                    ),
                  ),
                  if (existing != null && existing!.id.isNotEmpty)
                    _linkHealthPanel(theme),
                ]),
                _card(theme, 'Dates & priority',
                    'Higher priority surfaces the resource earlier in the feed.',
                    [
                  Row(
                    children: [
                      Expanded(
                          child: _dateField('Start date', _startDate,
                              (d) => setState(() => _startDate = d))),
                      const SizedBox(width: 14),
                      Expanded(
                          child: _dateField('Deadline', _deadline,
                              (d) => setState(() => _deadline = d))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _field('priority', 'Priority (higher shows first)',
                      number: true),
                ]),
                _card(theme, 'Publishing schedule',
                    'Optional. A background job flips status at these times; '
                    'unpublish must be after publish.', [
                  Row(
                    children: [
                      Expanded(
                          child: _dateField('Publish at', _scheduledPublishAt,
                              (d) => setState(() => _scheduledPublishAt = d))),
                      const SizedBox(width: 14),
                      Expanded(
                          child: _dateField(
                              'Unpublish at',
                              _scheduledUnpublishAt,
                              (d) =>
                                  setState(() => _scheduledUnpublishAt = d))),
                    ],
                  ),
                ]),
                if (!isDiscount)
                  _card(theme, 'Details',
                      'Benefits and how to apply are required to publish. '
                      'Shown on the opportunity detail page.',
                      [
                    _field('benefits', 'Benefits',
                        maxLines: 3,
                        onChanged: (_) => setState(() {}),
                        validator: (v) => (_status.isVisibleToStudents &&
                                (v == null || v.trim().isEmpty))
                            ? 'Required to publish (set status to Draft to '
                                'save an incomplete opportunity).'
                            : null),
                    _field('howToApply', 'How to apply',
                        maxLines: 3,
                        onChanged: (_) => setState(() {}),
                        validator: (v) => (_status.isVisibleToStudents &&
                                (v == null || v.trim().isEmpty))
                            ? 'Required to publish (set status to Draft to '
                                'save an incomplete opportunity).'
                            : null),
                    _field('requirements', 'Requirements (optional)',
                        maxLines: 3),
                  ]),
                _card(theme, 'Targeting',
                    'Leave a field blank to target everyone. Values are comma-separated.',
                    [
                  _field('countries', 'Countries ("Global" = all)'),
                  _field('degrees', 'Target degrees'),
                  _field('departments', 'Target departments'),
                  _field('interests', 'Target interests'),
                  _field('careerGoals', 'Target career goals'),
                  _field('tags', 'Tags'),
                  _field('relatedIds',
                      'Related resource IDs (comma-separated)'),
                ]),
                _card(theme, 'Flags', 'Toggle how this resource is presented.', [
                  _flagsGrid(),
                ]),
                if (isDiscount)
                  _card(theme, 'Discount details',
                      'Shown on discount / deal resources.', [
                    _field('company', 'Company / brand'),
                    _field('discountText',
                        'Discount headline (e.g. "50% off")'),
                    _field('discountCode', 'Discount code'),
                    _field('discountPercent', 'Discount value / percent',
                        number: true),
                    _field('redemptionInstructions', 'How to redeem',
                        maxLines: 3),
                    _field('terms', 'Terms', maxLines: 3),
                    _switchTile(
                        'Verification required',
                        'Partner handles eligibility verification',
                        _verificationRequired,
                        (v) => setState(() => _verificationRequired = v)),
                    _regionalEditor(theme),
                  ]),
              ],
            ),
          ),
        ),
      ),
        ),
      ),
    );
  }

  /// A titled panel card grouping related fields. Gives the form clear visual
  /// sections against the tinted page background.
  Widget _card(ThemeData theme, String title, String? subtitle,
      List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      decoration: softCard(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor)),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  /// Category picker sourced from the managed taxonomy (filtered to the
  /// resource's kind + enabled). Selection is stored in the `categories` list
  /// as names; legacy free-text values are preserved as removable chips.
  Widget _categoriesCard(ThemeData theme) {
    final kind =
        _type.isDiscount ? CategoryKind.discount : CategoryKind.opportunity;
    final all =
        ref.watch(cmsCategoriesProvider).valueOrNull ?? const <CmsCategory>[];
    final managed = sortedCategories(
        all.where((c) => c.kind == kind && c.enabled).toList());
    final selected = _list(_c['categories']!.text);
    final selectedSet = selected.toSet();
    final names = <String>[...managed.map((c) => c.name)];
    for (final s in selected) {
      if (!names.contains(s)) names.add(s);
    }

    void toggle(String name) {
      final cur = _list(_c['categories']!.text);
      if (!cur.remove(name)) cur.add(name);
      _c['categories']!.text = cur.join(', ');
      setState(() {});
    }

    void addTyped() {
      final name = _catInput.text.trim();
      if (name.isEmpty) return;
      final cur = _list(_c['categories']!.text);
      if (!cur.contains(name)) cur.add(name);
      _c['categories']!.text = cur.join(', ');
      _catInput.clear();
      setState(() {});
    }

    return _card(theme, 'Categories',
        'Pick from the managed taxonomy (manage it in the Categories tab), or '
        'type to add one.',
        [
          if (names.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in names)
                  _CategoryChip(
                    label: n,
                    selected: selectedSet.contains(n),
                    onTap: () => toggle(n),
                  ),
              ],
            ),
          if (names.isNotEmpty) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _catInput,
                  onSubmitted: (_) => addTyped(),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Add a category (e.g. Software, Travel)',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: addTyped,
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Add category',
              ),
            ],
          ),
        ]);
  }

  /// Responsive grid of flag toggles: two columns on wide forms, one on narrow.
  Widget _flagsGrid() {
    final tiles = <Widget>[
      _switchTile('Featured', 'Pin near the top of the feed', _featured,
          (v) => setState(() => _featured = v)),
      _switchTile('Sponsored', 'Marked as a paid placement', _sponsored,
          (v) => setState(() => _sponsored = v)),
      _switchTile('Verified', 'Show the verified badge', _verified,
          (v) => setState(() => _verified = v)),
      _switchTile('Remote', 'Location-independent', _remote,
          (v) => setState(() => _remote = v)),
      _switchTile('Paid', 'Involves a payment', _paid,
          (v) => setState(() => _paid = v)),
      _switchTile('Homepage eligible', 'May appear on the Home surface',
          _homepageEligible, (v) => setState(() => _homepageEligible = v)),
      _switchTile(
          'Recommendation eligible',
          'Allowed in personalized recommendations',
          _recommendationEligible,
          (v) => setState(() => _recommendationEligible = v)),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final twoCol = c.maxWidth > 440;
        final tileW = twoCol ? (c.maxWidth - 12) / 2 : c.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final t in tiles) SizedBox(width: tileW, child: t),
          ],
        );
      },
    );
  }

  Widget _field(String key, String label,
      {bool required = false,
      bool number = false,
      int maxLines = 1,
      String? Function(String?)? validator,
      ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _c[key],
        maxLines: maxLines,
        keyboardType: number ? TextInputType.number : null,
        inputFormatters:
            number ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
        validator: validator ??
            (required
                ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
                : null),
      ),
    );
  }

  /// A URL field with a live thumbnail preview + inline validity indicator.
  Widget _imageField(String key, String label) {
    final url = _c[key]!.text.trim();
    final valid = isValidHttpUrl(url);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _c[key],
            decoration: InputDecoration(
              labelText: label,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Choose from media library',
                    icon: const Icon(Icons.perm_media_outlined, size: 20),
                    onPressed: () async {
                      final url = await showMediaPicker(context);
                      if (url != null && url.isNotEmpty) {
                        _c[key]!.text = url;
                        setState(() {});
                      }
                    },
                  ),
                  if (url.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                          valid
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                          color: valid ? AppColors.success : AppColors.danger,
                          size: 20),
                    ),
                ],
              ),
            ),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final val = (v ?? '').trim();
              if (val.isNotEmpty && !isValidHttpUrl(val)) {
                return 'Enter a valid http(s) image URL.';
              }
              return null;
            },
          ),
          if (valid) ...[
            const SizedBox(height: 8),
            _ImagePreview(url: url),
          ],
        ],
      ),
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime?> set) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 5),
        );
        if (picked != null) set(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_rounded, size: 18)
              : IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () => set(null),
                ),
        ),
        child: Text(value == null
            ? 'Not set'
            : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'),
      ),
    );
  }

  Widget _switchTile(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor, width: 1.2),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  /// Editor for per-country offer variants (price + link overrides). Leave the
  /// resource-level headline/link as the default; add a row per country that
  /// prices/links differently (e.g. Spotify India ₹59 vs US $5.99).
  Widget _regionalEditor(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.public_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Regional offers (per country)',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Optional. Each row overrides the price and/or link for one or more '
            'countries (comma-separated). Countries without a row see the '
            'default headline/link above.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _regional.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor, width: 1.2),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _regional[i].countries,
                          decoration: const InputDecoration(
                              labelText: 'Country(ies), comma-separated',
                              isDense: true),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove region',
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: AppColors.danger),
                        onPressed: () => setState(() {
                          _regional.removeAt(i).dispose();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _regional[i].price,
                    decoration: const InputDecoration(
                        labelText: 'Price / headline for this region (e.g. ₹59/mo)',
                        isDense: true),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _regional[i].url,
                    decoration: const InputDecoration(
                        labelText: 'Link for this region (optional)',
                        isDense: true),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _regional.add(_RegionalDraft())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add region'),
            ),
          ),
        ],
      ),
    );
  }
}


/// A bounded, framed thumbnail preview for an image/logo URL, with graceful
/// loading and error states.
class _ImagePreview extends StatelessWidget {
  final String url;
  const _ImagePreview({required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (context, error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_rounded,
                  color: AppColors.danger, size: 22),
              const SizedBox(height: 6),
              Text('Could not load image',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact "content quality" panel: a 0–100 score with publish-blocking errors
/// and advisory warnings, so admins see exactly why something can't publish.
class _QualityCard extends StatelessWidget {
  final CmsQualityReport report;

  /// Whether the current status is student-visible (i.e. errors will block).
  final bool publishing;
  const _QualityCard({required this.report, required this.publishing});

  Color _scoreColor() {
    if (report.errors.isNotEmpty) return AppColors.danger;
    if (report.score >= 85) return AppColors.success;
    if (report.score >= 60) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _scoreColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: softCard(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, color: color, size: 20),
              const SizedBox(width: 8),
              Text('Content quality',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${report.score}/100',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: color, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: report.score / 100,
              minHeight: 8,
              backgroundColor: theme.dividerColor,
              color: color,
            ),
          ),
          if (report.errors.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(publishing ? 'Errors (blocking publish)' : 'Errors',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: AppColors.danger)),
            const SizedBox(height: 6),
            for (final e in report.errors)
              _IssueRow(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.danger,
                  text: e.message),
          ],
          if (report.warnings.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Warnings',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: AppColors.warning)),
            const SizedBox(height: 6),
            for (final w in report.warnings)
              _IssueRow(
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.warning,
                  text: w.message),
          ],
          if (report.errors.isEmpty && report.warnings.isEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 18),
              const SizedBox(width: 6),
              Text('Looks great — ready to publish.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor)),
            ]),
          ],
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _IssueRow(
      {required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// A selectable category pill (visible on any background), filled when selected.
class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? AppColors.primary : theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
            color: selected ? AppColors.primary : theme.dividerColor,
            width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: selected
                          ? Colors.white
                          : theme.textTheme.bodyMedium?.color,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}


/// Mutable editor row backing a [RegionalOffer] (per-country price/link).
class _RegionalDraft {
  final TextEditingController countries;
  final TextEditingController price;
  final TextEditingController url;

  _RegionalDraft({String countries = '', String price = '', String url = ''})
      : countries = TextEditingController(text: countries),
        price = TextEditingController(text: price),
        url = TextEditingController(text: url);

  factory _RegionalDraft.fromOffer(RegionalOffer o) => _RegionalDraft(
        countries: o.countries.join(', '),
        price: o.discountText ?? '',
        url: o.url ?? '',
      );

  RegionalOffer toOffer() => RegionalOffer(
        countries: countries.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        discountText: price.text.trim().isEmpty ? null : price.text.trim(),
        url: url.text.trim().isEmpty ? null : url.text.trim(),
      );

  String signature() => '${countries.text}|${price.text}|${url.text}';

  void dispose() {
    countries.dispose();
    price.dispose();
    url.dispose();
  }
}
