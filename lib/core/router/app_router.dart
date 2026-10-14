import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/firebase_providers.dart';
import '../../features/auth/presentation/providers/auth_providers.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/verify_email_screen.dart';
import '../../features/home/presentation/screens/home_shell.dart';
import '../../services/notification_service.dart';
import '../../services/analytics_identity.dart';
import '../../services/error_reporter.dart';

/// App router. Redirects between onboarding → auth → home based on state.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(authStateProvider, (prev, next) {
      refresh.value++;
      // On sign-out / account removal, wipe ALL scheduled local notifications
      // so the previous account's class, task and exam reminders never fire
      // for the next account on a shared device. The new user's reminders are
      // re-scheduled by reminderSyncProvider once HomeShell mounts. (An account
      // switch always passes through a logged-out state, so this also covers
      // switching users — cancellation happens while signed out, avoiding any
      // race with the next user's re-scheduling.)
      final wasLoggedIn = prev?.valueOrNull != null;
      final nowLoggedIn = next.valueOrNull != null;
      if (wasLoggedIn && !nowLoggedIn) {
        ref.read(notificationServiceProvider).cancelAll();
      }
      // Keep PostHog's identity in sync with Firebase Auth: tie events to the
      // user on login, and reset (back to an anonymous id, clearing stored
      // person data) on logout so the next account on a shared device starts
      // clean. Both are guarded — analytics must never break auth.
      final user = next.valueOrNull;
      if (nowLoggedIn && user != null) {
        _identifyPostHog(user);
        ErrorReporter.setUser(user.uid);
      } else if (wasLoggedIn && !nowLoggedIn) {
        ErrorReporter.setUser(null);
        resetPosthogIdentityCache();
        try {
          Posthog().reset();
        } catch (_) {}
      }
    })
    ..listen(onboardingDoneProvider, (_, __) => refresh.value++)
    ..listen(authReloadTickProvider, (_, __) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    // A route that fails to match or throws never dead-ends on a blank page:
    // show a clear message with a button back to Home.
    errorBuilder: (context, state) => Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.explore_off_rounded, size: 48),
                const SizedBox(height: 12),
                const Text(
                  "This page couldn't be opened.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Go to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    observers: [
      // Auto-logs a screen_view for each top-level route (splash, onboarding,
      // login, home, …). Feature screens log their own events via
      // AnalyticsService. Safe if Analytics isn't reachable.
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
      // Mirror the same route changes into PostHog as `$screen` events (uses
      // each GoRoute's `name`). Complements the manual openFeature/screen
      // events fanned out by AnalyticsService.
      PosthogObserver(),
      // Screen breadcrumbs for Crashlytics logs + PostHog exception `screen`.
      ErrorReporterRouteObserver(),
    ],
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final loc = state.matchedLocation;

      // Still resolving the auth stream — stay on splash.
      if (auth.isLoading) {
        return loc == '/splash' ? null : '/splash';
      }

      final onboardingDone = ref.read(onboardingDoneProvider);
      if (!onboardingDone) {
        return loc == '/onboarding' ? null : '/onboarding';
      }

      final loggedIn = auth.valueOrNull != null;
      final onAuthRoute = loc == '/login' || loc == '/signup';

      if (!loggedIn) {
        return onAuthRoute ? null : '/login';
      }

      // Email-verification gate for email/password accounts (Google is already
      // verified). Read the live user so a post-reload change is picked up.
      final repo = ref.read(authRepositoryProvider);
      if (repo.isPasswordUser && !repo.isEmailVerified) {
        return loc == '/verify-email' ? null : '/verify-email';
      }

      // Verified/social user: keep them out of entry + verify routes.
      if (onAuthRoute ||
          loc == '/splash' ||
          loc == '/onboarding' ||
          loc == '/verify-email') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
          path: '/splash',
          name: 'Splash',
          builder: (_, __) => const SplashScreen()),
      GoRoute(
          path: '/onboarding',
          name: 'Onboarding',
          builder: (_, __) => const OnboardingScreen()),
      GoRoute(
          path: '/login',
          name: 'Login',
          builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/signup',
          name: 'Signup',
          builder: (_, __) => const SignupScreen()),
      GoRoute(
          path: '/verify-email',
          name: 'Verify email',
          builder: (_, __) => const VerifyEmailScreen()),
      GoRoute(
          path: '/home', name: 'Home', builder: (_, __) => const HomeShell()),
    ],
  );
});

/// Ties PostHog events to the signed-in Firebase user. Guarded + fire-and-forget
/// so an analytics hiccup can never affect auth/navigation.
void _identifyPostHog(User user) {
  try {
    final email = user.email;
    final name = user.displayName;
    final provider = user.providerData.isNotEmpty
        ? user.providerData.first.providerId
        : 'unknown';
    unawaited(Posthog().identify(
      userId: user.uid,
      userProperties: {
        if (email != null && email.isNotEmpty) 'email': email,
        if (name != null && name.isNotEmpty) 'name': name,
        'auth_provider': provider,
        'email_verified': user.emailVerified,
      },
    ));
  } catch (_) {
    // Analytics must never break auth.
  }
}
