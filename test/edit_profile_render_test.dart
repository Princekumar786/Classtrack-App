import 'package:classtrack/core/theme/app_theme.dart';
import 'package:classtrack/features/auth/domain/app_user.dart';
import 'package:classtrack/features/auth/presentation/providers/auth_providers.dart';
import 'package:classtrack/features/auth/presentation/screens/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: the Edit Profile body must lay out under the REAL app theme.
///
/// The app's `outlinedButtonTheme` uses `minimumSize: Size.fromHeight(54)`
/// (infinite width). A trailing `OutlinedButton` placed directly in a Row (the
/// character picker's "Change" button) then received unbounded width and threw
/// "BoxConstraints forces an infinite width" during layout, cascading to blank
/// the entire ListView. These tests pump the screen under both real themes and
/// assert no exception + real content is present.
Future<void> _pumpAndCheck(WidgetTester tester, ThemeData theme) async {
  tester.view.physicalSize = const Size(1170, 2532); // iPhone-ish
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.resetPhysicalSize);

  final profile = AppUser(
    uid: 'user123',
    displayName: 'Prince',
    email: 'prince@classtracks.app',
    avatarCharacter: 'icons8-batman-144.png',
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [
      userProfileProvider.overrideWith((ref) => Stream.value(profile)),
    ],
    child: MaterialApp(theme: theme, home: const EditProfileScreen()),
  ));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  expect(tester.takeException(), isNull);
  expect(find.text('Profile character'), findsOneWidget);
  expect(find.text('Change'), findsOneWidget);
  expect(tester.getSize(find.byType(ListView)).height, greaterThan(100));
}

void main() {
  testWidgets('Edit profile lays out under real dark theme',
      (t) async => _pumpAndCheck(t, AppTheme.dark()));
  testWidgets('Edit profile lays out under real light theme',
      (t) async => _pumpAndCheck(t, AppTheme.light()));
}
