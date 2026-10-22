import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/services/push_notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/user_role.dart';
import '../../activities/view/activity_list_screen.dart';
import '../../approvals/view/approval_list_screen.dart';
import '../../auth/viewmodel/auth_viewmodel.dart';
import '../../attendance/view/attendance_screen.dart';
import '../../attendance/view/attendance_team_screen.dart';
import '../../attendance/viewmodel/attendance_view_model.dart';
import '../../billing/view/billing_list_screen.dart';
import '../../employees/view/employee_list_screen.dart';
import '../../notifications/view/notification_list_screen.dart';
import '../../notifications/viewmodel/notification_view_model.dart';
import '../../projects/view/project_list_screen.dart';
import '../../projects/view/reason_for_delay_screen.dart';
import '../../projects/view/status_update_screen.dart';
import '../../settings/view/settings_screen.dart';
import '../../worklogs/view/timesheet_approval_list_screen.dart';
import '../../worklogs/view/timesheet_list_screen.dart';
import '../model/dashboard_item.dart';
import '../viewmodel/dashboard_viewmodel.dart';
import 'dashboard_card.dart';

/// The shared dashboard shell reused by every role's dashboard (Captain,
/// Project Controller, Team Leader, Employee). Only the module list and hero
/// banner copy differ per role - the header, grid/list layout, and default
/// module-tap behavior all live here so no role dashboard duplicates this UI.
///
/// Follows the app's Light/Dark theme setting like every other screen -
/// dark mode keeps the original "premium" always-dark look, light mode
/// uses the standard light surfaces/text via the dashboardXxxFor(context)
/// accessors in [AppColors].
class RoleDashboardScaffold extends StatelessWidget {
  final List<DashboardModuleEntry> modules;
  final String heroTitle;
  final String heroSubtitle;

  /// Optional override for module taps. When omitted, tapping
  /// [DashboardModule.projects] opens [ProjectListScreen] (the only real
  /// module screen built so far) and every other module shows a
  /// "coming soon" message - the same fallback the Captain Dashboard used.
  final void Function(BuildContext context, DashboardModuleEntry entry)?
  onModuleTap;

  const RoleDashboardScaffold({
    super.key,
    required this.modules,
    required this.heroTitle,
    required this.heroSubtitle,
    this.onModuleTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DashboardViewModel>(
      create: (_) => DashboardViewModel(),
      child: _RoleDashboardView(
        modules: modules,
        heroTitle: heroTitle,
        heroSubtitle: heroSubtitle,
        onModuleTap: onModuleTap,
      ),
    );
  }
}

class _RoleDashboardView extends StatefulWidget {
  final List<DashboardModuleEntry> modules;
  final String heroTitle;
  final String heroSubtitle;
  final void Function(BuildContext context, DashboardModuleEntry entry)?
  onModuleTap;

  const _RoleDashboardView({
    required this.modules,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.onModuleTap,
  });

  @override
  State<_RoleDashboardView> createState() => _RoleDashboardViewState();
}

class _RoleDashboardViewState extends State<_RoleDashboardView>
    with WidgetsBindingObserver {
  List<DashboardModuleEntry> get modules => widget.modules;
  String get heroTitle => widget.heroTitle;
  String get heroSubtitle => widget.heroSubtitle;
  void Function(BuildContext context, DashboardModuleEntry entry)?
  get onModuleTap => widget.onModuleTap;

  /// Re-checked locally (no network call) on this timer so the checkout
  /// reminder still surfaces if the 9-hour mark is crossed while an
  /// Employee sits continuously on the dashboard, not just at app open/
  /// resume - see [_checkCheckoutReminder].
  static const _checkoutReminderPollInterval = Duration(minutes: 15);

  Timer? _checkoutReminderTimer;
  bool _showingCheckoutReminder = false;

  /// The attendance row (see `Attendance.id`) the reminder has already been
  /// shown for - a new day's check-in is a new row/id, so this naturally
  /// allows exactly one more reminder next time, without re-nagging for the
  /// same still-open checkout.
  int? _reminderShownForAttendanceId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Not re-fetched here: this screen is only ever reached via
      // RoleDashboardNavigator.navigate(), which already just fetched the
      // unread count moments before pushing this route - refetching it
      // again immediately would just repeat the same request.
      final employeeCode = context.read<AuthViewModel>().employeeCode;
      if (employeeCode.isNotEmpty) {
        PushNotificationService.instance.syncToken(employeeCode);
      }
      _checkCheckoutReminder(refetch: true);
    });
    _checkoutReminderTimer = Timer.periodic(
      _checkoutReminderPollInterval,
      (_) => _checkCheckoutReminder(refetch: false),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkoutReminderTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkCheckoutReminder(refetch: true);
    }
  }

  /// Employees only - Team Leaders/Captains/Project Controllers never
  /// personally check in/out (see `_handleModuleTap`'s attendance branch),
  /// so the reminder would never apply to them. [refetch] re-fetches
  /// today's attendance from the server (app open/resume, in case it
  /// changed elsewhere); the periodic in-foreground poll re-checks the
  /// already-fetched state locally instead, since only the current time -
  /// not the attendance record itself - can change between polls.
  Future<void> _checkCheckoutReminder({required bool refetch}) async {
    if (!mounted) return;
    if (context.read<AuthViewModel>().role != UserRole.employee) return;

    final attendanceViewModel = context.read<AttendanceViewModel>();
    if (refetch) {
      await attendanceViewModel.fetchTodayAttendance();
      if (!mounted) return;
    }

    if (!attendanceViewModel.isCheckoutOverdue) return;
    final attendanceId = attendanceViewModel.today?.id;
    if (attendanceId == null || attendanceId == _reminderShownForAttendanceId) {
      return;
    }

    _reminderShownForAttendanceId = attendanceId;
    _showCheckoutReminder();
  }

  Future<void> _showCheckoutReminder() async {
    if (_showingCheckoutReminder || !mounted) return;
    _showingCheckoutReminder = true;

    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.attendanceCheckoutReminderTitle),
        content: const Text(AppStrings.attendanceCheckoutReminderMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(AppStrings.attendanceCheckoutReminderCancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(AppStrings.attendanceCheckoutReminderContinueButton),
          ),
        ],
      ),
    );

    _showingCheckoutReminder = false;
    if (shouldContinue == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AttendanceScreen()),
      );
    }
  }

  void _handleModuleTap(BuildContext context, DashboardModuleEntry entry) {
    if (!context.canPushRoute) return;

    final override = onModuleTap;
    if (override != null) {
      override(context, entry);
      return;
    }
    if (entry.module == DashboardModule.projects) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProjectListScreen()),
      );
      return;
    }
    // Working Hours / Timesheet: only Employees submit and view their own
    // entries; only their project's Team Leader reviews and approves/
    // rejects them - the backend's @PreAuthorize on `/api/work-logs/**`
    // enforces the same split, so each role only ever reaches the screen
    // matching its permissions. Captain / Project Controller don't get a
    // Timesheet tile at all (see dashboard_item.dart).
    if (entry.module == DashboardModule.timesheet) {
      final role = context.read<AuthViewModel>().role;
      final isApprover = role == UserRole.teamLeader;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => isApprover
              ? const TimesheetApprovalListScreen()
              : const TimesheetListScreen(),
        ),
      );
      return;
    }
    // Attendance: Employees check in/out for themselves; Team Leaders view
    // their team's history (scoped server-side to projects they lead, see
    // `AttendanceServiceImpl#getTeamAttendance`). Captain / Project
    // Controller keep the "coming soon" fallback - no attendance screens are
    // required for those roles.
    if (entry.module == DashboardModule.attendance) {
      final role = context.read<AuthViewModel>().role;
      if (role == UserRole.employee) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AttendanceScreen()),
        );
        return;
      }
      if (role == UserRole.teamLeader) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AttendanceTeamScreen()),
        );
        return;
      }
    }
    // Billing Management: Captain / Project Controller only (see
    // dashboard_item.dart - Team Leader and Employee never get this tile),
    // matching the backend's @PreAuthorize on `/api/billing/**`.
    if (entry.module == DashboardModule.billing) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BillingListScreen()),
      );
      return;
    }
    // Activities: Project Controller only (see dashboard_item.dart),
    // matching the backend's @PreAuthorize on `/api/activities/**` - the
    // master list a Project Controller assigns per-project as Billable/
    // Non-Billable in Create/Edit Project.
    if (entry.module == DashboardModule.activities) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ActivityListScreen()),
      );
      return;
    }
    // Approval: Captain only (see dashboard_item.dart), matching the
    // backend's @PreAuthorize on `/api/project-change-requests/**` -
    // Project Controller requests to change a project's End Date/
    // Estimated Hours land here for decision.
    if (entry.module == DashboardModule.approval) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ApprovalListScreen()),
      );
      return;
    }
    // Status Update: Team Lead only (see dashboard_item.dart) - toggles a
    // led project between WIP and Billing, matching the backend's
    // @PreAuthorize on `PUT /api/projects/{id}/work-stage`.
    if (entry.module == DashboardModule.statusUpdate) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StatusUpdateScreen()),
      );
      return;
    }
    // Reason for Delay: Team Lead only (see dashboard_item.dart) - submits
    // a delay reason for a led project, notifying every Project Controller
    // (`NotificationServiceImpl#submitDelayRequest`).
    if (entry.module == DashboardModule.reasonForDelay) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ReasonForDelayScreen()),
      );
      return;
    }
    // Notifications: every role has this tile - the backend scopes the
    // list to the current user/role automatically
    // (`NotificationServiceImpl#getNotifications`), so no role branching is
    // needed here.
    if (entry.module == DashboardModule.notifications) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationListScreen()),
      ).then((_) {
        if (context.mounted) {
          context.read<NotificationViewModel>().fetchUnreadCount();
        }
      });
      return;
    }
    // Employee Management is admin tooling: the backend's @PreAuthorize on
    // /api/employees/** only admits Captains and Project Controllers, so the
    // Team Leader dashboard's "Team Members" relabel of this module keeps its
    // "coming soon" fallback rather than opening a screen that would only 403.
    //
    // Captains see this tile as "Project Controller Management" (see
    // dashboard_item.dart) and only ever manage Project Controller accounts
    // through it - Project Controllers still get the unrestricted staff
    // directory, unchanged.
    final role = context.read<AuthViewModel>().role;
    if (entry.module == DashboardModule.employees) {
      if (role == UserRole.captain) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const EmployeeListScreen(
              roleFilter: UserRole.projectManager,
              title: AppStrings.dashboardModuleProjectControllers,
              addButtonLabel: AppStrings.addProjectControllerButton,
              emptyTitle: AppStrings.projectControllerListEmptyTitle,
              emptyMessage: AppStrings.projectControllerListEmptyMessage,
            ),
          ),
        );
        return;
      }
      if (role == UserRole.projectManager) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EmployeeListScreen()),
        );
        return;
      }
    }
    // Settings: every role has this tile - the screen itself scopes actions
    // to the current authenticated user (see SettingsViewModel).
    if (entry.module == DashboardModule.settings) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
      return;
    }
    SnackbarUtil.showInfo(context, AppStrings.moduleComingSoon(entry.title));
  }

  DashboardModuleEntry _entryFor(DashboardModule module) {
    for (final entry in modules) {
      if (entry.module == module) return entry;
    }
    return DashboardModuleEntry(module);
  }

  int _resolveCrossAxisCount(double width) {
    if (width >= AppDimensions.desktopBreakpoint) return 4;
    if (width >= AppDimensions.tabletBreakpoint) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final dashboardViewModel = context.watch<DashboardViewModel>();
    final authViewModel = context.watch<AuthViewModel>();
    final hasUnreadNotifications =
        context.watch<NotificationViewModel>().unreadCount > 0;

    final gridModules = modules
        .where(
          (entry) =>
              entry.module != DashboardModule.settings &&
              entry.module != DashboardModule.notifications,
        )
        .toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppColors.isDark(context)
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.dashboardBackgroundFor(context),
        body: SafeArea(
          child: Column(
            children: [
              _Header(
                greeting: dashboardViewModel.greeting,
                greetingName: authViewModel.displayName,
                hasUnreadNotifications: hasUnreadNotifications,
                onNotificationTap: () => _handleModuleTap(
                  context,
                  _entryFor(DashboardModule.notifications),
                ),
                onSettingsTap: () => _handleModuleTap(
                  context,
                  _entryFor(DashboardModule.settings),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = _resolveCrossAxisCount(
                      constraints.maxWidth,
                    );

                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppDimensions.screenPadding,
                        0,
                        AppDimensions.screenPadding,
                        AppDimensions.sectionSpacing,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _GradientBanner(
                            title: heroTitle,
                            subtitle: heroSubtitle,
                            illustration: const _BuildingsIllustration(),
                          ),
                          const SizedBox(height: AppDimensions.sectionSpacing),
                          Text(
                            AppStrings.dashboardQuickAccessHeading,
                            style: AppTextStyles.subHeading.copyWith(
                              color: AppColors.dashboardTextFor(context),
                            ),
                          ),
                          const SizedBox(height: AppDimensions.cardSpacing),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: AppDimensions.cardSpacing,
                            mainAxisSpacing: AppDimensions.cardSpacing,
                            childAspectRatio: 0.95,
                            children: [
                              for (final entry in gridModules)
                                DashboardModuleCard(
                                  entry: entry,
                                  onTap: () => _handleModuleTap(context, entry),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppDimensions.sectionSpacing),
                          _GradientBanner(
                            title: AppStrings.dashboardMotivationTitle,
                            subtitle: AppStrings.dashboardMotivationSubtitle,
                            illustration: const _RocketIllustration(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String greeting;
  final String greetingName;
  final bool hasUnreadNotifications;
  final VoidCallback onNotificationTap;
  final VoidCallback onSettingsTap;

  const _Header({
    required this.greeting,
    required this.greetingName,
    required this.hasUnreadNotifications,
    required this.onNotificationTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.headerPadding,
        AppDimensions.headerPadding,
        AppDimensions.headerPadding,
        AppDimensions.sectionSpacing,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.dashboardTextMutedFor(context),
                  ),
                ),
                const SizedBox(height: AppDimensions.greetingNameSpacing),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '$greetingName ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.heading.copyWith(
                          color: AppColors.dashboardTextFor(context),
                          fontSize: 26,
                        ),
                      ),
                    ),
                    const Text('👋', style: TextStyle(fontSize: 22)),
                  ],
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onNotificationTap,
            borderRadius: BorderRadius.circular(
              AppDimensions.notificationBadgeSize / 2,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: AppDimensions.notificationBadgeSize,
                  height: AppDimensions.notificationBadgeSize,
                  decoration: BoxDecoration(
                    color: AppColors.dashboardSurfaceFor(context),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.notifications_outlined,
                    size: AppDimensions.notificationIconSize,
                    color: AppColors.dashboardTextFor(context),
                  ),
                ),
                if (hasUnreadNotifications)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.statusCancelled,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.dashboardSurfaceFor(context),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: onSettingsTap,
            borderRadius: BorderRadius.circular(
              AppDimensions.notificationBadgeSize / 2,
            ),
            child: Container(
              width: AppDimensions.notificationBadgeSize,
              height: AppDimensions.notificationBadgeSize,
              decoration: BoxDecoration(
                color: AppColors.dashboardSurfaceFor(context),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.settings_outlined,
                size: AppDimensions.notificationIconSize,
                color: AppColors.dashboardTextFor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget illustration;

  const _GradientBanner({
    required this.title,
    required this.subtitle,
    required this.illustration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.bannerPadding),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.dashboardGradientStart,
            AppColors.dashboardGradientEnd,
          ],
        ),
        borderRadius: BorderRadius.circular(AppDimensions.bannerRadius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.subHeading.copyWith(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: AppDimensions.bannerTitleSubtitleSpacing,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.dashboardTextMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          illustration,
        ],
      ),
    );
  }
}

/// Approximates the requested isometric-buildings illustration using plain
/// shapes/icons - there's no image asset for real 3D artwork in this project.
class _BuildingsIllustration extends StatelessWidget {
  const _BuildingsIllustration();

  Widget _block(double height, double width) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.darkText.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppDimensions.bannerIllustrationSize,
      height: AppDimensions.bannerIllustrationSize,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            top: 0,
            left: 10,
            child: Icon(
              Icons.star,
              size: 10,
              color: AppColors.darkText.withValues(alpha: 0.7),
            ),
          ),
          Positioned(
            top: 14,
            right: 4,
            child: Icon(
              Icons.star,
              size: 7,
              color: AppColors.darkText.withValues(alpha: 0.5),
            ),
          ),
          Positioned(
            top: 2,
            right: 28,
            child: Icon(
              Icons.star,
              size: 6,
              color: AppColors.darkText.withValues(alpha: 0.6),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _block(38, 18),
              const SizedBox(width: 6),
              _block(58, 22),
              const SizedBox(width: 6),
              _block(46, 18),
            ],
          ),
        ],
      ),
    );
  }
}

/// Approximates the requested rocket-launch illustration with a Material
/// icon plus scattered star sparkles - see [_BuildingsIllustration] note.
class _RocketIllustration extends StatelessWidget {
  const _RocketIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppDimensions.bannerIllustrationSize,
      height: AppDimensions.bannerIllustrationSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 4,
            left: 12,
            child: Icon(
              Icons.star,
              size: 10,
              color: AppColors.darkText.withValues(alpha: 0.7),
            ),
          ),
          Positioned(
            top: 16,
            right: 10,
            child: Icon(
              Icons.star,
              size: 8,
              color: AppColors.darkText.withValues(alpha: 0.5),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 8,
            child: Icon(
              Icons.star,
              size: 7,
              color: AppColors.darkText.withValues(alpha: 0.4),
            ),
          ),
          Icon(
            Icons.rocket_launch,
            size: 52,
            color: AppColors.darkText.withValues(alpha: 0.9),
          ),
        ],
      ),
    );
  }
}
