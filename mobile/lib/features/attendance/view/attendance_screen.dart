import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/location_helper.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/enums/attendance_type.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_view.dart';
import '../../../shared/widgets/app_loader.dart';
import '../model/attendance.dart';
import '../model/check_in_request.dart';
import '../model/check_out_request.dart';
import '../viewmodel/attendance_view_model.dart';
import '../widgets/location_status_card.dart';

/// Employee landing screen for the Attendance module - a single screen that
/// covers the whole day's flow: select a work mode, capture location, and
/// Check In; then, still on the same screen, view the check-in details and
/// Check Out (re-selecting a work mode and re-capturing location first).
/// [AttendanceViewModel] is provided app-wide (see main.dart); the work-mode/
/// location-capture state below is page-local ephemeral UI state.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  // ---- Check-in form state ----
  AttendanceType? _checkInType;
  bool _isLoadingCheckInLocation = false;
  bool _checkInLocationRequested = false;
  LocationResult? _checkInLocationResult;

  // ---- Check-out form state ----
  bool _isCheckingOut = false;
  AttendanceType? _checkOutType;
  bool _isLoadingCheckOutLocation = false;
  LocationResult? _checkOutLocationResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AttendanceViewModel>().fetchTodayAttendance();
    });
  }

  Future<void> _fetchCheckInLocation() async {
    setState(() => _isLoadingCheckInLocation = true);
    final result = await LocationHelper.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _checkInLocationResult = result;
      _isLoadingCheckInLocation = false;
    });
  }

  Future<void> _fetchCheckOutLocation() async {
    setState(() => _isLoadingCheckOutLocation = true);
    final result = await LocationHelper.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _checkOutLocationResult = result;
      _isLoadingCheckOutLocation = false;
    });
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _submitCheckIn() async {
    final type = _checkInType;
    final location = _checkInLocationResult;
    if (type == null) {
      SnackbarUtil.showError(context, AppStrings.checkInSelectTypeMessage);
      return;
    }
    if (location == null || !location.isSuccess) {
      SnackbarUtil.showError(context, AppStrings.attendanceLocationFailed);
      return;
    }

    final request = CheckInRequest(
      attendanceType: type.apiValue,
      latitude: location.latitude!,
      longitude: location.longitude!,
    );

    final result = await context.read<AttendanceViewModel>().checkIn(request);
    if (!mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, AppStrings.attendanceCheckInSuccess);
      setState(() {
        _checkInType = null;
        _checkInLocationResult = null;
      });
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  void _startCheckOut(Attendance today) {
    if (_isCheckingOut) return;
    setState(() {
      _isCheckingOut = true;
      _checkOutType = AttendanceTypeX.fromApiValue(today.attendanceType);
      _checkOutLocationResult = null;
    });
    _fetchCheckOutLocation();
  }

  Future<void> _submitCheckOut() async {
    final type = _checkOutType;
    final location = _checkOutLocationResult;
    if (type == null) {
      SnackbarUtil.showError(context, AppStrings.checkInSelectTypeMessage);
      return;
    }
    if (location == null || !location.isSuccess) {
      SnackbarUtil.showError(context, AppStrings.attendanceLocationFailed);
      return;
    }

    final request = CheckOutRequest(
      attendanceType: type.apiValue,
      latitude: location.latitude!,
      longitude: location.longitude!,
    );

    final result = await context.read<AttendanceViewModel>().checkOut(request);
    if (!mounted) return;

    if (result.success) {
      SnackbarUtil.showSuccess(context, AppStrings.attendanceCheckOutSuccess);
      setState(() => _isCheckingOut = false);
    } else {
      SnackbarUtil.showError(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AttendanceViewModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.attendanceScreenTitle),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(context, viewModel)),
    );
  }

  Widget _buildBody(BuildContext context, AttendanceViewModel viewModel) {
    switch (viewModel.loadState) {
      case AttendanceLoadState.initial:
      case AttendanceLoadState.loading:
        return const AppLoader(message: AppStrings.attendanceLoading);

      case AttendanceLoadState.error:
        return AppEmptyView(
          icon: Icons.cloud_off_outlined,
          title: AppStrings.attendanceLoadErrorTitle,
          message: viewModel.errorMessage,
          actionLabel: 'Retry',
          onAction: () => viewModel.fetchTodayAttendance(),
        );

      case AttendanceLoadState.success:
        final today = viewModel.today;
        return RefreshIndicator(
          onRefresh: viewModel.fetchTodayAttendance,
          child: ListView(
            padding: const EdgeInsets.all(AppDimensions.screenPadding),
            children: [
              if (today == null) _buildCheckInForm(context, viewModel),
              if (today != null && !today.isCheckedOut)
                _buildCheckedIn(context, viewModel, today),
              if (today != null && today.isCheckedOut)
                _buildCompleted(context, today),
            ],
          ),
        );
    }
  }

  Widget _buildCheckInForm(BuildContext context, AttendanceViewModel viewModel) {
    if (!_checkInLocationRequested) {
      _checkInLocationRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchCheckInLocation();
      });
    }

    final canSubmit = _checkInType != null &&
        (_checkInLocationResult?.isSuccess ?? false) &&
        !viewModel.isSubmitting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.login, color: AppColors.textSecondaryFor(context)),
              const SizedBox(height: 8),
              Text(
                AppStrings.attendanceNotCheckedInTitle,
                style: AppTextStyles.subHeading,
              ),
              const SizedBox(height: 4),
              Text(
                AppStrings.attendanceNotCheckedInMessage,
                style: TextStyle(color: AppColors.textSecondaryFor(context)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.sectionSpacing),
        const Text(
          AppStrings.checkInFieldType,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppDimensions.cardSpacing),
        Wrap(
          spacing: 12,
          children: [
            for (final type in AttendanceType.values)
              ChoiceChip(
                label: Text(type.label),
                avatar: Icon(type.icon, size: 18),
                selected: _checkInType == type,
                onSelected: (_) => setState(() => _checkInType = type),
              ),
          ],
        ),
        const SizedBox(height: AppDimensions.sectionSpacing),
        const Text(
          AppStrings.attendanceLocationLabel,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppDimensions.cardSpacing),
        LocationStatusCard(
          isLoading: _isLoadingCheckInLocation,
          result: _checkInLocationResult,
          onRetry: _fetchCheckInLocation,
        ),
        const SizedBox(height: AppDimensions.sectionSpacing),
        AppButton(
          text: AppStrings.attendanceCheckInButton,
          isLoading: viewModel.isSubmitting,
          onPressed: canSubmit ? _submitCheckIn : null,
        ),
      ],
    );
  }

  Widget _buildCheckedIn(
    BuildContext context,
    AttendanceViewModel viewModel,
    Attendance today,
  ) {
    final type = AttendanceTypeX.fromApiValue(today.attendanceType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(type.icon, color: AppColors.moduleAttendance),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.attendanceCheckedInTitle,
                    style: AppTextStyles.subHeading,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('${AppStrings.attendanceFieldWorkMode}: ${type.label}'),
              const SizedBox(height: 4),
              Text(
                '${AppStrings.attendanceFieldCheckInTime}: '
                '${_formatTime(today.inTime)}',
              ),
              if (today.locationName != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${AppStrings.attendanceLocationLabel}: '
                  '${LocationHelper.trimTrailingAfterCountry(today.locationName)}',
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Date: ${DateFormatter.format(today.attendanceDate)}',
                style: TextStyle(color: AppColors.textSecondaryFor(context)),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDimensions.sectionSpacing),
        if (!_isCheckingOut)
          AppButton(
            text: AppStrings.attendanceCheckOutButton,
            onPressed: () => _startCheckOut(today),
          )
        else
          _buildCheckOutForm(context, viewModel),
      ],
    );
  }

  Widget _buildCheckOutForm(BuildContext context, AttendanceViewModel viewModel) {
    final canSubmit = _checkOutType != null &&
        (_checkOutLocationResult?.isSuccess ?? false) &&
        !viewModel.isSubmitting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          AppStrings.checkInFieldType,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppDimensions.cardSpacing),
        Wrap(
          spacing: 12,
          children: [
            for (final type in AttendanceType.values)
              ChoiceChip(
                label: Text(type.label),
                avatar: Icon(type.icon, size: 18),
                selected: _checkOutType == type,
                onSelected: (_) => setState(() => _checkOutType = type),
              ),
          ],
        ),
        const SizedBox(height: AppDimensions.sectionSpacing),
        const Text(
          AppStrings.attendanceLocationLabel,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppDimensions.cardSpacing),
        LocationStatusCard(
          isLoading: _isLoadingCheckOutLocation,
          result: _checkOutLocationResult,
          onRetry: _fetchCheckOutLocation,
        ),
        const SizedBox(height: AppDimensions.sectionSpacing),
        AppButton(
          text: AppStrings.attendanceCheckOutButton,
          isLoading: viewModel.isSubmitting,
          onPressed: canSubmit ? _submitCheckOut : null,
        ),
      ],
    );
  }

  Widget _buildCompleted(BuildContext context, Attendance today) {
    final type = AttendanceTypeX.fromApiValue(today.attendanceType);
    final checkOutType = today.checkOutAttendanceType != null
        ? AttendanceTypeX.fromApiValue(today.checkOutAttendanceType)
        : null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.statusActive),
              const SizedBox(width: 8),
              Text(
                AppStrings.attendanceCompletedTitle,
                style: AppTextStyles.subHeading,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${AppStrings.attendanceFieldWorkMode}: ${type.label}'),
          const SizedBox(height: 4),
          Text(
            '${AppStrings.attendanceFieldCheckInTime}: '
            '${_formatTime(today.inTime)}',
          ),
          if (today.locationName != null) ...[
            const SizedBox(height: 4),
            Text(
              '${AppStrings.attendanceFieldCheckInLocation}: '
              '${LocationHelper.trimTrailingAfterCountry(today.locationName)}',
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${AppStrings.attendanceFieldCheckOutTime}: '
            '${_formatTime(today.outTime!)}',
          ),
          if (checkOutType != null) ...[
            const SizedBox(height: 4),
            Text('${AppStrings.attendanceFieldWorkMode}: ${checkOutType.label}'),
          ],
          if (today.checkOutLocationName != null) ...[
            const SizedBox(height: 4),
            Text(
              '${AppStrings.attendanceFieldCheckOutLocation}: '
              '${LocationHelper.trimTrailingAfterCountry(today.checkOutLocationName)}',
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Date: ${DateFormatter.format(today.attendanceDate)}',
            style: TextStyle(color: AppColors.textSecondaryFor(context)),
          ),
        ],
      ),
    );
  }
}
