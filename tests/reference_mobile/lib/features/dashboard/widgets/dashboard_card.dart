import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/widgets/app_card.dart';
import '../model/dashboard_item.dart';

enum DashboardCardLayout { grid, list }

class DashboardModuleCard extends StatelessWidget {
  final DashboardModuleEntry entry;
  final VoidCallback onTap;
  final DashboardCardLayout layout;

  const DashboardModuleCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.layout = DashboardCardLayout.grid,
  });

  Widget _iconSquare() {
    return Container(
      width: AppDimensions.cardIconSquareSize,
      height: AppDimensions.cardIconSquareSize,
      decoration: BoxDecoration(
        color: entry.module.accentColor,
        borderRadius: BorderRadius.circular(AppDimensions.cardIconSquareRadius),
      ),
      child: Icon(
        entry.module.icon,
        size: AppDimensions.moduleIconSize * 0.75,
        color: AppColors.darkText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = AppTextStyles.cardTitle.copyWith(
      color: AppColors.dashboardTextFor(context),
    );
    final descriptionStyle = AppTextStyles.body.copyWith(
      fontSize: 12,
      color: AppColors.dashboardTextMutedFor(context),
    );
    final chevron = Icon(
      Icons.chevron_right,
      size: AppDimensions.cardChevronSize,
      color: AppColors.dashboardChevronFor(context),
    );

    if (layout == DashboardCardLayout.list) {
      return AppCard(
        onTap: onTap,
        color: AppColors.dashboardSurfaceFor(context),
        elevation: 0,
        child: Row(
          children: [
            _iconSquare(),
            const SizedBox(width: AppDimensions.listCardIconTextSpacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title, style: titleStyle),
                  const SizedBox(height: 2),
                  Text(
                    entry.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: descriptionStyle,
                  ),
                ],
              ),
            ),
            chevron,
          ],
        ),
      );
    }

    return AppCard(
      onTap: onTap,
      color: AppColors.dashboardSurfaceFor(context),
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconSquare(),
              const Spacer(),
              chevron,
            ],
          ),
          const SizedBox(height: AppDimensions.cardContentSpacing),
          Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
          const SizedBox(height: 2),
          Text(
            entry.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: descriptionStyle,
          ),
        ],
      ),
    );
  }
}
