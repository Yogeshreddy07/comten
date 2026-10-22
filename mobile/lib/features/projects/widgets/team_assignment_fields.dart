import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/constants/app_strings.dart';
import '../model/project_member_option.dart';

/// A single-select "picker trigger" field styled like a dropdown, used for
/// the Team Leader step of the Create/Edit Project team hierarchy. Shared
/// between [CreateProjectScreen] and [EditProjectScreen] so both present the
/// exact same team-assignment UI.
class SingleUserPickerField extends StatelessWidget {
  final String label;
  final String hintText;
  final ProjectMemberOption? value;
  final String? errorText;
  final VoidCallback onTap;

  const SingleUserPickerField({
    super.key,
    required this.label,
    required this.hintText,
    required this.value,
    required this.errorText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.supervisor_account_outlined),
          errorText: errorText,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          value != null ? '${value!.name} (${value!.employeeCode})' : hintText,
          style: value == null
              ? TextStyle(color: AppColors.textSecondaryFor(context))
              : null,
        ),
      ),
    );
  }
}

/// Multi-select "chips + add" field used for the Employees step of the
/// Create/Edit Project team hierarchy.
class EmployeesPickerField extends StatelessWidget {
  final List<ProjectMemberOption> selected;
  final String? errorText;
  final bool enabled;
  final String? disabledHintText;
  final VoidCallback onAdd;
  final void Function(ProjectMemberOption user) onRemove;

  const EmployeesPickerField({
    super.key,
    required this.selected,
    required this.errorText,
    required this.enabled,
    this.disabledHintText,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.createProjectFieldEmployees,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.add),
              label: Text(AppStrings.createProjectSelectEmployeesHint),
            ),
          ],
        ),
        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              disabledHintText ?? '',
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          )
        else if (selected.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              AppStrings.createProjectNoEmployeesSelected,
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final employee in selected)
                Chip(
                  label: Text(employee.name),
                  onDeleted: () => onRemove(employee),
                ),
            ],
          ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              errorText!,
              style: TextStyle(color: colorScheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
