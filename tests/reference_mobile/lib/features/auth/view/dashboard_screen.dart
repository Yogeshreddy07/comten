import 'package:flutter/material.dart';

import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/user_role.dart';
import '../../dashboard/model/dashboard_item.dart';
import '../../dashboard/widgets/role_dashboard_scaffold.dart';

/// The Captain Dashboard - the live post-login landing screen for the
/// CAPTAIN role. All the actual UI (header, hero banner, Quick Access grid,
/// bottom nav) lives in [RoleDashboardScaffold], which every role dashboard
/// shares; this screen only supplies Captain's module set and hero copy.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleDashboardScaffold(
      modules: UserRole.captain.dashboardModules,
      heroTitle: AppStrings.dashboardHeroTitle,
      heroSubtitle: AppStrings.dashboardHeroSubtitle,
    );
  }
}
