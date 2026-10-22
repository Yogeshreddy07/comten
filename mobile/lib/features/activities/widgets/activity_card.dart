import 'package:flutter/material.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/app_card.dart';
import '../model/activity.dart';

/// A single row on [ActivityListScreen] - the activity's name plus a delete
/// action. The whole screen is already Project Controller-only (see
/// [ActivityListScreen]'s doc comment), so no extra role check is needed here.
class ActivityCard extends StatelessWidget {
  final Activity activity;
  final VoidCallback? onDelete;

  const ActivityCard({super.key, required this.activity, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.checklist_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              activity.name,
              style: AppTextStyles.subHeading,
            ),
          ),
          if (onDelete != null)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
        ],
      ),
    );
  }
}
