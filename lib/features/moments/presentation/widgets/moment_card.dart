import 'package:flutter/material.dart';

import '../../domain/shareable_moment.dart';

/// A polished, share-ready card visualising one [ShareableMoment]. Designed at
/// a 4:5 portrait ratio (great for stories/feeds) and captured to PNG via a
/// RepaintBoundary. All sizes scale off the available width so it renders
/// crisply whether shown small in a list or captured at high pixel-ratio.
class MomentCard extends StatelessWidget {
  final ShareableMoment moment;
  final String studentName;

  /// Optional invite code stamped on the card to drive referrals.
  final String? inviteCode;

  const MomentCard({
    super.key,
    required this.moment,
    required this.studentName,
    this.inviteCode,
  });

  @override
  Widget build(BuildContext context) {
    // A fixed-ratio, share-ready graphic: every size derives from the card
    // width, so the OS text-size setting must not scale it (it would overflow
    // the fixed 4:5 frame). The card is shown/exported as an image.
    return MediaQuery.withNoTextScaling(
      child: AspectRatio(
      aspectRatio: 4 / 5,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          const onGradient = Colors.white;
          final subtle = Colors.white.withValues(alpha: 0.82);

          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: moment.gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(w * 0.07),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Decorative translucent blobs.
                Positioned(
                  top: -w * 0.22,
                  right: -w * 0.18,
                  child: _blob(w * 0.55, Colors.white.withValues(alpha: 0.12)),
                ),
                Positioned(
                  bottom: -w * 0.28,
                  left: -w * 0.20,
                  child: _blob(w * 0.6, Colors.white.withValues(alpha: 0.08)),
                ),
                Padding(
                  padding: EdgeInsets.all(w * 0.075),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _brandRow(w, onGradient),
                      const Spacer(),
                      Text(moment.emoji,
                          style: TextStyle(fontSize: w * 0.13)),
                      SizedBox(height: w * 0.02),
                      // Hero value — auto-fits long strings.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          moment.value,
                          maxLines: 1,
                          style: TextStyle(
                            color: onGradient,
                            fontSize: w * 0.20,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                      SizedBox(height: w * 0.01),
                      Text(
                        moment.valueLabel.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: subtle,
                          fontSize: w * 0.04,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        moment.headline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onGradient,
                          fontSize: w * 0.072,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      SizedBox(height: w * 0.015),
                      Text(
                        moment.caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: subtle,
                          fontSize: w * 0.042,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: w * 0.04),
                      Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
                      SizedBox(height: w * 0.035),
                      _footerRow(w, onGradient, subtle),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _brandRow(double w, Color onGradient) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
              horizontal: w * 0.035, vertical: w * 0.018),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(w * 0.05),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('📚', style: TextStyle(fontSize: w * 0.045)),
              SizedBox(width: w * 0.02),
              Text(
                'ClassTrack',
                style: TextStyle(
                  color: onGradient,
                  fontSize: w * 0.045,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        Icon(Icons.auto_awesome_rounded,
            color: Colors.white.withValues(alpha: 0.85), size: w * 0.06),
      ],
    );
  }

  Widget _footerRow(double w, Color onGradient, Color subtle) {
    final name = studentName.trim().isEmpty ? 'A student' : studentName.trim();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onGradient,
                  fontSize: w * 0.05,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                inviteCode != null
                    ? 'Join with code $inviteCode'
                    : 'Join me on ClassTrack',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subtle, fontSize: w * 0.038),
              ),
            ],
          ),
        ),
        Container(
          width: w * 0.11,
          height: w * 0.11,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(w * 0.03),
          ),
          child: Icon(Icons.qr_code_2_rounded,
              color: onGradient, size: w * 0.07),
        ),
      ],
    );
  }
}
