import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_settings_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/validators.dart';
import '../../../../services/analytics_service.dart';
import '../../../../shared/widgets/character_avatar.dart';
import '../../../../shared/widgets/progress_ring.dart';
import '../../../../shared/widgets/sweep_shimmer.dart';
import '../../domain/onboarding_profile.dart';
import '../../domain/profile_avatars.dart';
import '../providers/onboarding_draft_provider.dart';
import '../widgets/onboarding_visuals.dart';

/// Personalised first-run onboarding.
///
/// Design principles:
///  • A guide character: the mascot changes expression and *reacts* to every
///    answer in a speech bubble, so it feels like a conversation, not a form.
///  • Tangible outcomes: a student ID card fills in live as you answer; the
///    attendance target becomes a term of dots you can see shrink and grow.
///  • Value before the ask: a short "building your plan" moment, then a
///    personalised home preview + confetti — only then do we ask for sign-up.
///  • One optional question per screen (Skip everywhere), progress bar, system
///    back steps back. Answers are drafted on-device and seeded at sign-up.
///  • Accessible + performant: ≥48dp targets, semantic labels/selected states,
///    every decorative motion is disabled under "reduce motion", backgrounds
///    use gradients (no blur filters) inside RepaintBoundaries.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { welcome, name, focus, target, avatar, building, plan }

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;
  bool _forward = true;
  late final TextEditingController _name;

  /// Question steps shown in the progress indicator.
  static const _questions = [_Step.name, _Step.focus, _Step.target, _Step.avatar];

  static const Map<_Step, Color> _accent = {
    _Step.welcome: AppColors.primary,
    _Step.name: AppColors.primary,
    _Step.focus: AppColors.coral,
    _Step.target: AppColors.success,
    _Step.avatar: AppColors.accent,
    _Step.building: AppColors.info,
    _Step.plan: AppColors.primary,
  };

  @override
  void initState() {
    super.initState();
    // Eager (not lazy) so dispose() never has to touch `ref`.
    _name = TextEditingController(text: ref.read(onboardingDraftProvider).name);
  }

  bool _precached = false;

  /// Decode every image the flow will show up front, so mascot expression
  /// changes and the avatar grid never stall a frame decoding on first use.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    for (final pose in MascotPose.values) {
      for (final size in const [84.0, 130.0, 170.0]) {
        precacheImage(
          ResizeImage(AssetImage(pose.asset), width: (size * dpr).round()),
          context,
        );
      }
    }
    for (final file in ProfileAvatars.free) {
      precacheImage(AssetImage('${ProfileAvatars.assetDir}/$file'), context);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _go(_Step next) {
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    setState(() {
      _forward = next.index > _step.index;
      _step = next;
    });
    ref.read(analyticsProvider).log('onboarding_step', {'step': next.name});
  }

  void _next() => _go(_Step.values[_step.index + 1]);

  void _back() {
    // The "building" moment is one-way: going back from the plan skips it.
    final target = _step == _Step.plan ? _Step.avatar : _Step.values[_step.index - 1];
    if (_step.index > 0) _go(target);
  }

  /// Called by the name step once its input is valid (or empty = skipped).
  void _saveName() {
    ref.read(onboardingDraftProvider.notifier).update((p) => p.copyWith(name: _name.text));
    _next();
  }

  /// Marks onboarding as done and hands off to sign-up / sign-in. Must complete
  /// first: the router bounces any auth route back here until it's done.
  Future<void> _finish({required bool hasAccount}) async {
    final draft = ref.read(onboardingDraftProvider);
    ref.read(analyticsProvider).log('onboarding_completed', {
      'has_account': hasAccount ? 1 : 0,
      'gave_name': draft.hasName ? 1 : 0,
      'focus_count': draft.focusAreas.length,
      'target': draft.targetAttendance,
      'picked_avatar': draft.avatarCharacter != null ? 1 : 0,
    });
    await ref.read(onboardingDraftProvider.notifier).flush();
    await ref.read(onboardingDoneProvider.notifier).complete();
    if (mounted) context.go(hasAccount ? '/login' : '/signup');
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider);
    final motion = motionOn(context);
    final qIndex = _questions.indexOf(_step);
    final notifier = ref.read(onboardingDraftProvider.notifier);

    final Widget body = switch (_step) {
      _Step.welcome => _WelcomeStep(onStart: _next, onHaveAccount: () => _finish(hasAccount: true)),
      _Step.name => _NameStep(controller: _name, onContinue: _saveName),
      _Step.focus => _FocusStep(draft: draft, onToggle: notifier.toggleFocus, onContinue: _next),
      _Step.target => _TargetStep(
          draft: draft,
          onChanged: (v) => notifier.update((p) => p.copyWith(targetAttendance: v)),
          onContinue: _next,
        ),
      _Step.avatar => _AvatarStep(
          draft: draft,
          onPick: (c) => notifier.update((p) => p.copyWith(avatarCharacter: c)),
          onContinue: _next,
        ),
      _Step.building => _BuildingStep(draft: draft, onDone: _next),
      _Step.plan => _PlanStep(
          draft: draft,
          onCreate: () => _finish(hasAccount: false),
          onHaveAccount: () => _finish(hasAccount: true),
        ),
    };

    return PopScope(
      // System back walks back through the steps instead of closing the app.
      canPop: _step == _Step.welcome,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step != _Step.building) _back();
      },
      child: Scaffold(
        body: OnboardingBackdrop(
          accent: _accent[_step]!,
          child: SafeArea(
            child: Column(
              children: [
                _TopBar(
                  showBack: _step != _Step.welcome && _step != _Step.building,
                  onBack: _back,
                  progress: qIndex,
                  total: _questions.length,
                  onSkip: qIndex >= 0 ? _next : null,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: motion ? const Duration(milliseconds: 360) : Duration.zero,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) {
                      final dx = _forward ? 0.10 : -0.10;
                      final incoming = child.key == ValueKey(_step);
                      return FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(begin: Offset(incoming ? dx : -dx, 0), end: Offset.zero).animate(anim),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(key: ValueKey(_step), child: body),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared building blocks ────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.showBack,
    required this.onBack,
    required this.progress,
    required this.total,
    required this.onSkip,
  });

  final bool showBack;
  final VoidCallback onBack;

  /// Index of the current question, or -1 when not on a question step.
  final int progress;
  final int total;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: showBack
                ? IconButton(tooltip: 'Back', onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded))
                : null,
          ),
          Expanded(
            child: progress < 0
                ? const SizedBox.shrink()
                : Semantics(
                    label: 'Step ${progress + 1} of $total',
                    child: ExcludeSemantics(
                      child: Row(
                        children: List.generate(total, (i) {
                          return Expanded(
                            child: Container(
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              alignment: Alignment.centerLeft,
                              // Segments fill left-to-right like a story bar.
                              child: AnimatedFractionallySizedBox(
                                duration: const Duration(milliseconds: 450),
                                curve: Curves.easeOutCubic,
                                widthFactor: i <= progress ? 1 : 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [scheme.primary, AppColors.primaryLight]),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
          ),
          SizedBox(
            width: 72,
            child: onSkip == null ? null : TextButton(onPressed: onSkip, child: const Text('Skip')),
          ),
        ],
      ),
    );
  }
}

/// Primary CTA with press-scale feedback.
class _Cta extends StatelessWidget {
  const _Cta({required this.label, required this.onPressed, this.icon, this.shimmer = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    Widget button = ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(label, key: ValueKey(label), overflow: TextOverflow.ellipsis),
            ),
          ),
          if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: 20)],
        ],
      ),
    );
    if (shimmer && motionOn(context)) {
      // Mask exists only during each sweep (vs. a permanent ShaderMask).
      button = SweepShimmer(
        delay: const Duration(milliseconds: 1400),
        every: const Duration(seconds: 5),
        color: Colors.white.withValues(alpha: 0.45),
        child: button,
      );
    }
    return PressScale(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: onPressed == null
              ? null
              : [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: SizedBox(width: double.infinity, child: button),
      ),
    );
  }
}

/// Standard step layout: mascot reaction, question, content, pinned CTA.
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.pose,
    required this.reaction,
    required this.title,
    this.subtitle,
    required this.child,
    required this.cta,
    this.secondary,
  });

  final MascotPose pose;
  final String reaction;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget cta;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MascotGuide(pose: pose, message: reaction).enter(context),
                const SizedBox(height: 20),
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.headlineMedium),
                ).enter(context, delayMs: 80),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyLarge?.copyWith(color: theme.textTheme.bodySmall?.color, height: 1.45),
                  ).enter(context, delayMs: 140),
                ],
                const SizedBox(height: 22),
                child,
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [cta, if (secondary != null) ...[const SizedBox(height: 4), secondary!]],
          ),
        ),
      ],
    );
  }
}

// ─── Step 0: welcome ───────────────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onStart, required this.onHaveAccount});

  final VoidCallback onStart;
  final VoidCallback onHaveAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                const WelcomeHero(),
                const SizedBox(height: 28),
                Semantics(
                  header: true,
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Your semester,\n'),
                      TextSpan(text: 'sorted.', style: TextStyle(color: theme.colorScheme.primary)),
                    ]),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(fontSize: 36, height: 1.1),
                  ),
                ).enter(context, delayMs: 200),
                const SizedBox(height: 14),
                Text(
                  'Attendance, classes, deadlines and grades in one calm place — '
                  'set up around you in 4 quick taps.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.textTheme.bodySmall?.color, height: 1.45),
                ).enter(context, delayMs: 300),
                const SizedBox(height: 18),
                const Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(icon: Icons.timer_outlined, label: '30 seconds'),
                    _Pill(icon: Icons.lock_outline_rounded, label: 'Private by default'),
                    _Pill(icon: Icons.favorite_border_rounded, label: 'Free to start'),
                  ],
                ).enter(context, delayMs: 380),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            children: [
              _Cta(label: 'Personalise my app', icon: Icons.arrow_forward_rounded, onPressed: onStart, shimmer: true)
                  .enter(context, delayMs: 460),
              const SizedBox(height: 4),
              TextButton(onPressed: onHaveAccount, child: const Text('I already have an account')),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: (theme.cardTheme.color ?? theme.colorScheme.surface).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.10)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelMedium),
      ]),
    );
  }
}

// ─── Step 1: name ──────────────────────────────────────────────────────────

class _NameStep extends StatefulWidget {
  const _NameStep({required this.controller, required this.onContinue});

  final TextEditingController controller;
  final VoidCallback onContinue;

  @override
  State<_NameStep> createState() => _NameStepState();
}

class _NameStepState extends State<_NameStep> {
  String? _error;

  void _submit() {
    final text = widget.controller.text;
    final err = text.trim().isEmpty ? null : Validators.name(text);
    setState(() => _error = err);
    if (err == null) widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final clean = Validators.sanitizeName(widget.controller.text);
    final first = clean.split(' ').first;
    return _StepScaffold(
      pose: first.isEmpty ? MascotPose.talk : MascotPose.wave,
      reaction: first.isEmpty ? 'Hey! I’m your study sidekick.' : 'Hi $first! Love that name.',
      title: 'What should we call you?',
      subtitle: 'It goes on your student card. Change it any time.',
      cta: _Cta(
        label: first.isEmpty ? 'Continue' : 'That’s me, $first',
        icon: Icons.arrow_forward_rounded,
        onPressed: _submit,
      ),
      child: Column(
        children: [
          StudentIdCard(name: clean).pop(context, delayMs: 120),
          const SizedBox(height: 22),
          TextField(
            controller: widget.controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.givenName],
            maxLength: 60,
            style: Theme.of(context).textTheme.titleLarge,
            decoration: InputDecoration(
              labelText: 'Your name',
              hintText: 'e.g. Priya',
              counterText: '',
              errorText: _error,
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ).enter(context, delayMs: 220),
        ],
      ),
    );
  }
}

// ─── Step 2: focus areas ───────────────────────────────────────────────────

class _FocusMeta {
  const _FocusMeta(this.icon, this.label, this.hint, this.color);
  final IconData icon;
  final String label;
  final String hint;
  final Color color;
}

const Map<FocusArea, _FocusMeta> _focusMeta = {
  FocusArea.attendance: _FocusMeta(Icons.fact_check_rounded, 'Attendance', 'Stay above the cut-off', AppColors.primary),
  FocusArea.classes: _FocusMeta(Icons.calendar_month_rounded, 'Timetable', 'Know where to be', AppColors.info),
  FocusArea.deadlines: _FocusMeta(Icons.task_alt_rounded, 'Deadlines', 'Never miss a submission', AppColors.coral),
  FocusArea.grades: _FocusMeta(Icons.insights_rounded, 'Grades & GPA', 'See where you stand', AppColors.success),
  FocusArea.budget: _FocusMeta(Icons.account_balance_wallet_rounded, 'Budget', 'Make money last the month', AppColors.accent),
  FocusArea.habits: _FocusMeta(Icons.local_fire_department_rounded, 'Habits & focus', 'Build study streaks', Color(0xFFEC4899)),
};

class _FocusStep extends StatelessWidget {
  const _FocusStep({required this.draft, required this.onToggle, required this.onContinue});

  final OnboardingProfile draft;
  final ValueChanged<FocusArea> onToggle;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final count = draft.focusAreas.length;
    final name = draft.hasName ? ', ${draft.firstName}' : '';
    final reaction = switch (count) {
      0 => 'Hmm… what’s on your plate$name?',
      1 || 2 => 'Nice — noted!',
      _ => 'Ambitious! I’ve got you.',
    };
    return _StepScaffold(
      pose: count == 0 ? MascotPose.think : MascotPose.excited,
      reaction: reaction,
      title: 'What do you want help with?',
      subtitle: 'Pick as many as you like — they go front and centre.',
      cta: _Cta(
        label: count == 0 ? 'Continue' : 'Continue with $count',
        icon: Icons.arrow_forward_rounded,
        onPressed: onContinue,
      ),
      child: LayoutBuilder(builder: (context, c) {
        const gap = 12.0;
        final w = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (i, area) in FocusArea.values.indexed)
              SizedBox(
                width: w,
                child: _FocusCard(
                  meta: _focusMeta[area]!,
                  selected: draft.focusAreas.contains(area),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onToggle(area);
                  },
                ).pop(context, delayMs: 160 + 60 * i),
              ),
          ],
        );
      }),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({required this.meta, required this.selected, required this.onTap});

  final _FocusMeta meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final motion = motionOn(context);
    Widget icon = Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(colors: [meta.color.withValues(alpha: 0.85), meta.color])
            : null,
        color: selected ? null : meta.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(meta.icon, color: selected ? Colors.white : meta.color, size: 22),
    );
    if (selected && motion) {
      // Little celebratory wiggle each time it's selected.
      icon = icon.animate(key: const ValueKey('sel')).rotate(begin: -0.04, end: 0, duration: 400.ms, curve: Curves.elasticOut).scaleXY(begin: 1.25, end: 1, duration: 400.ms, curve: Curves.easeOutBack);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: '${meta.label}. ${meta.hint}',
      excludeSemantics: true,
      child: PressScale(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? Color.alphaBlend(meta.color.withValues(alpha: 0.10), theme.cardTheme.color ?? Colors.white) : theme.cardTheme.color,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? meta.color : theme.dividerColor.withValues(alpha: 0.25), width: selected ? 2 : 1),
            boxShadow: selected
                ? [BoxShadow(color: meta.color.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))]
                : AppColors.softShadow(opacity: 0.05, blur: 14),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 124),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        icon,
                        const Spacer(),
                        AnimatedScale(
                          scale: selected ? 1 : 0,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          child: Icon(Icons.check_circle_rounded, color: meta.color, size: 22),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Text(meta.label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(meta.hint, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Step 3: attendance target ─────────────────────────────────────────────

class _TargetStep extends StatelessWidget {
  const _TargetStep({required this.draft, required this.onChanged, required this.onContinue});

  final OnboardingProfile draft;
  final ValueChanged<int> onChanged;
  final VoidCallback onContinue;

  /// A typical term, used only to make the percentage tangible.
  static const _termClasses = 40;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = draft.targetAttendance;
    final skippable = AttendanceMath.maxSkippable(_termClasses, t);
    final (pose, reaction) = switch (t) {
      >= 85 => (MascotPose.think, 'High bar! I’ll watch it closely.'),
      <= 65 => (MascotPose.excited, 'A little breathing room — nice.'),
      _ => (MascotPose.talk, '$t% — the classic. Got it.'),
    };
    return _StepScaffold(
      pose: pose,
      reaction: reaction,
      title: 'What attendance do you need?',
      subtitle: 'Most colleges ask for 75%. We’ll warn you before you slip below it.',
      cta: _Cta(label: 'Set $t% as my target', icon: Icons.flag_rounded, onPressed: onContinue),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 14),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(28),
          boxShadow: AppColors.softShadow(opacity: 0.07),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Ring springs from the old value to the new one.
                TweenAnimationBuilder<double>(
                  tween: Tween(end: t.toDouble()),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutBack,
                  builder: (_, v, __) => ProgressRing(
                    percent: v,
                    size: 110,
                    strokeWidth: 12,
                    color: AppColors.success,
                    subLabel: 'target',
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('You can miss up to', style: theme.textTheme.bodySmall),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: Text(
                          '$skippable',
                          key: ValueKey(skippable),
                          style: theme.textTheme.displaySmall?.copyWith(color: AppColors.coral, fontSize: 44),
                        ),
                      ),
                      Text('of $_termClasses classes this term', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Semantics(
              label: 'In a $_termClasses-class term you can miss up to $skippable ${skippable == 1 ? 'class' : 'classes'}.',
              child: AttendanceDots(total: _termClasses, skippable: skippable),
            ),
            const SizedBox(height: 10),
            Row(children: [
              _Legend(color: theme.colorScheme.primary, label: 'Attend'),
              const SizedBox(width: 14),
              const _Legend(color: AppColors.coral, label: 'Safe to skip'),
            ]),
            const SizedBox(height: 8),
            Slider(
              value: t.toDouble(),
              min: OnboardingProfile.minTarget.toDouble(),
              max: OnboardingProfile.maxTarget.toDouble(),
              divisions: (OnboardingProfile.maxTarget - OnboardingProfile.minTarget) ~/ 5,
              label: '$t%',
              semanticFormatterCallback: (v) => '${v.round()} percent target',
              onChanged: (v) {
                if (v.round() != t) HapticFeedback.selectionClick();
                onChanged(v.round());
              },
            ),
            Wrap(
              spacing: 8,
              children: [
                for (final preset in const [65, 75, 85])
                  ChoiceChip(
                    label: Text('$preset%'),
                    selected: t == preset,
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      onChanged(preset);
                    },
                  ),
              ],
            ),
          ],
        ),
      ).pop(context, delayMs: 160),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ]);
}

// ─── Step 4: avatar ────────────────────────────────────────────────────────

class _AvatarStep extends StatelessWidget {
  const _AvatarStep({required this.draft, required this.onPick, required this.onContinue});

  final OnboardingProfile draft;
  final ValueChanged<String> onPick;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final chosen = draft.avatarCharacter;
    return _StepScaffold(
      pose: chosen == null ? MascotPose.talk : MascotPose.excited,
      reaction: chosen == null ? 'Pick a buddy — let’s match vibes.' : 'Ooh, great choice!',
      title: 'Pick your sidekick',
      subtitle: 'This is how you’ll show up in ClassTrack. More unlock with Pro.',
      cta: _Cta(
        label: chosen == null ? 'Surprise me' : 'Looks good',
        icon: chosen == null ? Icons.casino_rounded : Icons.arrow_forward_rounded,
        onPressed: onContinue,
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              StudentIdCard(name: draft.name, avatarCharacter: chosen, targetAttendance: draft.targetAttendance),
              Positioned(left: 20, bottom: -30, child: SparkleBurst(trigger: chosen, radius: 60)),
            ],
          ).pop(context, delayMs: 100),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 5,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (i, file) in ProfileAvatars.free.indexed)
                _AvatarOption(
                  file: file,
                  selected: file == chosen,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onPick(file);
                  },
                ).pop(context, delayMs: 180 + 25 * i),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvatarOption extends StatelessWidget {
  const _AvatarOption({required this.file, required this.selected, required this.onTap});

  final String file;
  final bool selected;
  final VoidCallback onTap;

  /// "icons8-spider-man-head-144.png" → "Spider man head" for screen readers.
  /// Variants ("…-144-2.png") get a number so labels stay unique.
  static String _label(String f) {
    final variant = RegExp(r'-144-(\d+)').firstMatch(f)?.group(1);
    final core = f.replaceFirst('icons8-', '').replaceAll(RegExp(r'-144.*$'), '').replaceAll('-', ' ');
    final base = core.isEmpty ? 'Character' : core[0].toUpperCase() + core.substring(1);
    return variant == null ? base : '$base $variant';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: _label(file),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedScale(
          scale: selected ? 1.12 : 1,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2.5),
              boxShadow: selected
                  ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))]
                  : null,
            ),
            child: LayoutBuilder(
              // Fill the grid cell (minus ring) so narrow phones never clip.
              builder: (context, c) => CharacterAvatar(
                uid: 'onboarding',
                character: file,
                size: c.biggest.shortestSide,
                backgroundColor: scheme.primary.withValues(alpha: selected ? 0.16 : 0.07),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Step 5: building the plan (labour illusion) ───────────────────────────

class _BuildingStep extends StatefulWidget {
  const _BuildingStep({required this.draft, required this.onDone});

  final OnboardingProfile draft;
  final VoidCallback onDone;

  @override
  State<_BuildingStep> createState() => _BuildingStepState();
}

class _BuildingStepState extends State<_BuildingStep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Long enough to read; short enough not to feel like a fake wait.
    _c.duration = Duration(milliseconds: motionOn(context) ? 2600 : 700);
    _c.forward().whenComplete(() {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  List<(IconData, String)> get _items {
    final d = widget.draft;
    final focus = d.focusAreas.isEmpty
        ? 'your classes and deadlines'
        : FocusArea.values.where(d.focusAreas.contains).take(2).map((f) => _focusMeta[f]!.label.toLowerCase()).join(' & ');
    return [
      (Icons.flag_rounded, 'Setting your ${d.targetAttendance}% attendance goal'),
      (Icons.notifications_active_rounded, 'Tuning reminders for $focus'),
      (Icons.dashboard_customize_rounded, d.hasName ? 'Arranging your home, ${d.firstName}' : 'Arranging your home screen'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    return Semantics(
      liveRegion: true,
      label: 'Building your plan',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = Curves.easeInOutCubic.transform(_c.value);
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: Stack(alignment: Alignment.center, children: [
                    ProgressRing(percent: v * 100, size: 200, strokeWidth: 10, color: theme.colorScheme.primary, centerLabel: ''),
                    const Mascot(pose: MascotPose.talk, size: 130),
                  ]),
                ),
                const SizedBox(height: 28),
                Text('Building your plan…', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 22),
                for (final (i, (icon, label)) in items.indexed)
                  _BuildRow(icon: icon, label: label, done: v >= (i + 1) / (items.length + 0.6)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BuildRow extends StatelessWidget {
  const _BuildRow({required this.icon, required this.label, required this.done});
  final IconData icon;
  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: done ? 1 : 0.45,
        child: Row(children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: c),
            child: done
                ? const Icon(Icons.check_circle_rounded, key: ValueKey(true), color: AppColors.success, size: 24)
                : SizedBox(
                    key: const ValueKey(false),
                    width: 24,
                    height: 24,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(icon, size: 18, color: theme.colorScheme.primary),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        ]),
      ),
    );
  }
}

// ─── Step 6: personalised plan ─────────────────────────────────────────────

class _PlanStep extends StatefulWidget {
  const _PlanStep({required this.draft, required this.onCreate, required this.onHaveAccount});

  final OnboardingProfile draft;
  final VoidCallback onCreate;
  final VoidCallback onHaveAccount;

  /// What each focus area turns into inside the app.
  static String promise(FocusArea a, int target) => switch (a) {
        FocusArea.attendance => 'Attendance alerts before you dip below $target%',
        FocusArea.classes => 'Your timetable from a photo or Google Calendar in seconds',
        FocusArea.deadlines => 'Reminders ahead of every task and exam',
        FocusArea.grades => 'A live GPA so you always know where you stand',
        FocusArea.budget => 'A monthly budget that keeps spending on track',
        FocusArea.habits => 'Study streaks and a built-in focus timer',
      };

  @override
  State<_PlanStep> createState() => _PlanStepState();
}

class _PlanStepState extends State<_PlanStep> {
  final _confetti = ConfettiController(duration: const Duration(milliseconds: 900));
  bool _fired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_fired && motionOn(context)) {
      _fired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _confetti.play();
      });
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final theme = Theme.of(context);
    // Nothing picked → show the three things most students come for.
    final areas = draft.focusAreas.isEmpty
        ? const [FocusArea.attendance, FocusArea.classes, FocusArea.deadlines]
        : FocusArea.values.where(draft.focusAreas.contains).toList();

    return Stack(
      alignment: Alignment.topCenter,
      children: [
        _StepScaffold(
          pose: MascotPose.celebrate,
          reaction: draft.hasName ? 'Woohoo! Ready when you are, ${draft.firstName}.' : 'Woohoo! You’re ready.',
          title: draft.hasName ? 'You’re all set, ${draft.firstName}.' : 'You’re all set.',
          subtitle: 'Here’s a peek at your ClassTrack:',
          cta: _Cta(label: 'Create my free account', icon: Icons.rocket_launch_rounded, onPressed: widget.onCreate, shimmer: true),
          secondary: TextButton(onPressed: widget.onHaveAccount, child: const Text('I already have an account')),
          child: Column(
            children: [
              _HomePreview(draft: draft).pop(context, delayMs: 120),
              const SizedBox(height: 16),
              for (final (i, a) in areas.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PromiseRow(meta: _focusMeta[a]!, text: _PlanStep.promise(a, draft.targetAttendance))
                      .enter(context, delayMs: 260 + 90 * i, dy: 0.3),
                ),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: theme.textTheme.bodySmall?.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Your answers stay on this device until you create your account.', style: theme.textTheme.bodySmall),
                ),
              ]),
            ],
          ),
        ),
        IgnorePointer(
          child: ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            emissionFrequency: 0.0,
            numberOfParticles: 36,
            maxBlastForce: 28,
            minBlastForce: 10,
            gravity: 0.22,
            colors: const [AppColors.accent, AppColors.coral, AppColors.primaryLight, AppColors.success, AppColors.info],
          ),
        ),
      ],
    );
  }
}

/// A mini mock of the student's future home screen, built from their answers.
class _HomePreview extends StatelessWidget {
  const _HomePreview({required this.draft});
  final OnboardingProfile draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greet = greetingFor(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.ink, AppColors.inkSoft],
        ),
        boxShadow: [BoxShadow(color: AppColors.ink.withValues(alpha: 0.30), blurRadius: 26, offset: const Offset(0, 14))],
      ),
      child: Column(
        children: [
          Row(children: [
            CharacterAvatar(
              uid: draft.name.isEmpty ? 'onboarding' : draft.name,
              character: draft.avatarCharacter,
              fallbackText: draft.name,
              size: 48,
              backgroundColor: Colors.white.withValues(alpha: 0.14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(greet, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60)),
                Text(draft.hasName ? draft.firstName : 'Student',
                    style: theme.textTheme.titleLarge?.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: const Icon(Icons.notifications_none_rounded, color: Colors.white70, size: 20),
            ),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            AnimatedProgressRing(
              percent: draft.targetAttendance.toDouble(),
              size: 84,
              strokeWidth: 9,
              color: AppColors.success,
              subLabel: 'goal',
              duration: const Duration(milliseconds: 1200),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Attendance goal', style: theme.textTheme.labelMedium?.copyWith(color: Colors.white60)),
                const SizedBox(height: 2),
                Text('Stay at ${draft.targetAttendance}%+',
                    style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                  child: Text('We’ll nudge you early',
                      style: theme.textTheme.labelMedium?.copyWith(color: const Color(0xFF86EFAC))),
                ),
              ]),
            ),
          ]),
        ],
      ),
    );
  }
}

class _PromiseRow extends StatelessWidget {
  const _PromiseRow({required this.meta, required this.text});
  final _FocusMeta meta;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppColors.softShadow(opacity: 0.05, blur: 16),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: meta.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
          child: Icon(meta.icon, color: meta.color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        const Icon(Icons.check_rounded, color: AppColors.success, size: 20),
      ]),
    );
  }
}
