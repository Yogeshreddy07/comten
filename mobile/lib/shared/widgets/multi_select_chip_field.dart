import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Generic "chips + add" multi-select display field - the same shape as
/// `EmployeesPickerField` (see `features/projects/widgets/team_assignment_fields.dart`),
/// parameterized over any item type [T] so it can be reused for pickers
/// like Billable/Non-Billable Activities without duplicating the layout.
class MultiSelectChipField<T> extends StatelessWidget {
  final String label;
  final String addButtonLabel;
  final String emptyText;
  final List<T> selected;
  final String Function(T item) itemLabel;
  final String? errorText;
  final bool enabled;
  final String? disabledHintText;
  final VoidCallback onAdd;
  final void Function(T item) onRemove;

  const MultiSelectChipField({
    super.key,
    required this.label,
    required this.addButtonLabel,
    required this.emptyText,
    required this.selected,
    required this.itemLabel,
    required this.errorText,
    this.enabled = true,
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
                label,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: enabled ? onAdd : null,
              icon: const Icon(Icons.add),
              label: Text(addButtonLabel),
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
              emptyText,
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in selected)
                Chip(
                  label: Text(itemLabel(item)),
                  onDeleted: () => onRemove(item),
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
