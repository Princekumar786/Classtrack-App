import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/cms_role.dart';
import '../providers/cms_admin_providers.dart';

/// Admin-only user role management. Assigns/revokes CMS roles via the
/// server-enforced `setUserRole` callable. Every change is recorded in the
/// audit log.
class CmsUsersScreen extends ConsumerStatefulWidget {
  final CmsRole callerRole;
  const CmsUsersScreen({super.key, required this.callerRole});

  @override
  ConsumerState<CmsUsersScreen> createState() => _CmsUsersScreenState();
}

class _CmsUsersScreenState extends ConsumerState<CmsUsersScreen> {
  final _email = TextEditingController();
  CmsRole? _role; // selected new role; null = revoke
  bool _roleTouched = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _role = null;
      _roleTouched = false;
    });
    await ref.read(userLookupControllerProvider.notifier).lookup(email);
  }

  Future<void> _apply(CmsRole caller, UserLookup user) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!CmsRole.canAssign(caller, _role)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('You are not allowed to assign that role.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    final err = await ref
        .read(setUserRoleControllerProvider.notifier)
        .assign(uid: user.uid, roleKey: _role?.key ?? 'none');
    if (!mounted) return;
    if (err == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _role == null
                ? 'Revoked access for ${user.email}'
                : 'Granted ${_role!.label} to ${user.email}',
          ),
        ),
      );
      setState(() => _roleTouched = false);
      // Refresh the shown current role.
      await ref.read(userLookupControllerProvider.notifier).lookup(user.email);
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caller = widget.callerRole;

    if (!caller.canManageUsers) {
      return const Center(
        child: Text('You do not have access to user management.'),
      );
    }

    final lookup = ref.watch(userLookupControllerProvider);
    final busy = ref.watch(setUserRoleControllerProvider).isLoading;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            Text('Users & roles', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Find a user by email, review their role & permissions, then grant '
              'or revoke access. Changes take effect on the user\'s next token '
              'refresh and are recorded in the audit log.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: softCard(context),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      onSubmitted: (_) => _find(),
                      decoration: const InputDecoration(
                        labelText: 'User email',
                        hintText: 'name@example.com',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size(0, 56),
                    ),
                    onPressed: lookup.isLoading ? null : _find,
                    icon: lookup.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search_rounded),
                    label: const Text('Find'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            lookup.when(
              loading: () => const SizedBox.shrink(),
              error: (e, __) => Container(
                padding: const EdgeInsets.all(16),
                decoration: softCard(context),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.danger,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text('$e')),
                  ],
                ),
              ),
              data: (user) => user == null
                  ? const SizedBox.shrink()
                  : _userCard(theme, caller, user, busy),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userCard(
    ThemeData theme,
    CmsRole caller,
    UserLookup user,
    bool busy,
  ) {
    final currentRole = CmsRole.fromClaim(user.roleKey);
    final assignable = CmsRole.values
        .where((r) => CmsRole.canAssign(caller, r))
        .toList();
    // Mirror the server rule: only a super admin may modify an admin/super admin.
    final locked =
        currentRole != null &&
        currentRole.rank >= CmsRole.admin.rank &&
        caller != CmsRole.superAdmin;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: softCard(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  (user.displayName?.isNotEmpty == true
                          ? user.displayName![0]
                          : user.email[0])
                      .toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName ?? user.email,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      user.email,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color:
                      (currentRole == null
                              ? theme.hintColor
                              : AppColors.primary)
                          .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  currentRole?.label ?? 'No access',
                  style: TextStyle(
                    color: currentRole == null
                        ? theme.hintColor
                        : AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Permissions',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          if (currentRole == null)
            Text(
              'No CMS access.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in currentRole.permissionLabels)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          p,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          const Divider(height: 28),
          if (locked)
            Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only a super admin can modify an admin or super admin.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            )
          else ...[
            DropdownButtonFormField<CmsRole?>(
              initialValue: _roleTouched ? _role : null,
              decoration: const InputDecoration(labelText: 'Change role to'),
              items: [
                const DropdownMenuItem<CmsRole?>(
                  value: null,
                  child: Text('Revoke access (none)'),
                ),
                for (final r in assignable)
                  DropdownMenuItem<CmsRole?>(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => setState(() {
                _role = r;
                _roleTouched = true;
              }),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: (!_roleTouched || busy)
                  ? null
                  : () => _apply(caller, user),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_user_rounded),
              label: Text(
                _roleTouched && _role == null ? 'Revoke access' : 'Apply role',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
