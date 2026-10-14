import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/moment_share_service.dart';
import '../../domain/shareable_moment.dart';
import '../providers/moment_providers.dart';
import '../widgets/moment_card.dart';

/// A gallery of the student's real milestones, each rendered as a beautiful,
/// share-ready card. Tapping "Share" rasterises the card to a PNG and opens the
/// OS share sheet so it can be posted anywhere.
class MomentsScreen extends ConsumerWidget {
  const MomentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final moments = ref.watch(momentsProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final name = profile?.displayName ?? 'A student';
    final code = profile?.referralCode;

    return Scaffold(
      appBar: AppBar(title: const Text('Shareable moments')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Turn your wins into share-worthy cards 🎉',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'These are built from your real stats. Post them to your story and '
            'inspire your friends to keep up.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < moments.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: _MomentTile(
                moment: moments[i],
                studentName: name,
                inviteCode: code,
              )
                  .animate()
                  .fadeIn(delay: (i * 70).ms, duration: 350.ms)
                  .slideY(begin: 0.08, curve: Curves.easeOutCubic),
            ),
        ],
      ),
    );
  }
}

class _MomentTile extends StatefulWidget {
  final ShareableMoment moment;
  final String studentName;
  final String? inviteCode;

  const _MomentTile({
    required this.moment,
    required this.studentName,
    this.inviteCode,
  });

  @override
  State<_MomentTile> createState() => _MomentTileState();
}

class _MomentTileState extends State<_MomentTile> {
  final _cardKey = GlobalKey();
  bool _sharing = false;

  String _caption() {
    final code = widget.inviteCode;
    final invite = code != null
        ? 'Join with my code $code and get '
            '${AppConstants.referralWelcomeDays} days of Pro free:\n'
        : '';
    return '${widget.moment.shareText}\n\n'
        'I track attendance, grades, habits & study time with ClassTrack 📚\n'
        '$invite${AppConstants.playStoreUrl}';
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final ok = await MomentShareService.shareBoundary(
        _cardKey,
        caption: _caption(),
        subject: 'My ClassTrack moment',
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not create the image. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // The RepaintBoundary is what gets captured to an image.
        RepaintBoundary(
          key: _cardKey,
          child: MomentCard(
            moment: widget.moment,
            studentName: widget.studentName,
            inviteCode: widget.inviteCode,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: Text(_sharing ? 'Preparing…' : 'Share this'),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.moment.gradient.last,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
