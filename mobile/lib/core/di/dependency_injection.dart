import '../../features/activities/repository/activity_repository.dart';
import '../../features/approvals/repository/approval_repository.dart';
import '../../features/attendance/repository/attendance_repository.dart';
import '../../features/auth/repository/auth_repository.dart';
import '../../features/billing/repository/billing_repository.dart';
import '../../features/employees/repository/employee_repository.dart';
import '../../features/modules/repository/module_repository.dart';
import '../../features/notifications/repository/notification_repository.dart';
import '../../features/projects/repository/project_repository.dart';
import '../../features/worklogs/repository/work_log_repository.dart';

/// Central place repositories are constructed, so screens/bootstrap code
/// don't each instantiate their own copy.
class DependencyInjection {
  static final AuthRepository authRepository = AuthRepository();
  static final ProjectRepository projectRepository = ProjectRepository();
  static final ModuleRepository moduleRepository = ModuleRepository();
  static final EmployeeRepository employeeRepository = EmployeeRepository();
  static final WorkLogRepository workLogRepository = WorkLogRepository();
  static final AttendanceRepository attendanceRepository = AttendanceRepository();
  static final BillingRepository billingRepository = BillingRepository();
  static final ActivityRepository activityRepository = ActivityRepository();
  static final ApprovalRepository approvalRepository = ApprovalRepository();
  static final NotificationRepository notificationRepository = NotificationRepository();
}