import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/app_settings_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class ClassTrackApp extends ConsumerWidget {
  const ClassTrackApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final accent = ref.watch(accentColorProvider);
    final use24 = ref.watch(timeFormatProvider).use24;

    return MaterialApp.router(
      title: 'ClassTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(accent: accent),
      darkTheme: AppTheme.dark(accent: accent),
      themeMode: themeMode,
      routerConfig: router,
      // Honour the user's system font-size preference for accessibility, but
      // clamp the range so very large scales don't clip fixed-height cards,
      // chips and mark buttons (which caused overflow/ellipsis loss). Users who
      // bump their device font size still get noticeably larger text (up to
      // 1.3x); we just cap the extreme end where the dense dashboards break.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.9,
              maxScaleFactor: 1.3,
            ),
            // In-app 12/24-hour choice (Settings → Appearance). Every time in
            // the app is formatted via TimeOfDay.format, which reads this.
            alwaysUse24HourFormat: use24 ?? mq.alwaysUse24HourFormat,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
