import 'package:flutter/material.dart';

/// Shared Edit/Deactivate/Activate(/Delete) action row - used by both
/// [ProjectDetailsScreen] and [ModuleDetailsScreen]. While active, shows
/// Edit + Deactivate; once inactive, shows Activate instead (no Edit) -
/// [onDelete] is always available when supplied. A cancelled module (see
/// [isCancelled]) can only be viewed or deleted - it can't be edited, and
/// there's no way to "restore" it back out of Cancelled - so it shows only
/// Delete, overriding every other button regardless of [isActive].
class ProjectActionBar extends StatelessWidget {
  final bool isActive;
  final bool isCancelled;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;
  final VoidCallback onActivate;
  final VoidCallback? onDelete;

  const ProjectActionBar({
    super.key,
    this.isActive = true,
    this.isCancelled = false,
    required this.onEdit,
    required this.onDeactivate,
    required this.onActivate,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;

    if (isCancelled) {
      return Row(
        children: [
          if (onDelete != null)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: errorColor,
                  side: BorderSide(color: errorColor),
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
              ),
            ),
        ],
      );
    }

    // Active row's OutlinedButtons trade the theme's default horizontal
    // padding for a tighter one, freeing real width across all three
    // buttons; "Deactivate" (the longest label, and the one that was
    // wrapping to two lines at equal thirds) also gets a larger flex share
    // than Edit/Delete. The inactive (Activate + Delete) row is untouched -
    // it was never the one wrapping and has plenty of room already.
    const activeButtonPadding = EdgeInsets.symmetric(horizontal: 8);

    return Row(
      children: [
        if (isActive) ...[
          Expanded(
            flex: 3,
            child: OutlinedButton.icon(
              onPressed: onEdit,
              style: OutlinedButton.styleFrom(padding: activeButtonPadding),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: OutlinedButton.icon(
              onPressed: onDeactivate,
              style: OutlinedButton.styleFrom(
                foregroundColor: errorColor,
                side: BorderSide(color: errorColor),
                padding: activeButtonPadding,
              ),
              icon: const Icon(Icons.block_outlined, size: 18),
              label: const Text('Deactivate'),
            ),
          ),
        ] else ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onActivate,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Activate'),
            ),
          ),
        ],
        if (onDelete != null) ...[
          const SizedBox(width: 12),
          Expanded(
            flex: isActive ? 3 : 1,
            child: OutlinedButton.icon(
              onPressed: onDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: errorColor,
                side: BorderSide(color: errorColor),
                padding: isActive ? activeButtonPadding : null,
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
          ),
        ],
      ],
    );
  }
}
