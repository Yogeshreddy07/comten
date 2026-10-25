import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/auth/model/api_result.dart';
import 'package:frontend/features/projects/model/project_list_item.dart';
import 'package:frontend/features/projects/repository/project_repository.dart';
import 'package:frontend/features/projects/viewmodel/project_view_model.dart';
import 'package:frontend/features/modules/model/module_summary.dart';
import 'package:frontend/features/modules/repository/module_repository.dart';
import 'package:frontend/features/modules/viewmodel/module_view_model.dart';
import 'package:frontend/features/activities/model/activity.dart';
import 'package:frontend/features/activities/repository/activity_repository.dart';
import 'package:frontend/features/activities/viewmodel/activity_view_model.dart';
import 'package:frontend/features/projects/model/create_project_request.dart';
import 'package:frontend/features/projects/model/project_summary.dart';
import 'package:frontend/features/projects/viewmodel/create_project_view_model.dart';

class Projects extends ProjectRepository {
  int reads = 0;
  bool pending = false;
  @override
  Future<ApiResult> getProjects({bool? active, bool? hasInProgressModule, bool force = false}) async {
    reads++;
    return ApiResult(success: true, message: '', data: [
      const ProjectListItem(id: 1, projectCode: 'P1', projectName: 'Alpha',
          isActive: true, moduleCount: 2, status: 'IN_PROGRESS'),
      const ProjectListItem(id: 2, projectCode: 'P2', projectName: 'Beta',
          isActive: true, moduleCount: 1, status: 'IN_PROGRESS'),
    ]);
  }
  @override
  Future<ApiResult> deactivateProject(int id) async =>
      ApiResult(success: true, message: '', data: {'active': pending});
  @override
  Future<ApiResult> activateProject(int id) async =>
      ApiResult(success: true, message: '', data: {'active': true});
}

class Modules extends ModuleRepository {
  int reads = 0;
  @override
  Future<ApiResult> getModuleDetails(int id) async {
    reads++;
    return ApiResult(
      success: true, message: '', data: ModuleSummary.fromJson({
        'id': id, 'projectId': 1, 'moduleName': 'Design', 'status': 'INACTIVE'}));
  }
  @override
  Future<ApiResult> activateModule(int id) async =>
      ApiResult(success: true, message: '', data: {'active': true, 'status': 'ON_HOLD'});
}

class Creation extends Projects {
  @override
  Future<ApiResult> submitProject(CreateProjectRequest request) async =>
      ApiResult(success: true, message: '', data: ProjectSummary.fromJson({
        'id': 1, 'projectName': 'Project', 'modules': [
          {'id': 10, 'projectId': 1, 'moduleName': 'Design',
            'members': [{'userId': 4, 'name': 'Employee'}],
            'billableActivities': [{'id': 1, 'name': 'Design', 'active': true}]}
        ]}));
}

class Activities extends ActivityRepository {
  @override
  Future<ApiResult> getActivities() async => ApiResult(success: true, message: '', data: [
    const Activity(id: 1, name: 'Active', active: true),
    const Activity(id: 2, name: 'Retired', active: false),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('confirmed deactivation reorders list without fetching every project', () async {
    final repository = Projects();
    final model = ProjectViewModel(repository: repository);
    await model.fetchProjects();
    await model.deactivateProject(1);
    expect(repository.reads, 1);
    expect(model.projects.map((p) => p.id), [2, 1]);
    expect(model.projects.last.isActive, false);
    expect(model.projects.last.moduleCount, 0);
    await model.activateProject(1);
    expect(repository.reads, 1);
    expect(model.projects.singleWhere((p) => p.id == 1).status, 'NOT_STARTED');
    model.dispose();
  });
  test('pending billing approval leaves project active', () async {
    final repository = Projects()..pending = true;
    final model = ProjectViewModel(repository: repository);
    await model.fetchProjects();
    await model.deactivateProject(1);
    expect(model.projects.first.isActive, true);
    expect(model.projects.first.moduleCount, 2);
    model.dispose();
  });
  test('module activation displays the returned lifecycle status', () async {
    final model = ModuleViewModel(repository: Modules());
    await model.fetchModuleDetails(1);
    await model.activateModule(1);
    expect(model.selectedModule!.status, 'ON_HOLD');
    model.dispose();
  });
  test('retired activities cannot be offered by a cached picker response', () async {
    final model = ActivityViewModel(repository: Activities());
    await model.fetchActivities();
    expect(model.activities.map((a) => a.id), [1]);
    model.dispose();
  });
  test('creation uses returned members and activities without a second request', () async {
    final modules = Modules();
    final model = CreateProjectViewModel(projectRepository: Creation(), moduleRepository: modules)
      ..setNumberOfFloorsText('2')..setAreaText('500');
    expect(await model.submit(), true);
    expect(modules.reads, 0);
    expect(model.createdModule!.memberNames, ['Employee']);
    expect(model.createdModule!.billableActivities.single.name, 'Design');
    model.dispose();
  });
}
