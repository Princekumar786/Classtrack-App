import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/buttons.dart';
import '../auth_errors.dart';
import '../providers/auth_providers.dart';
import '../providers/onboarding_draft_provider.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  // Pre-filled from onboarding so the student never types their name twice.
  late final TextEditingController _name;
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: ref.read(onboardingDraftProvider).name);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authControllerProvider.notifier)
        .signUp(_email.text, _password.text, _name.text);
    if (!ok && mounted) _showError();
  }

  /// Sign up (or sign in) with Google. For OAuth there's no separate "create
  /// account" step — signing in provisions the Firebase user and the profile
  /// document on first use (see AuthRepository.signInWithGoogle).
  Future<void> _google() async {
    final ok =
        await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!ok && mounted) _showError();
  }

  void _showError() {
    final err = ref.read(authControllerProvider).error;
    // Clear any queued/visible snackbars first so a rapid sequence of failed
    // attempts doesn't stack and flash the same message several times.
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(friendlyAuthError(err ?? 'error'))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider).isLoading;
    final theme = Theme.of(context);
    final draft = ref.watch(onboardingDraftProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    draft.hasName
                        ? 'Almost there, ${draft.firstName}'
                        : 'Let’s get you set up',
                    style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                    draft.isEmpty
                        ? 'Create an account to start tracking attendance.'
                        : 'Create an account to save your setup and sync it '
                            'across devices.',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: Validators.name,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                  ),
                  validator: Validators.email,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: Validators.passwordPolicyHint,
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(_obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: Validators.password,
                ),
                const SizedBox(height: 24),
                LoadingButton(
                  label: 'Create account',
                  loading: loading,
                  onPressed: _submit,
                ),
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
                GoogleButton(onPressed: _google, loading: loading),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Already have an account?',
                        style: theme.textTheme.bodyMedium),
                    TextButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Sign in'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
