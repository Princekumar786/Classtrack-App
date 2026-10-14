import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons.dart';
import '../../../../shared/widgets/illustrations.dart';
import '../auth_errors.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authControllerProvider.notifier)
        .signIn(_email.text, _password.text);
    if (!ok && mounted) _showError();
  }

  Future<void> _google() async {
    final ok =
        await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!ok && mounted) _showError();
  }

  void _showError() {
    final err = ref.read(authControllerProvider).error;
    if (err == null) return;
    // Clear any queued/visible snackbars first so a rapid sequence of failed
    // attempts doesn't stack and flash the same message several times.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(friendlyAuthError(err))),
      );
  }

  Future<void> _forgotPassword() async {
    if (_email.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Enter your email first.')),
        );
      return;
    }
    final ok = await ref
        .read(authControllerProvider.notifier)
        .resetPassword(_email.text);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'Password reset email sent. Not in your inbox? Check Spam or Junk.'
                : friendlyAuthError(ref.read(authControllerProvider).error!)),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider).isLoading;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Animated illustrated header.
                  const AuthIllustration()
                      .animate()
                      .fadeIn(duration: 400.ms),
                  const SizedBox(height: 8),
                  Text('Welcome back',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800))
                      .animate()
                      .fadeIn(delay: 120.ms, duration: 350.ms)
                      .slideY(begin: 0.2, curve: Curves.easeOut),
                  const SizedBox(height: 6),
                  Text('Sign in to keep your attendance on track.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.hintColor))
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 350.ms),
                  const SizedBox(height: 30),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                    validator: Validators.email,
                  )
                      .animate()
                      .fadeIn(delay: 280.ms, duration: 350.ms)
                      .slideY(begin: 0.15, curve: Curves.easeOut),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => loading ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter your password' : null,
                  )
                      .animate()
                      .fadeIn(delay: 340.ms, duration: 350.ms)
                      .slideY(begin: 0.15, curve: Curves.easeOut),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: loading ? null : _forgotPassword,
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  LoadingButton(
                    label: 'Sign in',
                    loading: loading,
                    onPressed: _submit,
                  )
                      .animate()
                      .fadeIn(delay: 420.ms, duration: 350.ms)
                      .slideY(begin: 0.2, curve: Curves.easeOut),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: theme.textTheme.bodySmall),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GoogleButton(onPressed: _google, loading: loading)
                      .animate()
                      .fadeIn(delay: 500.ms, duration: 350.ms),
                  const SizedBox(height: 24),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text("Don't have an account?",
                          style: theme.textTheme.bodyMedium),
                      TextButton(
                        onPressed: () => context.push('/signup'),
                        child: const Text('Sign up'),
                      ),
                    ],
                  ).animate().fadeIn(delay: 560.ms, duration: 350.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
