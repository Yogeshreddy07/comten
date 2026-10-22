import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Mirrors the backend's `com.comten.enums.ProjectStatus` exactly - values
/// are sent/received as these upper-snake-case names (see
/// `ProjectServiceImpl#resolveStatus` / `ProjectStatus.isValid`).
enum ProjectStatus {
  notStarted,
  inProgress,
  completed,
  cancelled,
  inactive,
}

extension ProjectStatusX on ProjectStatus {
  String get label {
    switch (this) {
      case ProjectStatus.notStarted:
        return 'Not Started';
      case ProjectStatus.inProgress:
        return 'In Progress';
      case ProjectStatus.completed:
        return 'Completed';
      case ProjectStatus.cancelled:
        return 'Cancelled';
      case ProjectStatus.inactive:
        return 'Inactive';
    }
  }

  String get apiValue {
    switch (this) {
      case ProjectStatus.notStarted:
        return 'NOT_STARTED';
      case ProjectStatus.inProgress:
        return 'IN_PROGRESS';
      case ProjectStatus.completed:
        return 'COMPLETED';
      case ProjectStatus.cancelled:
        return 'CANCELLED';
      case ProjectStatus.inactive:
        return 'INACTIVE';
    }
  }

  Color get color {
    switch (this) {
      case ProjectStatus.notStarted:
        return AppColors.statusNotStarted;
      case ProjectStatus.inProgress:
        return AppColors.statusActive;
      case ProjectStatus.completed:
        return AppColors.statusCompleted;
      case ProjectStatus.cancelled:
        return AppColors.statusCancelled;
      case ProjectStatus.inactive:
        return AppColors.statusInactive;
    }
  }

  /// Sort priority for the Projects list: In Progress first, then Not
  /// Started, then Completed, with Inactive always last. Only In Progress,
  /// Not Started, Completed and Inactive are ever returned as a *project's*
  /// computed status (see `ProjectStatusCalculator` on the backend), but
  /// Cancelled is handled defensively so a stray value never crashes the
  /// sort.
  int get projectSortPriority {
    switch (this) {
      case ProjectStatus.inProgress:
        return 0;
      case ProjectStatus.notStarted:
        return 1;
      case ProjectStatus.completed:
        return 2;
      case ProjectStatus.cancelled:
        return 0;
      case ProjectStatus.inactive:
        return 3;
    }
  }

  static ProjectStatus fromApiValue(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'NOT_STARTED':
        return ProjectStatus.notStarted;
      case 'IN_PROGRESS':
        return ProjectStatus.inProgress;
      case 'COMPLETED':
        return ProjectStatus.completed;
      case 'CANCELLED':
        return ProjectStatus.cancelled;
      case 'INACTIVE':
        return ProjectStatus.inactive;
      default:
        return ProjectStatus.notStarted;
    }
  }
}
