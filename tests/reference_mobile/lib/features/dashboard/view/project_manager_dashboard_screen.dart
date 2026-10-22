import 'package:flutter/material.dart';

import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/user_role.dart';
import '../model/dashboard_item.dart';
import '../widgets/role_dashboard_scaffold.dart';

/// Post-login landing screen for the PROJECT_CONTROLLER role. Shares the
/// same premium shell as every other role dashboard via
/// [RoleDashboardScaffold] - only the module set and hero copy differ.
class ProjectManagerDashboardScreen extends StatelessWidget {
  const ProjectManagerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleDashboardScaffold(
      modules: UserRole.projectManager.dashboardModules,
      heroTitle: AppStrings.dashboardHeroTitleProjectManager,
      heroSubtitle: AppStrings.dashboardHeroSubtitleProjectManager,
    );
  }
}
