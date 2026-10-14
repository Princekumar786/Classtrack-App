import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/firebase_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/cms_role.dart';
import '../providers/cms_auth_providers.dart';
import 'cms_analytics_screen.dart';
import 'cms_audit_logs_screen.dart';
import 'cms_banners_screen.dart';
import 'cms_campaigns_screen.dart';
import 'cms_categories_screen.dart';
import 'cms_dashboard_screen.dart';
import 'cms_login_screen.dart';
import 'cms_media_screen.dart';
import 'cms_notifications_screen.dart';
import 'cms_reports_screen.dart';
import 'cms_resources_screen.dart';
import 'cms_settings_screen.dart';
import 'cms_users_screen.dart';

/// A CMS navigation section, gated by the current role's permissions.
class CmsSection {
  final String label;
  final IconData icon;
  final bool Function(CmsRole) visibleTo;
  final Widget Function(BuildContext context, CmsRole role) build;
  const CmsSection({
    required this.label,
    required this.icon,
    required this.visibleTo,
    required this.build,
  });
}

/// All CMS sections in nav order. Each builder receives the already-resolved
/// role from the shell (never null here), so action-gating never depends on a
/// re-read of the async role provider inside the screen.
final cmsSections = <CmsSection>[
  CmsSection(
    label: 'Dashboard',
    icon: Icons.space_dashboard_rounded,
    visibleTo: (_) => true,
    build: (_, role) => CmsDashboardScreen(role: role),
  ),
  CmsSection(
    label: 'Resources',
    icon: Icons.inventory_2_rounded,
    visibleTo: (r) => r.canViewContent,
    build: (_, role) => CmsResourcesScreen(role: role),
  ),
  CmsSection(
    label: 'Categories',
    icon: Icons.sell_rounded,
    visibleTo: (r) => r.canEditContent,
    build: (_, __) => const CmsCategoriesScreen(),
  ),
  CmsSection(
    label: 'Media',
    icon: Icons.perm_media_rounded,
    visibleTo: (r) => r.canEditContent || r.canManageMarketing,
    build: (_, __) => const CmsMediaScreen(),
  ),
  CmsSection(
    label: 'Banners',
    icon: Icons.view_carousel_rounded,
    visibleTo: (r) => r.canManageMarketing,
    build: (_, __) => const CmsBannersScreen(),
  ),
  CmsSection(
    label: 'Campaigns',
    icon: Icons.campaign_rounded,
    visibleTo: (r) => r.canManageMarketing,
    build: (_, __) => const CmsCampaignsScreen(),
  ),
  CmsSection(
    label: 'Notifications',
    icon: Icons.notifications_active_rounded,
    visibleTo: (r) => r.canManageMarketing,
    build: (_, __) => const CmsNotificationsScreen(),
  ),
  CmsSection(
    label: 'Analytics',
    icon: Icons.insights_rounded,
    visibleTo: (r) => r.canViewAnalytics,
    build: (_, role) => CmsAnalyticsScreen(role: role),
  ),
  CmsSection(
    label: 'Reports',
    icon: Icons.flag_rounded,
    visibleTo: (r) => r.canModerate,
    build: (_, __) => const CmsReportsScreen(),
  ),
  CmsSection(
    label: 'Users',
    icon: Icons.group_rounded,
    visibleTo: (r) => r.canManageUsers,
    build: (_, role) => CmsUsersScreen(callerRole: role),
  ),
  CmsSection(
    label: 'Audit logs',
    icon: Icons.receipt_long_rounded,
    visibleTo: (r) => r.canViewAuditLogs,
    build: (_, __) => const CmsAuditLogsScreen(),
  ),
  CmsSection(
    label: 'Settings',
    icon: Icons.settings_rounded,
    visibleTo: (r) => r.canEditConfig,
    build: (_, __) => const CmsSettingsScreen(),
  ),
];

/// Root of the authenticated CMS: gates on auth + role, then shows the
/// navigation shell.
class CmsShell extends ConsumerStatefulWidget {
  const CmsShell({super.key});

  @override
  ConsumerState<CmsShell> createState() => _CmsShellState();
}

class _CmsShellState extends ConsumerState<CmsShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);

    return auth.when(
      loading: () => const _Loading(),
      error: (_, __) => const CmsLoginScreen(),
      data: (user) {
        if (user == null) return const CmsLoginScreen();
        final roleAsync = ref.watch(cmsRoleProvider);
        return roleAsync.when(
          loading: () => const _Loading(),
          error: (_, __) => const _NoAccess(),
          data: (role) {
            if (role == null) return const _NoAccess();
            return _buildShell(context, role, user.email ?? '');
          },
        );
      },
    );
  }

  Widget _buildShell(BuildContext context, CmsRole role, String email) {
    final theme = Theme.of(context);
    final sections = cmsSections
        .where((s) => s.visibleTo(role))
        .toList(growable: false);
    if (_index >= sections.length) _index = 0;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.of(context).size.width > 1100,
            minWidth: 72,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.primary],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.dashboard_customize_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            destinations: [
              for (final s in sections)
                NavigationRailDestination(
                  icon: Icon(s.icon),
                  label: Text(s.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _TopBar(email: email, role: role),
                const Divider(height: 1),
                Expanded(
                  child: Container(
                    color: theme.scaffoldBackgroundColor,
                    child: sections[_index].build(context, role),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  final String email;
  final CmsRole role;
  const _TopBar({required this.email, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              role.label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(email, style: theme.textTheme.bodySmall),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () =>
                ref.read(cmsAuthControllerProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Signed in, but the account has no CMS role — deny access with a sign-out.
class _NoAccess extends ConsumerWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_person_rounded,
                size: 56,
                color: AppColors.danger,
              ),
              const SizedBox(height: 16),
              Text('No CMS access', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'This account is signed in but has not been granted a CMS role. '
                'Ask a super admin to grant you access.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
                onPressed: () =>
                    ref.read(cmsAuthControllerProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
