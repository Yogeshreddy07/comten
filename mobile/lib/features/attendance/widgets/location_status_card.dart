import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/location_helper.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_card.dart';

/// Shows the current state of capturing GPS coordinates for Check-in /
/// Check-out - loading, captured, or a specific failure message with a
/// Retry action.
class LocationStatusCard extends StatelessWidget {
  final bool isLoading;
  final LocationResult? result;
  final VoidCallback onRetry;

  const LocationStatusCard({
    super.key,
    required this.isLoading,
    required this.result,
    required this.onRetry,
  });

  String _failureMessage(LocationFailure failure) {
    switch (failure) {
      case LocationFailure.serviceDisabled:
        return AppStrings.attendanceLocationServiceDisabled;
      case LocationFailure.permissionDenied:
        return AppStrings.attendanceLocationPermissionDenied;
      case LocationFailure.permissionDeniedForever:
        return AppStrings.attendanceLocationPermissionDeniedForever;
      case LocationFailure.failed:
        return AppStrings.attendanceLocationFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const AppCard(
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            SizedBox(width: 14),
            Expanded(child: Text(AppStrings.attendanceLocationCapturing)),
          ],
        ),
      );
    }

    final current = result;
    if (current != null && current.isSuccess) {
      // The place name is resolved server-side once these coordinates reach the backend (see
      // GeocodingService) - not available yet to show here, so this is just a captured/not
      // state, same as the loading/failure branches below.
      return const AppCard(
        child: Row(
          children: [
            Icon(Icons.location_on, color: AppColors.statusActive),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                AppStrings.attendanceLocationCaptured,
                style: TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final failure = current?.failure;
    final message = failure != null
        ? _failureMessage(failure)
        : AppStrings.attendanceLocationFailed;
    // Retrying can't help when the fix lives in system settings - send the
    // user there instead; the screen re-captures location on resume.
    final opensSettings = LocationHelper.needsSettings(failure);

    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.location_off_outlined, color: AppColors.statusCancelled),
          const SizedBox(width: 14),
          Expanded(child: Text(message)),
          TextButton(
            onPressed: opensSettings
                ? () => LocationHelper.openSettingsFor(failure!)
                : onRetry,
            child: Text(opensSettings
                ? AppStrings.attendanceLocationOpenSettings
                : AppStrings.attendanceLocationRetry),
          ),
        ],
      ),
    );
  }
}
