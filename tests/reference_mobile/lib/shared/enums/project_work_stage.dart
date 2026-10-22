import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A Team Lead-controlled WIP/Billing toggle on a project - mirrors the
/// backend's `com.comten.enums.ProjectWorkStage` exactly. Distinct from
/// [ProjectStatus] (the Captain/Project Controller-managed project
/// lifecycle status) - only [billing] projects appear in the Project
/// Controller's Billing Status list.
enum ProjectWorkStage {
  wip,
  billing,
}

extension ProjectWorkStageX on ProjectWorkStage {
  String get label {
    switch (this) {
      case ProjectWorkStage.wip:
        return 'WIP';
      case ProjectWorkStage.billing:
        return 'Billing';
    }
  }

  String get apiValue {
    switch (this) {
      case ProjectWorkStage.wip:
        return 'WIP';
      case ProjectWorkStage.billing:
        return 'BILLING';
    }
  }

  Color get color {
    switch (this) {
      case ProjectWorkStage.wip:
        return AppColors.statusOnHold;
      case ProjectWorkStage.billing:
        return AppColors.moduleBilling;
    }
  }

  /// `value == null` means the project was created before this field
  /// existed - treated as [ProjectWorkStage.wip] (see backend
  /// `ProjectMapper#effectiveWorkStage`).
  static ProjectWorkStage fromApiValue(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'BILLING':
        return ProjectWorkStage.billing;
      default:
        return ProjectWorkStage.wip;
    }
  }
}
