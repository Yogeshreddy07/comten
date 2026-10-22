import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/utils/navigation_guard.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../viewmodel/create_project_view_model.dart';
import '../widgets/review_summary_card.dart';

/// Confirms the module the backend actually created - reads
/// [CreateProjectViewModel.createdModule] (the server's `ModuleResponse`),
/// not the raw form input, so this reflects what was truly persisted.
/// One-way screen: back navigation is disabled, "Back to Projects" is the
/// only way out.
class ProjectSuccessScreen extends StatelessWidget {
  const ProjectSuccessScreen({super.key});

  void _backToProjects(BuildContext context) {
    if (!context.canPushRoute) return;
    // This screen replaced ReviewProjectScreen via pushReplacement, so the
    // stack directly below is CreateProjectScreen, then the Projects list -
    // popping twice returns to the list.
    Navigator.of(context)
      ..pop()
      ..pop();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CreateProjectViewModel>();
    final module = viewModel.createdModule;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.screenPadding),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: AppDimensions.sectionSpacing),
                        Icon(
                          Icons.check_circle,
                          size: 96,
                          color: AppColors.statusActive,
                        ),
                        const SizedBox(height: AppDimensions.cardSpacing),
                        Text(
                          viewModel.isNewProject
                              ? AppStrings.projectSuccessTitle
                              : AppStrings.moduleSuccessTitle,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.heading.copyWith(fontSize: 22),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          viewModel.isNewProject
                              ? AppStrings.projectSuccessSubtitle
                              : AppStrings.moduleSuccessSubtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondaryFor(context),
                          ),
                        ),
                        const SizedBox(height: AppDimensions.sectionSpacing),
                        if (module != null)
                          Column(
                            children: [
                              ReviewSummarySection(
                                title:
                                    AppStrings.createProjectSectionInformation,
                                rows: [
                                  ReviewDetailRow(
                                    AppStrings.createProjectFieldClientId,
                                    viewModel.createdClientId.isEmpty
                                        ? '-'
                                        : viewModel.createdClientId,
                                  ),
                                  ReviewDetailRow(
                                    AppStrings.createProjectFieldProjectName,
                                    module.projectName,
                                  ),
                                  ReviewDetailRow(
                                    AppStrings.createProjectFieldProjectId,
                                    module.projectCode,
                                  ),
                                  ReviewDetailRow(
                                    AppStrings.createProjectFieldModuleName,
                                    module.moduleName,
                                  ),
                                ],
                              ),
                              const SizedBox(
                                height: AppDimensions.sectionSpacing,
                              ),
                              ReviewSummarySection(
                                title: AppStrings.createProjectSectionTeam,
                                rows: [
                                  ReviewDetailRow(
                                    AppStrings.createProjectFieldTeamLeader,
                                    module.teamLeadName ?? '-',
                                  ),
                                  ReviewDetailRow(
                                    AppStrings.createProjectFieldEmployees,
                                    module.memberNames.isEmpty
                                        ? '-'
                                        : module.memberNames.join(', '),
                                  ),
                                ],
                              ),
                              const SizedBox(
                                height: AppDimensions.sectionSpacing,
                              ),
                              ReviewSummarySection(
                                title: AppStrings.createProjectSectionTimeline,
                                rows: [
                                  ReviewDetailRow(
                                    AppStrings.createProjectFieldStartDate,
                                    DateFormatter.formatNullable(
                                          module.startDate,
                                        ) ??
                                        '-',
                                  ),
                                  ReviewDetailRow(
                                    AppStrings.createProjectFieldEndDate,
                                    DateFormatter.formatNullable(
                                          module.endDate,
                                        ) ??
                                        '-',
                                  ),
                                  ReviewDetailRow(
                                    AppStrings.createProjectFieldEstimatedHours,
                                    DurationFormatter.humanReadable(module.estimatedMinutes) ??
                                        '0 minutes',
                                  ),
                                ],
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppDimensions.sectionSpacing),
                AppButton(
                  text: AppStrings.projectSuccessBackButton,
                  onPressed: () => _backToProjects(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
