import '../../opportunities/domain/resource.dart';

/// Builds a CSV export of the resource library.
///
/// Pure and side-effect-free so it can be unit-tested; the actual file download
/// is handled separately (see `data/file_download.dart`). Follows RFC-4180
/// quoting: fields containing a comma, quote or newline are wrapped in double
/// quotes and inner quotes are doubled.
String buildResourcesCsv(List<Resource> resources) {
  const headers = <String>[
    'id',
    'title',
    'type',
    'organization',
    'stored_status',
    'effective_status',
    'countries',
    'deadline',
    'priority',
    'sponsored',
    'featured',
    'verified',
    'application_url',
  ];

  String cell(Object? value) {
    var s = value?.toString() ?? '';
    // Formula-injection guard: a spreadsheet treats a cell starting with
    // = + - @ (also tab/CR) as a formula. Neutralise string cells by prefixing
    // an apostrophe. Only applied to STRINGS so numeric/bool cells stay intact.
    if (value is String &&
        s.isNotEmpty &&
        (s.startsWith('=') ||
            s.startsWith('+') ||
            s.startsWith('-') ||
            s.startsWith('@') ||
            s.startsWith('\t') ||
            s.startsWith('\r'))) {
      s = "'$s";
    }
    final needsQuote =
        s.contains(',') ||
        s.contains('"') ||
        s.contains('\n') ||
        s.contains('\r');
    if (!needsQuote) return s;
    return '"${s.replaceAll('"', '""')}"';
  }

  String dateOnly(DateTime? d) => d == null
      ? ''
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  final rows = <String>[headers.map(cell).join(',')];
  for (final r in resources) {
    rows.add(
      [
        cell(r.id),
        cell(r.title),
        cell(r.type.label),
        cell(r.organization),
        cell(r.status.label),
        cell(r.effectiveStatus.label),
        cell(r.countries.join('; ')),
        cell(dateOnly(r.deadline)),
        cell(r.priority),
        cell(r.sponsored),
        cell(r.featured),
        cell(r.verified),
        cell(r.applicationUrl ?? ''),
      ].join(','),
    );
  }
  // CRLF line endings for maximum spreadsheet compatibility.
  return rows.join('\r\n');
}
