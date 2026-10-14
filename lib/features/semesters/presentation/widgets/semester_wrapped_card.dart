import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/semester_wrapped.dart';

/// Share-ready 4:5 "Semester Wrapped" card. Every size scales off the card
/// width (like MomentCard) so it looks the same on screen and when captured
/// to PNG at a high pixel ratio.
class SemesterWrappedCard extends StatelessWidget {
  final SemesterWrapped data;
  final String studentName;
  final String? inviteCode;

  const SemesterWrappedCard({
    super.key,
    required this.data,
    required this.studentName,
    this.inviteCode,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          const on = Colors.white;
          final subtle = Colors.white.withValues(alpha: 0.82);
          final name =
              studentName.trim().isEmpty ? 'A student' : studentName.trim();
          return Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1B4B), AppColors.primary, Color(0xFFEC4899)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(w * 0.07),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Positioned(
                top: -w * 0.2,
                right: -w * 0.2,
                child: _blob(w * 0.6, Colors.white.withValues(alpha: 0.10)),
              ),
              Padding(
                padding: EdgeInsets.all(w * 0.075),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('📚 ClassTrack',
                          style: TextStyle(
                              color: on,
                              fontSize: w * 0.045,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('WRAPPED',
                          style: TextStyle(
                              color: subtle,
                              fontSize: w * 0.038,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2)),
                    ]),
                    SizedBox(height: w * 0.05),
                    Text(data.semesterName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: on,
                            fontSize: w * 0.075,
                            fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text(data.emoji, style: TextStyle(fontSize: w * 0.11)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(data.heroValue,
                          maxLines: 1,
                          style: TextStyle(
                              color: on,
                              fontSize: w * 0.2,
                              fontWeight: FontWeight.w900,
                              height: 1,
                              letterSpacing: -1)),
                    ),
                    Text(data.heroLabel.toUpperCase(),
                        style: TextStyle(
                            color: subtle,
                            fontSize: w * 0.04,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5)),
                    SizedBox(height: w * 0.05),
                    Row(children: [
                      for (final (label, value) in data.stats)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(value,
                                  maxLines: 1,
                                  style: TextStyle(
                                      color: on,
                                      fontSize: w * 0.06,
                                      fontWeight: FontWeight.w800)),
                              Text(label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: subtle, fontSize: w * 0.032)),
                            ],
                          ),
                        ),
                    ]),
                    const Spacer(),
                    Text(data.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: on,
                            fontSize: w * 0.065,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: w * 0.035),
                    Divider(
                        color: Colors.white.withValues(alpha: 0.25), height: 1),
                    SizedBox(height: w * 0.03),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: on,
                            fontSize: w * 0.048,
                            fontWeight: FontWeight.w700)),
                    Text(
                        inviteCode != null
                            ? 'Join with code $inviteCode'
                            : 'Join me on ClassTrack',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: subtle, fontSize: w * 0.036)),
                  ],
                ),
              ),
            ]),
          );
        }),
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
