import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class AppDropdown<T> extends StatelessWidget {
  final String label;
  final IconData? icon;
  final T? value;
  final List<T> items;
  final String Function(T item) itemLabel;
  final void Function(T? value) onChanged;
  final String? Function(T? value)? validator;
  final String emptyHint;

  /// Whether to show the dropdown's built-in down-arrow indicator. Defaults
  /// to true (unchanged behavior); callers rendering a read-only instance of
  /// this dropdown (e.g. Captain's Billing Management view) can pass false
  /// so the field doesn't visually imply it's editable.
  final bool showDropdownIcon;

  const AppDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.icon,
    this.value,
    this.validator,
    this.emptyHint = 'No options available',
    this.showDropdownIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).primaryColor,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 18,
      ),
    );

    if (items.isEmpty) {
      return InputDecorator(
        decoration: decoration.copyWith(
          enabled: false,
        ),
        child: Text(
          emptyHint,
          style: TextStyle(color: AppColors.textSecondaryFor(context)),
        ),
      );
    }

    // DropdownButtonFormField asserts that a non-null value must be present
    // among items; fall back to unselected instead of crashing if the
    // current value isn't (yet) in the list, e.g. teams still loading.
    final matchedValue = items.contains(value) ? value : null;

    return DropdownButtonFormField<T>(
      initialValue: matchedValue,
      decoration: decoration,
      isExpanded: true,
      items: items
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              // Long labels (project/module names) truncate with "..."
              // instead of overflowing the closed field or the menu row.
              child: Text(
                itemLabel(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: validator,
      icon: showDropdownIcon ? null : const SizedBox.shrink(),
    );
  }
}
