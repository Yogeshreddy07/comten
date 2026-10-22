import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/push_notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/theme_view_model.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/user_role.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/files_screen.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../../activities/viewmodel/activity_view_model.dart';
import '../../approvals/viewmodel/approval_view_model.dart';
import '../../attendance/viewmodel/attendance_team_view_model.dart';
import '../../attendance/viewmodel/attendance_view_model.dart';
import '../../auth/view/welcome_screen.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../../billing/viewmodel/billing_approval_view_model.dart';
import '../../billing/viewmodel/billing_view_model.dart';
import '../../employees/viewmodel/employee_view_model.dart';
import '../../modules/viewmodel/module_view_model.dart';
import '../../notifications/viewmodel/notification_view_model.dart';
import '../../projects/viewmodel/project_view_model.dart';
import '../../worklogs/viewmodel/work_log_approval_view_model.dart';
import '../../worklogs/viewmodel/work_log_view_model.dart';
import '../model/user_settings.dart';
import '../viewmodel/settings_view_model.dart';
import 'change_password_screen.dart';
import 'change_pin_screen.dart';

/// Settings - shared across every role. Account/Security actions delegate to
/// [SettingsViewModel] (password/PIN/logout, all `/api/auth/**`) except the
/// biometric toggle, which stays on [AuthViewModel] since that already owns
/// the device-hardware check and secure-storage sync.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isTogglingBiometric = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SettingsViewModel>().fetchSettings();
    });
  }

  Future<void> _toggleBiometric(bool enable) async {
    if (_isTogglingBiometric) return;
    _isTogglingBiometric = true;

    final authViewModel = context.read<AuthViewModel>();

    final result = enable
        ? await authViewModel.enableAppLockBiometric()
        : await authViewModel.disableAppLockBiometric();

    if (!mounted) return;
    _isTogglingBiometric = false;
    if (result.success) {
      SnackbarUtil.showSuccess(context, result.message);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  Future<void> _confirmLogout() async {
    if (!context.canPushRoute) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(AppStrings.settingsLogoutConfirmTitle),
        content: const Text(AppStrings.settingsLogoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text(AppStrings.settingsLogout),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final authViewModel = context.read<AuthViewModel>();
    final settingsViewModel = context.read<SettingsViewModel>();
    final employeeCode = authViewModel.employeeCode;

    if (employeeCode.isNotEmpty) {
      await PushNotificationService.instance.unregister(employeeCode);
    }
    await settingsViewModel.logout();
    await authViewModel.clearActiveUser();

    if (!mounted) return;
    context.read<ProjectViewModel>().reset();
    context.read<ModuleViewModel>().reset();
    context.read<EmployeeViewModel>().reset();
    context.read<WorkLogViewModel>().reset();
    context.read<WorkLogApprovalViewModel>().reset();
    context.read<AttendanceViewModel>().reset();
    context.read<AttendanceTeamViewModel>().reset();
    context.read<BillingViewModel>().reset();
    context.read<BillingApprovalViewModel>().reset();
    context.read<ActivityViewModel>().reset();
    context.read<ApprovalViewModel>().reset();
    context.read<NotificationViewModel>().reset();
    settingsViewModel.reset();

    SnackbarUtil.showSuccess(context, AppStrings.settingsLogoutSuccess);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _openStaticInfo(String title, String body) {
    if (!context.canPushRoute) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _StaticInfoScreen(title: title, body: body)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsViewModel = context.watch<SettingsViewModel>();
    final authViewModel = context.watch<AuthViewModel>();
    final themeViewModel = context.watch<ThemeViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.settingsTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _buildBody(context, settingsViewModel, authViewModel, themeViewModel),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SettingsViewModel settingsViewModel,
    AuthViewModel authViewModel,
    ThemeViewModel themeViewModel,
  ) {
    switch (settingsViewModel.loadState) {
      case SettingsLoadState.initial:
      case SettingsLoadState.loading:
        return const AppLoader(message: AppStrings.settingsLoading);

      case SettingsLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.settingsLoadErrorTitle,
          message: settingsViewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => settingsViewModel.fetchSettings(),
        );

      case SettingsLoadState.success:
        final settings = settingsViewModel.settings;
        return RefreshIndicator(
          onRefresh: settingsViewModel.fetchSettings,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (settings != null) _ProfileHeader(settings: settings),
              const SizedBox(height: AppDimensions.sectionSpacing),

              const _SectionLabel(AppStrings.settingsSectionAccount),
              const SizedBox(height: 8),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (settings != null) _SettingsRow(
                      icon: Icons.attach_file,
                      title: 'My attachments',
                      subtitle: 'Documents and profile images',
                      onTap: () {
                        if (!context.canPushRoute) return;
                        Navigator.push(context, MaterialPageRoute(builder: (_) => FilesScreen(
                          targetId: settings.userId,
                          categories: const {'employee_document':'Documents','profile_image':'Profile images'},
                        )));
                      },
                    ),
                    _SettingsRow(
                      icon: Icons.lock_outline,
                      title: AppStrings.settingsChangePassword,
                      subtitle: AppStrings.settingsChangePasswordSubtitle,
                      onTap: () {
                        if (!context.canPushRoute) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ChangePasswordScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.sectionSpacing),
              const _SectionLabel(AppStrings.settingsSectionSecurity),
              const SizedBox(height: 8),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.fingerprint),
                      title: const Text(AppStrings.settingsBiometricLogin),
                      subtitle: Text(
                        authViewModel.isBiometricsSupported
                            ? AppStrings.settingsBiometricLoginSubtitle
                            : AppStrings.settingsBiometricUnavailable,
                      ),
                      value: authViewModel.isBiometricEnabled,
                      onChanged: authViewModel.isBiometricsSupported
                          ? (value) => _toggleBiometric(value)
                          : null,
                    ),
                    const Divider(height: 1),
                    // UI reorganization only: Change App PIN moved here from
                    // Account (replacing the App Lock row) - same screen,
                    // validation and flow as before.
                    _SettingsRow(
                      icon: Icons.pin_outlined,
                      title: AppStrings.settingsChangePin,
                      subtitle: AppStrings.settingsChangePinSubtitle,
                      onTap: () {
                        if (!context.canPushRoute) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ChangePinScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.sectionSpacing),
              const _SectionLabel(AppStrings.settingsSectionAppearance),
              const SizedBox(height: 8),
              AppCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  secondary: Icon(
                    themeViewModel.isDark(context)
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                  ),
                  title: const Text(AppStrings.settingsDarkMode),
                  subtitle: Text(
                    themeViewModel.isDark(context)
                        ? AppStrings.settingsDarkModeSubtitleOn
                        : AppStrings.settingsDarkModeSubtitleOff,
                  ),
                  value: themeViewModel.isDark(context),
                  onChanged: (_) => themeViewModel.toggleTheme(context),
                ),
              ),

              const SizedBox(height: AppDimensions.sectionSpacing),
              const _SectionLabel(AppStrings.settingsSectionPrivacy),
              const SizedBox(height: 8),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _SettingsRow(
                      icon: Icons.privacy_tip_outlined,
                      title: AppStrings.settingsPrivacyPolicy,
                      onTap: () => _openStaticInfo(
                        AppStrings.settingsPrivacyPolicy,
                        AppStrings.settingsPrivacyPolicyBody,
                      ),
                    ),
                    const Divider(height: 1),
                    _SettingsRow(
                      icon: Icons.shield_outlined,
                      title: AppStrings.settingsSecurityInformation,
                      onTap: () => _openStaticInfo(
                        AppStrings.settingsSecurityInformation,
                        AppStrings.settingsSecurityInformationBody,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.sectionSpacing),
              AppButton(
                text: AppStrings.settingsLogout,
                icon: Icons.logout,
                outlined: true,
                onPressed: _confirmLogout,
              ),
            ],
          ),
        );
    }
  }
}

class _ProfileHeader extends StatelessWidget {
  final UserSettings settings;

  const _ProfileHeader({required this.settings});

  @override
  Widget build(BuildContext context) {
    final role = UserRoleX.fromBackendValue(settings.role);

    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: AppDimensions.avatarSize / 2,
            backgroundColor: AppColors.moduleEmployees,
            child: Icon(
              Icons.person,
              color: AppColors.darkText,
              size: AppDimensions.avatarSize * 0.55,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.subHeading,
                ),
                const SizedBox(height: 2),
                Text(
                  '${settings.employeeCode} · ${role.displayLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textSecondaryFor(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.textSecondaryFor(context),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: onTap != null
          ? Icon(Icons.chevron_right, color: AppColors.textSecondaryFor(context))
          : null,
      onTap: onTap,
    );
  }
}

class _StaticInfoScreen extends StatelessWidget {
  final String title;
  final String body;

  const _StaticInfoScreen({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.screenPadding),
          child: Text(body, style: AppTextStyles.body),
        ),
      ),
    );
  }
}
