import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/providers/app_settings_provider.dart';
import '../../../../services/analytics_service.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../moments/data/moment_share_service.dart';
import '../../domain/semester_wrapped.dart';
import '../providers/semester_providers.dart';
import '../widgets/semester_wrapped_card.dart';

/// Preview + share of the "Semester Wrapped" card for one past semester.
class SemesterWrappedScreen extends ConsumerStatefulWidget {
  final String semesterId;
  const SemesterWrappedScreen({super.key, required this.semesterId});

  @override
  ConsumerState<SemesterWrappedScreen> createState() =>
      _SemesterWrappedScreenState();
}

class _SemesterWrappedScreenState extends ConsumerState<SemesterWrappedScreen> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share(SemesterWrapped data, String? code) async {
    setState(() => _sharing = true);
    try {
      final invite = code != null
          ? 'Join with my code $code and get '
              '${AppConstants.referralWelcomeDays} days of Pro free:\n'
          : '';
      final ok = await MomentShareService.shareBoundary(
        _cardKey,
        caption: '${data.shareText}\n\n'
            'I track attendance, grades & exams with ClassTrack 📚\n'
            '$invite${AppConstants.playStoreUrl}',
        subject: 'My ${data.semesterName} on ClassTrack',
      );
      ref.read(analyticsProvider).log('semester_wrapped_shared', {'ok': ok});
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not create the image. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final semester = ref.watch(semesterByIdProvider(widget.semesterId));
    final stats = ref.watch(semesterStatsProvider(widget.semesterId));
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final tenPoint = ref.watch(gpaScaleProvider) == GpaScaleType.ten;
    final data = SemesterWrapped.build(
      semesterName: semester?.name ?? 'My semester',
      stats: stats,
      tenPoint: tenPoint,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Semester Wrapped')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          RepaintBoundary(
            key: _cardKey,
            child: SemesterWrappedCard(
              data: data,
              studentName: profile?.displayName ?? 'A student',
              inviteCode: profile?.referralCode,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed:
                _sharing ? null : () => _share(data, profile?.referralCode),
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.ios_share_rounded),
            label: Text(_sharing ? 'Preparing…' : 'Share to story'),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your official SGPA or final grades on the semester page to '
            'make the card exact.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
