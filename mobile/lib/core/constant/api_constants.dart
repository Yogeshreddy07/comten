import 'package:flutter/foundation.dart' show kReleaseMode;

class ApiConstants {
  // The copied UI uses Firebase directly for routine operations. Privileged
  // operations require this FastAPI origin; release builds require explicit HTTPS.
  static const _prodBaseUrl = 'https://configure-crompton-backend.invalid/api';
  static const _devBaseUrl = 'http://127.0.0.1:8006/api';

  static String get baseUrl {
    const fromEnv = String.fromEnvironment('BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    return kReleaseMode ? _prodBaseUrl : _devBaseUrl;
  }

  static const requestTimeoutSeconds = 15;

  // Login is commonly the first request after the app opens. The production
  // service may be cold and take substantially longer than a normal API call
  // to start, so do not report a connection failure while it is still waking.
  // This is deliberately a longer timeout on one request, not an automatic
  // POST retry: a successful login replaces the account's active-session
  // token, so replaying it could immediately invalidate the first response.
  static const loginTimeoutSeconds = 120;

  // Sending the forgot-password email OTP involves a live dispatch to Resend on
  // the backend, which is slower than a typical CRUD call, especially on a cold
  // backend/JVM start. A longer, dedicated timeout avoids the client giving up
  // before the backend (which has no such timeout) finishes and actually
  // dispatches it.
  static const otpSendTimeoutSeconds = 30;

  // ---- AUTH ----
  // NOTE: paths only (not prefixed with baseUrl) - ApiService.get/post/put/delete
  // prepend baseUrl internally.
  static const authVerifyTempPassword = '/auth/signup/verify-temp-password';
  static const authSetPassword = '/auth/signup/set-password';
  // Firebase Auth phone sign-in (SMS OTP) - the SMS send/verify itself happens
  // natively on-device (see PhoneVerificationChannel); this just submits the
  // resulting ID token to the backend for validation.
  static const authVerifyPhone = '/auth/signup/verify-phone';
  static const authLogin = '/auth/login';
  static const authForgotPasswordSendOtp = '/auth/forgot-password/send-otp';
  static const authForgotPasswordVerifyOtp = '/auth/forgot-password/verify-otp';
  static const authForgotPasswordReset = '/auth/forgot-password/reset';
  static const authChangePassword = '/auth/change-password';
  static const authLogout = '/auth/logout';

  // ---- USERS ----
  static const usersMe = '/users/me';

  // ---- PROJECTS ----
  static const projects = "/projects";
  static String projectById(String id) => "/projects/$id";
  static const projectUsers = "/projects/users";
  static String deleteProject(String id) => "/projects/$id/delete";
  static String activateProject(String id) => "/projects/$id/activate";

  // ---- MODULES ----
  static const modules = "/modules";
  static String moduleById(String id) => "/modules/$id";
  static const modulesLed = "/modules/led";
  static const modulesLedCompleted = "/modules/led/completed";
  static String moduleWorkStage(String id) => "/modules/$id/work-stage";
  static String activateModule(String id) => "/modules/$id/activate";
  static String deleteModule(String id) => "/modules/$id/delete";

  // ---- EMPLOYEES ----
  static const employees = "/employees";
  static String employeeById(String id) => "/employees/$id";
  static String activateEmployee(String id) => "/employees/$id/activate";
  static String deleteEmployee(String id) => "/employees/$id/delete";

  // ---- ACTIVITIES ----
  static const activities = "/activities";
  static String activityById(String id) => "/activities/$id";

  // ---- MODULE CHANGE REQUESTS (Approval module) ----
  static const moduleChangeRequests = "/module-change-requests";
  static String moduleChangeRequestById(String id) =>
      "/module-change-requests/$id";
  static String moduleChangeRequestsByModule(String moduleId) =>
      "/module-change-requests?moduleId=$moduleId";
  static String approveModuleChangeRequest(String id) =>
      "/module-change-requests/$id/approve";
  static String rejectModuleChangeRequest(String id) =>
      "/module-change-requests/$id/reject";

  // ---- PROJECT DEACTIVATION REQUESTS (Approval module) ----
  static const projectDeactivationRequests = "/project-deactivation-requests";
  static String projectDeactivationRequestById(String id) =>
      "/project-deactivation-requests/$id";
  static String approveProjectDeactivationRequest(String id) =>
      "/project-deactivation-requests/$id/approve";
  static String rejectProjectDeactivationRequest(String id) =>
      "/project-deactivation-requests/$id/reject";

  // ---- WORK LOGS (Working Hours / Timesheet) ----
  static const workLogs = "/work-logs";
  static const myWorkLogs = "/work-logs/my";
  static const workLogReminder = "/work-logs/reminder";
  static String workLogById(String id) => "/work-logs/$id";
  static String approveWorkLog(String id) => "/work-logs/$id/approve";
  static String rejectWorkLog(String id) => "/work-logs/$id/reject";

  // ---- ATTENDANCE ----
  static const attendanceCheckIn = "/attendance/check-in";
  static const attendanceCheckOut = "/attendance/check-out";
  static const attendanceToday = "/attendance/today";
  static const attendanceTeam = "/attendance/team";

  // ---- BILLING ----
  static const billing = "/billing";
  static String billingByModuleId(String moduleId) => "/billing/$moduleId";

  // ---- BILLING STATUS CHANGE REQUESTS (Billing Approval module) ----
  static const billingStatusChangeRequests = "/billing-status-change-requests";
  static String billingStatusChangeRequestById(String id) =>
      "/billing-status-change-requests/$id";
  static String approveBillingStatusChangeRequest(String id) =>
      "/billing-status-change-requests/$id/approve";
  static String rejectBillingStatusChangeRequest(String id) =>
      "/billing-status-change-requests/$id/reject";

  // ---- NOTIFICATIONS ----
  static const notifications = "/notifications";
  static const notificationsUnreadCount = "/notifications/unread-count";
  static String markNotificationRead(String id) => "/notifications/$id/read";
  static const submitDelayRequest = "/notifications/delay-requests";
  static const registerDeviceToken = "/notifications/device-tokens";
  static const unregisterDeviceToken =
      "/notifications/device-tokens/unregister";
}
