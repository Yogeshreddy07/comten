import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/enums/project_status.dart';
import '../../../shared/widgets/app_card.dart';
import '../model/project_list_item.dart';

enum ProjectCardAction { edit, deactivate, activate, delete }

class ProjectCard extends StatelessWidget {
  final ProjectListItem project;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;
  final VoidCallback onActivate;
  final VoidCallback onDelete;

  const ProjectCard({
    super.key,
    required this.project,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
    required this.onDeactivate,
    required this.onActivate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.projectName,
                      style: AppTextStyles.subHeading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${project.projectCode}',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: ProjectStatusX.fromApiValue(project.status)),
              if (canManage)
                PopupMenuButton<ProjectCardAction>(
                  onSelected: (action) {
                    switch (action) {
                      case ProjectCardAction.edit:
                        onEdit();
                        break;
                      case ProjectCardAction.deactivate:
                        onDeactivate();
                        break;
                      case ProjectCardAction.activate:
                        onActivate();
                        break;
                      case ProjectCardAction.delete:
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (project.isActive) ...[
                      const PopupMenuItem(
                        value: ProjectCardAction.edit,
                        child: Text('Edit'),
                      ),
                      const PopupMenuItem(
                        value: ProjectCardAction.deactivate,
                        child: Text('Deactivate'),
                      ),
                    ] else
                      const PopupMenuItem(
                        value: ProjectCardAction.activate,
                        child: Text('Activate'),
                      ),
                    const PopupMenuItem(
                      value: ProjectCardAction.delete,
                      child: Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.widgets_outlined,
                  size: 16, color: AppColors.textSecondaryFor(context)),
              const SizedBox(width: 6),
              Text(
                project.moduleCount == 1
                    ? '1 module'
                    : '${project.moduleCount} modules',
                style: TextStyle(color: AppColors.textSecondaryFor(context)),
              ),
              if (project.clientId != null && project.clientId!.isNotEmpty) ...[
                const SizedBox(width: 12),
                Icon(Icons.badge_outlined,
                    size: 15, color: AppColors.textSecondaryFor(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    project.clientId!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ProjectStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: status.color,
        ),
      ),
    );
  }
}
