// Verifies the Sign-up screen exposes a working "Continue with Google" option.
//
// Regression test for the bug where users could not sign up with Google: the
// SignupScreen previously rendered only email/password fields, so there was no
// Google entry point in the sign-up flow at all. This test asserts the button
// exists and that tapping it drives AuthController.signInWithGoogle().

import 'package:classtrack/core/providers/app_settings_provider.dart';
import 'package:classtrack/core/theme/app_theme.dart';
import 'package:classtrack/features/auth/data/auth_repository.dart';
import 'package:classtrack/features/auth/presentation/providers/auth_providers.dart';
import 'package:classtrack/features/auth/presentation/screens/signup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal fake so we can build an [AuthController] without touching Firebase.
/// AuthController never calls into it in this test because the spy overrides
/// signInWithGoogle() entirely.
class _FakeRepo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Records calls to signInWithGoogle instead of hitting Google/Firebase.
class _SpyAuthController extends AuthController {
  _SpyAuthController(super.repo);
  int googleCalls = 0;

  @override
  Future<bool> signInWithGoogle() async {
    googleCalls++;
    return true;
  }
}

void main() {
  testWidgets('Sign-up screen offers Google and wires it to signInWithGoogle',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final spy = _SpyAuthController(_FakeRepo());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          authControllerProvider.overrideWith((ref) => spy),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SignupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The Google entry point must be present on the sign-up screen.
    final googleButton = find.text('Continue with Google');
    expect(googleButton, findsOneWidget,
        reason: 'Sign-up screen is missing the Google option');

    // Tapping it must invoke the Google sign-in/sign-up flow.
    await tester.ensureVisible(googleButton);
    await tester.tap(googleButton);
    await tester.pump();

    expect(spy.googleCalls, 1,
        reason: 'Tapping "Continue with Google" should call signInWithGoogle');
  });
}
