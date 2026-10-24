class AppStrings {
  AppStrings._();

  // Dashboard (shared across all role dashboards)
  static const dashboardTitle = 'Dashboard';
  static const dashboardGreetingMorning = 'Good morning,';
  static const dashboardGreetingAfternoon = 'Good afternoon,';
  static const dashboardGreetingEvening = 'Good evening,';
  static const dashboardTagline = "Here's an overview of your workspace";

  static const dashboardQuickAccessHeading = 'Quick Access';

  static const dashboardMotivationTitle = "Let's make today productive!";
  static const dashboardMotivationSubtitle =
      'Keep pushing forward and achieve more.';

  // Captain Dashboard hero banner
  static const dashboardHeroTitle = 'Stay on top of your projects and team';
  static const dashboardHeroSubtitle = 'Manage · Monitor · Succeed';

  // Project Controller Dashboard hero banner
  static const dashboardHeroTitleProjectManager =
      'Keep your projects and teams on track';
  static const dashboardHeroSubtitleProjectManager =
      'Plan · Coordinate · Deliver';

  // Team Leader Dashboard hero banner
  static const dashboardHeroTitleTeamLeader =
      'Guide your team to success today';
  static const dashboardHeroSubtitleTeamLeader = 'Support · Track · Achieve';

  // Employee Dashboard hero banner
  static const dashboardHeroTitleEmployee =
      'Stay productive and organized today';
  static const dashboardHeroSubtitleEmployee = 'Focus · Contribute · Grow';

  static const dashboardModuleProjects = 'Projects';
  static const dashboardModuleEmployees = 'Employee Management';
  static const dashboardModuleProjectControllers =
      'Project Controller Management';
  static const dashboardModuleAttendance = 'Attendance';
  static const dashboardModuleNotifications = 'Notifications';
  static const dashboardModuleSettings = 'Settings';
  static const dashboardModuleTeamManagement = 'Team Management';
  static const dashboardModuleTasks = 'Tasks';
  static const dashboardModuleLeave = 'Leave';
  static const dashboardModuleTimesheet = 'Timesheet';
  static const dashboardModuleBilling = 'Billing Management';
  static const dashboardModuleActivities = 'Activities';
  static const dashboardModuleApproval = 'Approval';

  static const dashboardModuleProjectsDescription =
      'View and manage all projects';
  static const dashboardModuleEmployeesDescription = 'Manage your team members';
  static const dashboardModuleProjectControllersDescription =
      'Manage Project Controller accounts';
  static const dashboardModuleAttendanceDescription =
      'Track attendance and reports';
  static const dashboardModuleNotificationsDescription =
      'Stay updated with alerts & updates';
  static const dashboardModuleSettingsDescription = 'Manage your preferences';
  static const dashboardModuleTeamManagementDescription =
      'Oversee your project teams';
  static const dashboardModuleTasksDescription =
      'Track and complete your assigned tasks';
  static const dashboardModuleLeaveDescription =
      'Apply for and track your leave requests';
  static const dashboardModuleTimesheetDescription =
      'Log your working hours and track approval status';
  static const dashboardModuleBillingDescription =
      'Track and update project billing status';
  static const dashboardModuleActivitiesDescription =
      'Create Billable and Non-Billable activities for projects';
  static const dashboardModuleApprovalDescription =
      'Approve or reject project End Date/Estimated Hours change requests';

  // Role-specific relabeling of a shared module (same capability, different
  // wording per role) - kept as overrides rather than new modules so the
  // underlying icon/navigation/accent stays a single source of truth.
  static const dashboardModuleAssignedProjects = 'Assigned Projects';
  static const dashboardModuleAssignedProjectsDescription =
      'View projects assigned to your team';
  static const dashboardModuleMyProjects = 'My Projects';
  static const dashboardModuleMyProjectsDescription =
      'View projects you are working on';
  static const dashboardModuleTeamMembers = 'Team Members';
  static const dashboardModuleTeamMembersDescription =
      'View and manage your team';
  static const dashboardModuleProjectDatabase = 'Project Database';
  static const dashboardModuleProjectDatabaseDescription =
      'View your projects and their team members';
  static const dashboardModuleTimesheetApprovals = 'Timesheet Approvals';
  static const dashboardModuleTimesheetApprovalsDescription =
      'Review and approve submitted timesheets';

  static const bottomNavHome = 'Home';
  static const bottomNavProjects = 'Projects';
  static const bottomNavEmployees = 'Employees';
  static const bottomNavAttendance = 'Attendance';
  static const bottomNavSettings = 'Settings';

  static String moduleComingSoon(String moduleName) =>
      '$moduleName module coming soon';

  // Roles (shared picker labels - kept in sync with UserRole/backend values).
  // Displayed as "Project Controller" per product decision, even though the
  // Dart identifier stays `UserRole.projectManager` (matches the backend's
  // own "PROJECT_CONTROLLER" role string - only the label changed here).
  static const roleCaptain = 'Captain';
  static const roleProjectManager = 'Project Controller';
  static const roleTeamLeader = 'Team Leader';
  static const roleEmployee = 'Employee';

  // Create Project/Module flow
  static const createProjectTitle = 'Create Project';
  static const createProjectButton = 'Create Project';
  static const createProjectSectionInformation = 'Project Information';
  static const createProjectSectionModule = 'Module';
  static const createProjectSectionTeam = 'Team Information';
  static const createProjectSectionTimeline = 'Timeline';

  static const createProjectChoiceNewProject = 'New Project';
  static const createProjectChoiceExistingProject = 'Existing Project';
  static const createProjectFieldExistingProject = 'Select Project';
  static const createProjectSelectExistingProjectHint = 'Choose a project';

  static const createProjectFieldClientId = 'Client ID';
  static const createProjectFieldProjectName = 'Project Name';
  static const createProjectFieldProjectId = 'Project ID';
  static const createProjectFieldModuleName = 'Module Name';
  static const createProjectFieldBuildingClassification = 'Building Classification';
  static const createProjectFieldStructureClassification = 'Structure Classification';
  static const createProjectFieldNumberOfFloors = 'Number of Floors';
  static const createProjectFieldArea = 'Area (sq ft)';
  static const createProjectFieldTeamLeader = 'Team Leader';
  static const createProjectFieldEmployees = 'Employees';
  static const createProjectFieldStartDate = 'Start Date';
  static const createProjectFieldEndDate = 'End Date';
  static const createProjectFieldEstimatedHours = 'Estimated Working Hours';

  static const createProjectModuleNameHint =
      'e.g. Web Frontend, Backend Services';
  static const createProjectBuildingClassificationHint =
      'e.g. Residential, Commercial';
  static const createProjectStructureClassificationHint =
      'e.g. RCC, Steel Frame';
  static const createProjectSelectTeamLeaderHint = 'Select Team Leader';
  static const createProjectSelectEmployeesHint = 'Select Employees';
  static const createProjectNoEmployeesSelected = 'No employees added yet';
  static const createProjectReviewButton = 'Review Project';

  static String createProjectSelectParentFirst(String parentLabel) =>
      'Select $parentLabel first';

  static const estimatedDurationHoursHint = 'HH';
  static const estimatedDurationMinutesHint = 'MM';
  static const estimatedDurationSecondsHint = 'SS';

  static const reviewProjectTitle = 'Review Project';
  static const reviewProjectEditButton = 'Edit';
  static const reviewProjectConfirmButton = 'Confirm & Create';

  static const projectSuccessTitle = 'Project Created Successfully';
  static const projectSuccessSubtitle =
      'The project has been created and is ready to go.';
  static const projectSuccessBackButton = 'Continue';

  // Modules (add-on to an existing or new project)
  static const addModuleButton = 'Add Module';
  static const moduleDetailsTitle = 'Module Details';
  static const editModuleTitle = 'Edit Module';
  static const moduleSuccessTitle = 'Module Created Successfully';
  static const moduleSuccessSubtitle =
      'The module has been created and is ready to go.';

  static const userPickerSearchHint = 'Search by name, ID, or email';

  static String userPickerEmptyForRole(String roleLabel) =>
      'No $roleLabel users found';

  static String failedToLoadUsersForRole(String roleLabel) =>
      'Failed to load $roleLabel users';

  // Employee Management
  static const employeeListTitle = 'Employee Management';
  static const employeeListAddButton = 'Add Employee';
  static const employeeListSearchHint = 'Search by name, ID, or email';
  static const employeeListEmptyTitle = 'No employees yet';
  static const employeeListEmptyMessage =
      'Tap "Add Employee" to add your first team member.';

  // Project Controller Management (Captain-only, same screens as Employee
  // Management, scoped to role=PROJECT_CONTROLLER).
  static const addProjectControllerButton = 'Add Project Controller';
  static const projectControllerListEmptyTitle = 'No Project Controllers yet';
  static const projectControllerListEmptyMessage =
      'Tap "Add Project Controller" to add your first one.';
  static const employeeListLoadErrorTitle = 'Unable to load employees';
  static const employeeListLoading = 'Loading employees...';
  static const employeeStatusActive = 'Active';
  static const employeeStatusInactive = 'Inactive';

  static const addEmployeeTitle = 'Add Employee';
  static const editEmployeeTitle = 'Edit Employee';
  static const employeeFieldName = 'Name';
  static const employeeFieldCode = 'Employee Code';
  static const employeeFieldRole = 'Role';
  static const employeeFieldPhone = 'Mobile Number';
  static const employeeFieldEmail = 'Email ID';
  static const employeeSaveButton = 'Save';
  static const employeeNextButton = 'Next';
  static const employeeCancelButton = 'Cancel';
  static const addEmployeeWelcomeNote =
      'An activation OTP will be emailed to the registered address. The employee can verify it and set their own password.';

  static const deactivateEmployeeTitle = 'Deactivate Employee';
  static String deactivateEmployeeMessage(String name) =>
      'Are you sure you want to deactivate "$name"? '
      'They will no longer be able to log in.';

  static const activateEmployeeTitle = 'Activate Employee';
  static String activateEmployeeMessage(String name) =>
      'Are you sure you want to activate "$name"? '
      'They will be able to log in again.';

  static const deleteEmployeeTitle = 'Delete Employee';
  static String deleteEmployeeMessage(String name) =>
      'Are you sure you want to delete "$name"? '
      'This cannot be undone from the app - the employee will no longer '
      'appear anywhere, though their records are retained.';

  // Review Employee/TL (Add & Edit share the same review -> confirm -> save
  // step; see ReviewEmployeeScreen).
  static String reviewAddEmployeeTitle(String roleLabel) =>
      'Review $roleLabel Details';
  static String reviewEditEmployeeTitle(String roleLabel) =>
      'Review $roleLabel Changes';
  static const reviewEmployeeSectionTitle = 'Entered Details';
  static const reviewEmployeeWarning =
      'Please review the entered details carefully before proceeding.';
  static const reviewEmployeeEditButton = 'Edit';
  static const reviewEmployeeConfirmButton = 'Confirm';

  static const confirmSaveEmployeeTitle = 'Confirm Save';
  static const confirmSaveEmployeeMessage =
      'Once the employee is saved, the Name and Employee Code cannot be modified. Click Save to add the employee.';
  static const confirmSaveEmployeeCancelButton = 'Cancel';
  static const confirmSaveEmployeeSaveButton = 'Save';

  // Activities (Project Controller-only master list; assigned per-project as
  // Billable / Non-Billable in Create/Edit Project).
  static const activityListTitle = 'Activities';
  static const activityListAddButton = 'Add Activity';
  static const activityListEmptyTitle = 'No activities yet';
  static const activityListEmptyMessage =
      'Tap "Add Activity" to create your first activity.';
  static const activityListLoadErrorTitle = 'Unable to load activities';
  static const activityListLoading = 'Loading activities...';
  static const addActivityTitle = 'Add Activity';
  static const activityFieldName = 'Activity Name';
  static const activityCreateSuccess = 'Activity created successfully';
  static const activityDeleteTitle = 'Delete Activity';
  static String activityDeleteConfirmMessage(String activityName) =>
      'Are you sure you want to delete "$activityName"? This cannot be undone.';
  static const billableActivitiesLabel = 'Billable Activities';
  static const nonBillableActivitiesLabel = 'Non-Billable Activities';
  static const activitiesEmptyForProjectMessage =
      'No activities configured for this project yet.';

  // Working Hours / Timesheet (Employee, Team Leader)
  static const timesheetListTitle = 'My Timesheets';
  static const timesheetListAddButton = 'Log Hours';
  static const timesheetListLoading = 'Loading timesheets...';
  static const timesheetListLoadErrorTitle = 'Unable to load timesheets';
  static const timesheetListEmptyTitle = 'No timesheets yet';
  static const timesheetListEmptyMessage =
      'Tap "Log Hours" to submit your first timesheet entry.';

  static const timesheetReminderTitle = 'Missed Working Hours Update';
  static String timesheetReminderMessage(String dayLabel) =>
      'You have not updated your working hours for $dayLabel. Please complete it now.';
  static const timesheetReminderDismiss = 'OK';

  static const submitTimesheetTitle = 'Log Working Hours';
  static const submitTimesheetButton = 'Submit Timesheet';
  static const timesheetFieldProject = 'Project';
  static const timesheetSelectProjectHint = 'Select Project';
  static const timesheetFieldWorkDate = 'Work Date';
  static const billableHoursWorkedLabel = 'Billable Hours Worked';
  static const nonBillableHoursWorkedLabel = 'Non-Billable Hours Worked';
  static const timesheetFieldWorkDone = 'Work Done';
  static const timesheetWorkDoneHint = 'Describe the work completed';
  static const timesheetSubmitSuccess = 'Timesheet submitted successfully';
  static const timesheetNoProjectsMessage =
      'You are not assigned to any project yet.';

  static const timesheetDetailsTitle = 'Timesheet Details';
  static const timesheetRejectionReasonLabel = 'Rejection Reason';
  static const timesheetApprovedByLabel = 'Approved By';

  // Timesheet Approvals (Team Leader)
  static const timesheetApprovalListTitle = 'Timesheet Approvals';
  static const timesheetApprovalListLoading = 'Loading timesheets...';
  static const timesheetApprovalListLoadErrorTitle =
      'Unable to load timesheets';
  static const timesheetApprovalListEmptyTitle = 'No timesheets found';
  static const timesheetApprovalListEmptyMessage =
      'There are no timesheet entries for this filter yet.';
  static const timesheetApproveButton = 'Approve';
  static const timesheetRejectButton = 'Reject';
  static const timesheetApproveSuccess = 'Timesheet approved successfully';
  static const timesheetRejectSuccess = 'Timesheet rejected successfully';
  static const timesheetRejectDialogTitle = 'Reject Timesheet';
  static const timesheetRejectDialogMessage =
      'Please provide a reason for rejecting this timesheet entry.';
  static const timesheetRejectReasonHint = 'Enter rejection reason';
  static const timesheetRejectReasonRequired = 'Rejection reason is required';

  static const timesheetFilterAll = 'All';
  static const timesheetFilterPending = 'Pending';
  static const timesheetFilterApproved = 'Approved';
  static const timesheetFilterRejected = 'Rejected';

  // Attendance (Employee)
  static const attendanceScreenTitle = 'Attendance';
  static const attendanceLoading = 'Loading attendance...';
  static const attendanceLoadErrorTitle = 'Unable to load attendance';
  static const attendanceNotCheckedInTitle = "You haven't checked in today";
  static const attendanceNotCheckedInMessage =
      'Tap "Check In" to record your attendance for today.';
  static const attendanceCheckedInTitle = 'Checked in';
  static const attendanceCompletedTitle = 'Attendance completed for today';
  static const attendanceCheckInButton = 'Check In';
  static const attendanceCheckOutButton = 'Check Out';
  static const attendanceCheckInSuccess = 'Checked in successfully';
  static const attendanceCheckOutSuccess = 'Checked out successfully';

  static const attendanceCheckoutReminderTitle = 'Checkout Reminder';
  static const attendanceCheckoutReminderMessage =
      "You have not checked out for today's attendance. Would you like to check out now?";
  static const attendanceCheckoutReminderCancelButton = 'Cancel';
  static const attendanceCheckoutReminderContinueButton = 'Continue';

  static const checkInFieldType = 'Work Mode';
  static const checkInSelectTypeMessage = 'Please select a work mode';

  static const attendanceLocationLabel = 'Location';
  static const attendanceLocationCapturing = 'Capturing your location...';
  static const attendanceLocationCaptured = 'Location captured';
  static const attendanceLocationRetry = 'Retry';
  static const attendanceLocationOpenSettings = 'Settings';
  static const attendanceLocationServiceDisabled =
      'Location services are disabled. Please enable them to continue.';
  static const attendanceLocationPermissionDenied =
      'Location permission is required to record attendance.';
  static const attendanceLocationPermissionDeniedForever =
      'Location permission is permanently denied. Please enable it from Settings.';
  static const attendanceLocationFailed =
      'Unable to get your current location.';
  static const attendanceLocationNameUnavailable = 'Address unavailable';

  static const attendanceFieldWorkMode = 'Work Mode';
  static const attendanceFieldCheckInTime = 'Check-in Time';
  static const attendanceFieldCheckOutTime = 'Check-out Time';
  static const attendanceFieldCheckInLocation = 'Check-in Location';
  static const attendanceFieldCheckOutLocation = 'Check-out Location';
  static const attendanceNotCheckedOutYet = 'Not checked out yet';

  // Attendance (Team Leader)
  static const attendanceTeamTitle = 'Team Attendance';
  static const attendanceTeamLoading = 'Loading attendance...';
  static const attendanceTeamLoadErrorTitle = 'Unable to load attendance';
  static const attendanceTeamEmptyTitle = 'No team members found';
  static const attendanceTeamEmptyMessage =
      'You have no employees assigned to your projects yet.';
  static const attendanceDetailsTitle = 'Attendance Details';

  static const attendanceFilterToday = 'Today';

  // Billing Management (Captain, Project Controller)
  static const billingListTitle = 'Billing Management';
  static const billingLoading = 'Loading billing status...';
  static const billingLoadErrorTitle = 'Unable to load billing status';
  static const billingEmptyTitle = 'No projects found';
  static const billingEmptyMessage =
      'There are no projects for this filter yet.';
  static const billingStatusNotSet = 'To Be Billed';
  static const billingSpocNotSet = 'SPOC not assigned';
  static const billingTeamLeadNotSet = 'No Team Lead assigned';
  static const billingFieldTeamLead = 'Team Lead';

  static const billingTabNotSet = 'To Be Billed';
  static const billingTabPending = 'Pending';
  static const billingTabCompleted = 'Completed';

  static const updateBillingTitle = 'Update Billing Status';
  static const updateBillingButton = 'Save';
  static const billingFieldSpocName = 'SPOC Name';
  static const billingFieldStatus = 'Status';
  static const billingFieldRemarks = 'Remarks';
  static const billingRemarksHint = 'Add any notes about this billing update';
  static const billingUpdateSuccess = 'Billing status updated successfully';
  static const billingFieldLastUpdated = 'Last Updated';
  static const billingFieldUpdatedBy = 'Updated By';

  // Billing Approval (Captain) - Project Controller requests to revert a
  // billing project from Completed back to Pending; shown together with
  // Project Change Requests in the unified Approval screen (see
  // [ApprovalListScreen]).
  static const billingApprovalDetailsTitle = 'Billing Reversion Request';
  static const billingApprovalFieldCurrentStatus = 'Current Status';
  static const billingApprovalFieldProposedStatus = 'Proposed Status';
  static const billingApprovalApproveSuccess = 'Billing reversion approved';
  static const billingApprovalRejectSuccess = 'Billing reversion rejected';

  // Approval (Captain) - Project Controller requests to change a project's
  // End Date/Estimated Hours (independent of the Team Lead's Reason for
  // Delay notification, which stays purely informational).
  static const approvalListTitle = 'Approval';
  static const approvalLoading = 'Loading requests...';
  static const approvalLoadErrorTitle = 'Unable to load requests';
  static const approvalEmptyTitle = 'No requests found';
  static const approvalEmptyMessage =
      'There are no change requests for this filter yet.';
  static const approvalTabPending = 'Pending';
  static const approvalTabApproved = 'Approved';
  static const approvalTabRejected = 'Rejected';
  static const approvalDetailsTitle = 'Change Request';
  static const approvalFieldRequestedBy = 'Requested By';
  // "Existing"/"Requested" rather than "Current"/"Proposed": once a request
  // is decided (especially rejected), "Current" reads ambiguously - it can
  // look like it means the request's own proposed value rather than the
  // module's end date at the time the request was raised.
  static const approvalFieldCurrentEndDate = 'Existing End Date';
  static const approvalFieldProposedEndDate = 'Requested End Date';
  static const approvalFieldCurrentEstimatedHours = 'Current Estimated Hours';
  static const approvalFieldProposedEstimatedHours = 'Proposed Estimated Hours';
  static const approvalFieldRemarks = 'Remarks';
  static const approvalFieldDecisionReason = 'Decision Reason';
  static const approvalDecisionReasonHint =
      'Required to reject; optional to approve';
  static const approvalApproveButton = 'Approve';
  static const approvalRejectButton = 'Reject';
  static const approvalReasonRequiredError = 'A reason is required';
  static const approvalApproveSuccess = 'Change request approved';
  static const approvalRejectSuccess = 'Change request rejected';

  static const submitChangeRequestTitle = 'Request Change';
  static const submitChangeRequestPendingBanner =
      'A change request is pending Captain approval for this project.';
  static const submitChangeRequestSuccess =
      'Your requested change has been sent to the Captain for approval.';
  static const projectPendingApprovalBadge = 'Pending Captain Approval';

  // Project Database (Team Lead) - the Team Lead dashboard's relabeled
  // Projects tile (see dashboard_item.dart).
  static const projectDatabaseTitle = 'Project Database';

  // Status Update (Team Lead)
  static const dashboardModuleStatusUpdate = 'Status Update';
  static const dashboardModuleStatusUpdateDescription =
      'Mark a project WIP or move it to Billing';

  static const statusUpdateTitle = 'Status Update';
  static const statusUpdateLoading = 'Loading your projects...';
  static const statusUpdateLoadErrorTitle = 'Unable to load projects';
  static const statusUpdateEmptyTitle = 'No projects assigned';
  static const statusUpdateEmptyMessage =
      'None of the projects you lead are marked Completed yet.';
  static const statusUpdateFieldProject = 'Project Name';
  static const statusUpdateFieldModule = 'Module';
  static const statusUpdateFieldStatus = 'Status';
  static const statusUpdateButton = 'Submit';
  static const statusUpdateSuccess = 'Project status updated successfully';
  static const statusUpdateSelectProjectMessage = 'Please select a project';
  static const statusUpdateSelectModuleMessage = 'Please select a module';
  static const statusUpdateSelectStatusMessage = 'Please select a status';
  static const statusUpdateModulesEmptyHint =
      'No eligible modules for this project';

  // Reason for Delay (Team Lead)
  static const dashboardModuleReasonForDelay = 'Reason for Delay';
  static const dashboardModuleReasonForDelayDescription =
      'Submit a reason for delay to the Project Controller';

  static const reasonForDelayTitle = 'Reason for Delay';
  static const reasonForDelayLoading = 'Loading your projects...';
  static const reasonForDelayLoadErrorTitle = 'Unable to load projects';
  static const reasonForDelayEmptyTitle = 'No overdue projects';
  static const reasonForDelayEmptyMessage =
      'None of your projects have passed their end date yet.';
  static const reasonForDelayFieldProject = 'Project Name';
  static const reasonForDelayFieldModule = 'Module';
  static const reasonForDelayFieldReason = 'Reason';
  static const reasonForDelayReasonHint = 'Describe the reason for the delay';
  static const reasonForDelayReasonRequired = 'Reason is required';
  static const reasonForDelayButton = 'Submit';
  static const reasonForDelaySuccess =
      'Reason for delay submitted successfully';
  static const reasonForDelaySelectProjectMessage = 'Please select a project';
  static const reasonForDelaySelectModuleMessage = 'Please select a module';
  static const reasonForDelayModulesEmptyHint =
      'No eligible modules for this project';

  // Notifications (all roles)
  static const notificationListTitle = 'Notifications';
  static const notificationListLoading = 'Loading notifications...';
  static const notificationListLoadErrorTitle = 'Unable to load notifications';
  static const notificationListEmptyTitle = 'No notifications yet';
  static const notificationListEmptyMessage =
      "You're all caught up - new notifications will appear here.";

  static const notificationDetailsTitle = 'Reason for Delay';
  static const notificationBillingSubmittedTitle = 'Submitted for Billing';
  static const notificationFieldProject = 'Project';
  static const notificationFieldModule = 'Module';
  static const notificationFieldSubmittedBy = 'Submitted By';
  static const notificationFieldReason = 'Reason';
  static const notificationContinueButton = 'Continue';
  static const notificationBillingEntryNotFound =
      'This module is no longer awaiting billing - it may have already been processed.';

  // Unread notifications gate (shown before the dashboard on app entry)
  static const notificationGateTitle = 'New Notifications';
  static const notificationGateMessage =
      'Please review your new notifications before continuing.';
  static const notificationGateLoadErrorTitle = 'Unable to load notifications';
  static const notificationGateContinueButton = 'Continue';

  // Settings (all roles)
  static const settingsTitle = 'Settings';
  static const settingsLoading = 'Loading settings...';
  static const settingsLoadErrorTitle = 'Unable to load settings';

  static const settingsSectionAccount = 'Account';
  static const settingsChangePassword = 'Change Password';
  static const settingsChangePasswordSubtitle = 'Update your account password';
  static const settingsChangePin = 'Change App PIN';
  static const settingsChangePinSubtitle = 'Update your quick-access PIN';

  static const settingsSectionSecurity = 'Security';
  static const settingsBiometricLogin = 'Biometric Login';
  static const settingsBiometricLoginSubtitle =
      'Use your fingerprint to log in quickly';
  static const settingsBiometricUnavailable =
      'Biometric hardware is unavailable on this device.';
  static const settingsAppLockInfo = 'App Lock';
  static const settingsAppLockInfoMessage =
      "Your account is protected with a 4-digit PIN and, if enabled, "
      "biometric login. You'll be asked to unlock the app every time you "
      "return to it.";

  static const settingsSectionAppearance = 'Appearance';
  static const settingsDarkMode = 'Dark Mode';
  static const settingsDarkModeSubtitleOn = 'Dark theme is on';
  static const settingsDarkModeSubtitleOff = 'Switch to a dark color scheme';

  static const settingsSectionPrivacy = 'Privacy';
  static const settingsPrivacyPolicy = 'Privacy Policy';
  static const settingsPrivacyPolicyBody =
      "We value your privacy. Comten collects only the information "
      "necessary to provide attendance, timesheet, billing and project "
      "management services to your organization. Your data is stored "
      "securely and is never shared with third parties without your "
      "consent. You may request access to or deletion of your data at "
      "any time by contacting your administrator.";
  static const settingsSecurityInformation = 'Security Information';
  static const settingsSecurityInformationBody =
      "Comten protects your account with password and PIN-based "
      "authentication, optional biometric login, and encrypted network "
      "communication. Sessions are secured using industry-standard "
      "tokens that expire automatically. We recommend enabling biometric "
      "login and choosing a strong, unique password to keep your account "
      "secure.";

  static const settingsLogout = 'Logout';
  static const settingsLogoutConfirmTitle = 'Logout';
  static const settingsLogoutConfirmMessage =
      'Are you sure you want to logout?';
  static const settingsLogoutSuccess = 'Logged out successfully';

  /// Detection key only, not shown to the user - text must match `JwtFilter
  /// .SESSION_INVALIDATED_MESSAGE` on the backend exactly, since that's how
  /// `ApiService` recognizes this specific 401 case. See
  /// [sessionInvalidatedDisplayMessage] for the message actually shown.
  static const sessionInvalidatedMessage =
      'Your account has been logged in from another device.';

  /// Detection key for the other rejection `JwtFilter` can return: this account
  /// has no active session at all (logged out, or the server restarted), rather
  /// than having been superseded elsewhere. Must match
  /// `JwtFilter.SESSION_ENDED_MESSAGE` exactly.
  static const sessionEndedMessage =
      'Your session has ended. Please sign in again.';

  /// Shown to the user when this device's session was superseded by a
  /// newer login elsewhere (see `SessionManager`). Kept separate from
  /// [sessionInvalidatedMessage] so its wording can change freely without
  /// touching the backend-matching logic.
  static const sessionInvalidatedDisplayMessage =
      'Your account has been logged in on another device. You have been '
      'signed out from this device for security reasons.';

  static const changePasswordTitle = 'Change Password';
  static const changePasswordCurrentLabel = 'Current Password';
  static const changePasswordNewLabel = 'New Password';
  static const changePasswordConfirmLabel = 'Confirm New Password';
  static const changePasswordButton = 'Update Password';
  static const changePasswordSuccess = 'Password updated successfully';

  static const changePinTitle = 'Change App PIN';
  static const changePinNewLabel = 'Enter New PIN';
  static const changePinConfirmLabel = 'Confirm New PIN';
  static const changePinButton = 'Update PIN';
  static const changePinSuccess = 'PIN updated successfully';

  // Role-based first-login walkthrough (shown once per employee - see
  // features/walkthrough). Per-role page copy reuses the dashboard hero and
  // Quick Access module strings above rather than duplicating them.
  static const walkthroughSkipButton = 'Skip';
  static const walkthroughNextButton = 'Next';
  static const walkthroughGetStartedButton = 'Get Started';
  static String walkthroughWelcomeTitle(String roleLabel) =>
      'Welcome, $roleLabel!';
  static const walkthroughWelcomeSubtitle =
      "Here's a quick look at what you can do in the app.";
  static const walkthroughDashboardPageTitle = 'Your Dashboard';
  static const walkthroughDashboardPageSubtitle =
      'Everything you need is one tap away from your dashboard.';
  static const walkthroughActionsPageTitle = 'What You Can Do';
  static const walkthroughActionsPageSubtitle =
      "Here's what you'll be doing most often.";
  static const walkthroughGetStartedTitle = "You're All Set!";
  static const walkthroughGetStartedSubtitle =
      'Jump into your dashboard and start managing your work.';

  // Walkthrough highlight bullets - 2 short, point-wise lines per screen
  // (see RoleWalkthroughContentX.walkthroughPages), each paired with an icon
  // instead of the single long subtitle above.
  static const walkthroughWelcomeHighlight1 =
      'See your role-based dashboard at a glance';
  static const walkthroughWelcomeHighlight2 =
      'Quick access to everything you need';

  static const walkthroughProjectsHighlight1 =
      'View all project details in one place';
  static const walkthroughProjectsHighlight2 =
      'Track progress of modules and projects in real time';

  // Employee-only: "My Projects" - unlike the shared copy above, this is
  // about accessing your own assigned work, not tracking overall progress.
  static const walkthroughMyProjectsHighlight1 =
      'View projects and modules assigned to you';
  static const walkthroughMyProjectsHighlight2 =
      "Quickly access the work you're responsible for";

  static const walkthroughAttendanceHighlight1 =
      'Mark your check-in and check-out';
  static const walkthroughAttendanceHighlight2 =
      'View attendance and reports';

  // Team Leader-only: Attendance is monitor-only for this role (Employees
  // are the ones who check in/out), unlike the Employee copy above.
  static const walkthroughAttendanceTeamLeaderHighlight1 =
      'See who has checked in or out';
  static const walkthroughAttendanceTeamLeaderHighlight2 =
      'Track attendance timings and history';

  static const walkthroughTimesheetHighlight1 =
      'Review hours logged by your team';
  static const walkthroughTimesheetHighlight2 =
      'Approve or reject submitted timesheets';

  // Employee-only: submitting a timesheet, not the Team Leader's approval
  // view above.
  static const walkthroughTimesheetSubmitHighlight1 =
      'Log hours by project, module, and work date';
  static const walkthroughTimesheetSubmitHighlight2 =
      'Submitted timesheets are reviewed by your Team Leader';

  static const walkthroughEmployeeManagementHighlight1 =
      'View all employees in your team';
  static const walkthroughEmployeeManagementHighlight2 =
      'Manage employee details and access';

  static const walkthroughProjectControllerHighlight1 =
      'View every Project Controller account';
  static const walkthroughProjectControllerHighlight2 =
      'Manage access across your organization';

  static const walkthroughBillingHighlight1 =
      'Track billing status across projects';
  static const walkthroughBillingHighlight2 =
      'Update billing as work is completed';

  // Captain-only: the Captain views billing status but never edits it,
  // unlike the Project Controller copy above (walkthroughBillingHighlight2).
  static const walkthroughBillingCaptainHighlight2 =
      'View pending, completed, and billed details';

  // Team Leader submits these for Project Controller approval - not simply
  // "posting an update".
  static const walkthroughStatusUpdateHighlight1 =
      'Submit Work in Progress or Billing status';
  static const walkthroughStatusUpdateHighlight2 =
      'Sent to your Project Controller for approval';

  // Team Leader submits a delay request for Project Controller review - not
  // just "flagging" it.
  static const walkthroughReasonForDelayHighlight1 =
      'Submit a request explaining the delay';
  static const walkthroughReasonForDelayHighlight2 =
      'Sent to your Project Controller for review';

  static const walkthroughActivitiesHighlight1 =
      'Create billable and non-billable activities';
  static const walkthroughActivitiesHighlight2 =
      'Organize work under each project module';

  static const walkthroughApprovalHighlight1 =
      'Review submitted change requests';
  static const walkthroughApprovalHighlight2 = 'Approve or reject in one tap';

  static const walkthroughGetStartedHighlight1 =
      'Everything is set up and ready';
  static const walkthroughGetStartedHighlight2 = 'Start managing your work now';
}
