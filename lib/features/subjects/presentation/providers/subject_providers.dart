import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../data/subject_repository.dart';
import '../../domain/subject.dart';

/// Repository bound to the current user. Null when signed out.
final subjectRepositoryProvider = Provider<SubjectRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return SubjectRepository(db: ref.watch(firestoreProvider), uid: uid);
});

/// Live list of the user's CURRENT-semester subjects (archived ones hidden).
final subjectsStreamProvider = StreamProvider<List<Subject>>((ref) {
  final repo = ref.watch(subjectRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchSubjects();
});

/// Every subject, including archived semesters (Past semesters screens).
final allSubjectsStreamProvider = StreamProvider<List<Subject>>((ref) {
  final repo = ref.watch(subjectRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchAllSubjects();
});

/// Live single subject by id.
final subjectProvider =
    StreamProvider.family<Subject?, String>((ref, id) {
  final repo = ref.watch(subjectRepositoryProvider);
  if (repo == null) return Stream.value(null);
  return repo.watchSubject(id);
});

/// Quick lookup map id -> Subject. Includes archived subjects too, so notes,
/// tasks and focus sessions linked to a past semester's subject keep showing
/// its name. (Lists of "current" subjects must use [subjectsStreamProvider].)
final subjectsByIdProvider = Provider<Map<String, Subject>>((ref) {
  final current = ref.watch(subjectsStreamProvider).valueOrNull ?? const [];
  final all = ref.watch(allSubjectsStreamProvider).valueOrNull ?? const [];
  return {
    for (final s in all) s.id: s,
    for (final s in current) s.id: s,
  };
});
