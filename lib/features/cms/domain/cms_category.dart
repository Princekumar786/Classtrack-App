import 'cms_metrics.dart' show slugify;

/// Which surface a category belongs to.
enum CategoryKind {
  opportunity('opportunity', 'Opportunity'),
  discount('discount', 'Discount');

  const CategoryKind(this.key, this.label);
  final String key;
  final String label;

  static CategoryKind fromKey(String? k) => values.firstWhere(
    (v) => v.key == k,
    orElse: () => CategoryKind.opportunity,
  );
}

/// A manageable taxonomy entry (`categories/{id}`) — replaces hard-coded lists.
/// Disabled categories are hidden from pickers but preserved so existing
/// references never break.
class CmsCategory {
  final String id;
  final String name;
  final String slug;
  final CategoryKind kind;
  final bool enabled;
  final int sort;

  const CmsCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.kind,
    this.enabled = true,
    this.sort = 0,
  });

  factory CmsCategory.fromMap(String id, Map<String, dynamic> m) => CmsCategory(
    id: id,
    name: (m['name'] as String?)?.trim() ?? '',
    slug: (m['slug'] as String?) ?? slugify((m['name'] as String?) ?? ''),
    kind: CategoryKind.fromKey(m['kind'] as String?),
    enabled: (m['enabled'] as bool?) ?? true,
    sort: (m['sort'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'slug': slug.isEmpty ? slugify(name) : slug,
    'kind': kind.key,
    'enabled': enabled,
    'sort': sort,
  };

  CmsCategory copyWith({
    String? name,
    bool? enabled,
    int? sort,
    CategoryKind? kind,
  }) => CmsCategory(
    id: id,
    name: name ?? this.name,
    slug: (name != null) ? slugify(name) : slug,
    kind: kind ?? this.kind,
    enabled: enabled ?? this.enabled,
    sort: sort ?? this.sort,
  );
}

/// Sorts categories for display: by [sort] then name (stable, pure).
List<CmsCategory> sortedCategories(List<CmsCategory> list) {
  final out = [...list]
    ..sort(
      (a, b) => a.sort != b.sort
          ? a.sort.compareTo(b.sort)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  return out;
}
