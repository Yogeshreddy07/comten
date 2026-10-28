import '../../../core/services/performance_trace.dart';

import '../../../shared/constants/app_strings.dart';

/// Extends ChangeNotifier for consistency with the app's other ViewModels,
/// though there's no async/mutable state to notify about today - the
/// time-of-day greeting is the only thing computed here. Shared by every
/// role dashboard via [RoleDashboardScaffold]; each role's own module list
/// is supplied separately (see `UserRole.dashboardModules`).
class DashboardViewModel extends PerformanceNotifier {
  String get greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return AppStrings.dashboardGreetingMorning;
    if (hour < 17) return AppStrings.dashboardGreetingAfternoon;
    return AppStrings.dashboardGreetingEvening;
  }
}
