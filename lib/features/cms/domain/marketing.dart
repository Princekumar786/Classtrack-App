import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/validators.dart';

/// Where a banner or campaign can be placed (PRD §11/§19).
///
/// Each key maps to a concrete slot in the app that renders a [PlacementBanner]
/// and/or [PlacementCampaign]. Keys are the stable strings persisted in
/// Firestore — never rename an existing key (only its [label]).
class Placements {
  Placements._();

  // Home surfaces.
  static const home = 'home'; // Home (bottom, near lifecycle banners)
  static const homeTop = 'home_top';
  static const homeAboveQuickTools = 'home_above_quick_tools';
  static const homeBelowStats = 'home_below_stats';
  static const homeBelowTimeline = 'home_below_timeline';
  static const homeBelowTasks = 'home_below_tasks';

  // Feature destinations.
  static const opportunities = 'opportunities';
  static const discounts = 'discounts';
  static const attendance = 'attendance';
  static const tasks = 'tasks';
  static const grades = 'grades';
  static const exams = 'exams';

  // Generic / legacy slots.
  static const featured = 'featured';
  static const banner = 'banner';

  /// Shown in the Home notification bell (in-app announcements), not on a page.
  static const announcement = 'announcement';

  static const all = <String>[
    homeTop,
    homeAboveQuickTools,
    homeBelowStats,
    homeBelowTimeline,
    homeBelowTasks,
    home,
    attendance,
    tasks,
    grades,
    exams,
    opportunities,
    discounts,
    announcement,
    featured,
    banner,
  ];

  static String label(String key) {
    switch (key) {
      case home:
        return 'Home — bottom';
      case homeTop:
        return 'Home — top';
      case homeAboveQuickTools:
        return 'Home — above quick tools';
      case homeBelowStats:
        return 'Home — below stats';
      case homeBelowTimeline:
        return 'Home — below timeline';
      case homeBelowTasks:
        return 'Home — below tasks';
      case opportunities:
        return 'Opportunities';
      case discounts:
        return 'Perks';
      case attendance:
        return 'Attendance';
      case tasks:
        return 'Tasks';
      case grades:
        return 'Grades';
      case exams:
        return 'Exams';
      case announcement:
        return 'Announcement (bell)';
      case featured:
        return 'Featured card';
      case banner:
        return 'Banner';
      default:
        return key;
    }
  }
}

/// A marketing banner (PRD §19). CMS-managed; the app reads only `published`
/// ones. Lets marketing change a Home banner without shipping a new build.
class CmsBanner {
  final String id;
  final String title;
  final String? imageUrl;
  final String? ctaLabel;
  final String? destination; // URL or in-app route
  final List<String> countries; // empty/"Global" = everywhere
  final String? category;
  final DateTime? startDate;
  final DateTime? endDate;
  final int priority;
  final String placement;
  final bool sponsored;
  final bool published;

  /// Whether Pro subscribers see this banner. Off = shown to free users only
  /// (e.g. upgrade offers or ads you don't want paying users to see). Missing
  /// in older docs, which default to true so existing banners keep showing.
  final bool showToPro;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CmsBanner({
    required this.id,
    required this.title,
    this.imageUrl,
    this.ctaLabel,
    this.destination,
    this.countries = const [],
    this.category,
    this.startDate,
    this.endDate,
    this.priority = 0,
    this.placement = Placements.home,
    this.sponsored = false,
    this.published = false,
    this.showToPro = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Live = published and within its (optional) scheduled window.
  bool isLive([DateTime? now]) {
    if (!published) return false;
    final t = now ?? DateTime.now();
    if (startDate != null && t.isBefore(startDate!)) return false;
    if (endDate != null && t.isAfter(endDate!)) return false;
    return true;
  }

  factory CmsBanner.fromMap(String id, Map<String, dynamic> m) {
    DateTime? ts(dynamic v) => (v as Timestamp?)?.toDate();
    return CmsBanner(
      id: id,
      title: Validators.sanitizeText(
        (m['title'] as String?) ?? '',
        maxLength: 120,
      ),
      imageUrl: m['imageUrl'] as String?,
      ctaLabel: m['ctaLabel'] as String?,
      destination: m['destination'] as String?,
      countries:
          (m['countries'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      category: m['category'] as String?,
      startDate: ts(m['startDate']),
      endDate: ts(m['endDate']),
      priority: (m['priority'] as num?)?.toInt() ?? 0,
      placement: (m['placement'] as String?) ?? Placements.home,
      sponsored: (m['sponsored'] as bool?) ?? false,
      published: (m['published'] as bool?) ?? false,
      showToPro: (m['showToPro'] as bool?) ?? true,
      createdAt: ts(m['createdAt']),
      updatedAt: ts(m['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'imageUrl': imageUrl,
    'ctaLabel': ctaLabel,
    'destination': destination,
    'countries': countries,
    'category': category,
    'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
    'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
    'priority': priority,
    'placement': placement,
    'sponsored': sponsored,
    'published': published,
    'showToPro': showToPro,
    'createdAt': createdAt != null
        ? Timestamp.fromDate(createdAt!)
        : FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// A sponsored campaign (PRD §11) — links a sponsor to a resource/placement
/// over a date range.
class Campaign {
  final String id;
  final String company;
  final String name;
  final String? resourceId;
  final List<String> countries;
  final String? targetAudience;
  final DateTime? startDate;
  final DateTime? endDate;
  final String placement;
  final int priority;
  final bool sponsored;
  final bool published;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Campaign({
    required this.id,
    required this.company,
    required this.name,
    this.resourceId,
    this.countries = const [],
    this.targetAudience,
    this.startDate,
    this.endDate,
    this.placement = Placements.home,
    this.priority = 0,
    this.sponsored = true,
    this.published = false,
    this.createdAt,
    this.updatedAt,
  });

  bool isLive([DateTime? now]) {
    if (!published) return false;
    final t = now ?? DateTime.now();
    if (startDate != null && t.isBefore(startDate!)) return false;
    if (endDate != null && t.isAfter(endDate!)) return false;
    return true;
  }

  factory Campaign.fromMap(String id, Map<String, dynamic> m) {
    DateTime? ts(dynamic v) => (v as Timestamp?)?.toDate();
    return Campaign(
      id: id,
      company: Validators.sanitizeText(
        (m['company'] as String?) ?? '',
        maxLength: 120,
      ),
      name: Validators.sanitizeText(
        (m['name'] as String?) ?? '',
        maxLength: 140,
      ),
      resourceId: m['resourceId'] as String?,
      countries:
          (m['countries'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      targetAudience: m['targetAudience'] as String?,
      startDate: ts(m['startDate']),
      endDate: ts(m['endDate']),
      placement: (m['placement'] as String?) ?? Placements.home,
      priority: (m['priority'] as num?)?.toInt() ?? 0,
      sponsored: (m['sponsored'] as bool?) ?? true,
      published: (m['published'] as bool?) ?? false,
      createdAt: ts(m['createdAt']),
      updatedAt: ts(m['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() => {
    'company': company,
    'name': name,
    'resourceId': resourceId,
    'countries': countries,
    'targetAudience': targetAudience,
    'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
    'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
    'placement': placement,
    'priority': priority,
    'sponsored': sponsored,
    'published': published,
    'createdAt': createdAt != null
        ? Timestamp.fromDate(createdAt!)
        : FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
