import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/snackbar_util.dart';
import '../../../shared/constants/app_dimensions.dart';
import '../../../shared/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../viewmodel/create_project_view_model.dart';
import '../widgets/estimated_duration_input.dart';
import '../widgets/review_summary_card.dart';
import 'project_success_screen.dart';

/// Read-only summary of everything entered on [CreateProjectScreen], shown
/// before the API call actually fires. "Edit" just pops back to the still-
/// alive Create screen (same [CreateProjectViewModel] instance, so nothing
/// is lost); "Confirm" is the only action that calls the backend.
class ReviewProjectScreen extends StatelessWidget {
  const ReviewProjectScreen({super.key});

  Future<void> _confirm(
    BuildContext context,
    CreateProjectViewModel viewModel,
  ) async {
    final success = await viewModel.submit();
    if (!context.mounted) return;

    if (success) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          // Same reasoning as CreateProjectScreen -> ReviewProjectScreen:
          // re-provide the instance explicitly for the newly-pushed route.
          builder: (_) => ChangeNotifierProvider.value(
            value: viewModel,
            child: const ProjectSuccessScreen(),
          ),
        ),
      );
    } else {
      SnackbarUtil.showError(
        context,
        viewModel.submitError ?? 'Failed to create project',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CreateProjectViewModel>();
    final employees = viewModel.selectedEmployees;
    final teamLeader = viewModel.teamLeader;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.reviewProjectTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReviewSummarySection(
                title: AppStrings.createProjectSectionInformation,
                rows: viewModel.isNewProject
                    ? [
                        ReviewDetailRow(
                          AppStrings.createProjectFieldClientId,
                          viewModel.clientId.isEmpty ? '-' : viewModel.clientId,
                        ),
                        ReviewDetailRow(
                          AppStrings.createProjectFieldProjectName,
                          viewModel.projectName,
                        ),
                        ReviewDetailRow(
                          AppStrings.createProjectFieldProjectId,
                          viewModel.projectCode,
                        ),
                      ]
                    : [
                        ReviewDetailRow(
                          AppStrings.createProjectFieldExistingProject,
                          viewModel.existingProject != null
                              ? '${viewModel.existingProject!.projectName} '
                                  '(${viewModel.existingProject!.projectCode})'
                              : '-',
                        ),
                      ],
              ),
              const SizedBox(height: AppDimensions.sectionSpacing),
              ReviewSummarySection(
                title: AppStrings.createProjectSectionModule,
                rows: [
                  ReviewDetailRow(
                    AppStrings.createProjectFieldModuleName,
                    viewModel.moduleName,
                  ),
                  ReviewDetailRow(
                    AppStrings.createProjectFieldBuildingClassification,
                    viewModel.buildingClassification,
                  ),
                  ReviewDetailRow(
                    AppStrings.createProjectFieldStructureClassification,
                    viewModel.structureClassification,
                  ),
                  ReviewDetailRow(
                    AppStrings.createProjectFieldNumberOfFloors,
                    viewModel.numberOfFloorsText,
                  ),
                  ReviewDetailRow(
                    AppStrings.createProjectFieldArea,
                    viewModel.areaText,
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.sectionSpacing),
              ReviewSummarySection(
                title: AppStrings.createProjectSectionTeam,
                rows: [
                  ReviewDetailRow(
                    AppStrings.createProjectFieldTeamLeader,
                    teamLeader != null
                        ? '${teamLeader.name} (${teamLeader.employeeCode})'
                        : '-',
                  ),
                  ReviewDetailRow(
                    AppStrings.createProjectFieldEmployees,
                    employees.isEmpty
                        ? '-'
                        : employees.map((employee) => employee.name).join(', '),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.sectionSpacing),
              ReviewSummarySection(
                title: AppStrings.dashboardModuleActivities,
                rows: [
                  ReviewDetailRow(
                    AppStrings.billableActivitiesLabel,
                    viewModel.selectedBillableActivities.isEmpty
                        ? '-'
                        : viewModel.selectedBillableActivities
                            .map((a) => a.name)
                            .join(', '),
                  ),
                  ReviewDetailRow(
                    AppStrings.nonBillableActivitiesLabel,
                    viewModel.selectedNonBillableActivities.isEmpty
                        ? '-'
                        : viewModel.selectedNonBillableActivities
                            .map((a) => a.name)
                            .join(', '),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.sectionSpacing),
              ReviewSummarySection(
                title: AppStrings.createProjectSectionTimeline,
                rows: [
                  ReviewDetailRow(
                    AppStrings.createProjectFieldStartDate,
                    DateFormatter.formatNullable(viewModel.startDate) ?? '-',
                  ),
                  ReviewDetailRow(
                    AppStrings.createProjectFieldEndDate,
                    DateFormatter.formatNullable(viewModel.endDate) ?? '-',
                  ),
                  ReviewDetailRow(
                    AppStrings.createProjectFieldEstimatedHours,
                    EstimatedDurationInput.formatDisplay(
                      viewModel.hoursText,
                      viewModel.minutesText,
                      viewModel.secondsText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.sectionSpacing),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: AppStrings.reviewProjectEditButton,
                      outlined: true,
                      onPressed: viewModel.isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.cardSpacing),
                  Expanded(
                    child: AppButton(
                      text: AppStrings.reviewProjectConfirmButton,
                      isLoading: viewModel.isSubmitting,
                      onPressed: viewModel.isSubmitting
                          ? null
                          : () => _confirm(context, viewModel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
