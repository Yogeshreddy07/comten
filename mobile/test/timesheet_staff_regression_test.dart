import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/auth/model/api_result.dart';
import 'package:frontend/features/modules/model/module_list_item.dart';
import 'package:frontend/features/modules/repository/module_repository.dart';
import 'package:frontend/features/projects/viewmodel/status_update_view_model.dart';
import 'package:frontend/features/worklogs/model/create_work_log_request.dart';
import 'package:frontend/features/worklogs/model/work_log.dart';
import 'package:frontend/features/worklogs/repository/work_log_repository.dart';
import 'package:frontend/features/worklogs/viewmodel/work_log_view_model.dart';
import 'package:frontend/features/employees/model/employee.dart';
import 'package:frontend/features/employees/repository/employee_repository.dart';
import 'package:frontend/features/employees/viewmodel/employee_view_model.dart';
import 'package:frontend/features/employees/view/employee_list_screen.dart';
import 'package:frontend/shared/enums/user_role.dart';

class StageRepository extends ModuleRepository {
  int writes=0;
  @override
  Future<ApiResult> getCompletedLedModules() async => ApiResult(success:true,message:'',data:[
    const ModuleListItem(id:1,projectId:1,projectCode:'P1',projectName:'Project',moduleName:'Done',status:'COMPLETED',workStage:'BILLING'),
    const ModuleListItem(id:2,projectId:1,projectCode:'P1',projectName:'Project',moduleName:'Open',status:'IN_PROGRESS',workStage:'BILLING'),
    const ModuleListItem(id:3,projectId:1,projectCode:'P1',projectName:'Project',moduleName:'Paid',status:'IN_PROGRESS',workStage:'BILLING',billingStatus:'FULL_PAYMENT_RECEIVED')]);
  @override
  Future<ApiResult> updateWorkStage(int id,String stage) async {
    writes++;
    return ApiResult(success:true,message:'Updated');
  }
}

WorkLog log(int moduleId) => WorkLog.fromJson({
  'id':moduleId,'moduleId':moduleId,'projectId':1,'employeeId':4,
  'workDate':'2026-10-19','createdAt':'2026-10-19T10:00:00Z',
  'approvalStatus':'PENDING','moduleName':'Module $moduleId'});

CreateWorkLogRequest request(int moduleId) => CreateWorkLogRequest(
  moduleId:moduleId,workDate:DateTime(2026,10,19),workDone:'Design',billableDurationSeconds:900);

class LogsRepository extends WorkLogRepository {
  final rows=<WorkLog>[];
  Completer<ApiResult>? pending;
  @override
  Future<ApiResult> getMyWorkLogs({int? moduleId,String? status}) async =>
      pending!=null ? pending!.future : ApiResult(success:true,message:'',data:List<WorkLog>.of(rows));
  @override
  Future<ApiResult> submitWorkLog(CreateWorkLogRequest request) async {
    final created=log(request.moduleId);
    if(!rows.any((r)=>r.id==created.id)) rows.add(created);
    return ApiResult(success:true,message:'Submitted',data:created);
  }
}

class StaffRepository extends EmployeeRepository {
  @override
  Future<ApiResult> getEmployees({UserRole? role}) async => ApiResult(success:true,message:'',data:[
    for(final item in [(1,'CAPTAIN',UserRole.captain),(2,'PC002',UserRole.projectManager),
      (3,'TL003',UserRole.teamLeader),(4,'EMP004',UserRole.employee)])
      Employee(id:item.$1,employeeCode:item.$2,name:item.$2,phone:'',email:'',role:item.$3,isActive:true)]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('completed module is rejected immediately; open module still permits WIP',() async {
    final repository=StageRepository();
    final model=StatusUpdateViewModel(repository:repository);
    await model.fetchLedModules();
    final blocked=await model.updateWorkStage(1,'WIP');
    expect(blocked.success,false);
    expect(blocked.message,contains('already completed and cannot be moved back to WIP'));
    expect(repository.writes,0);
    expect(model.ledModules.first.workStage,'BILLING');
    expect(model.ledModules.map((m)=>m.id),[1,2]);
    expect((await model.updateWorkStage(3,'WIP')).message,contains('no longer available'));
    final repeat=await model.updateWorkStage(1,'BILLING');
    expect(repeat.success,false);
    expect(repeat.message,'This module is already in Billing.');
    expect(repository.writes,0);
    expect((await model.updateWorkStage(2,'WIP')).success,true);
    expect(repository.writes,1);
    expect((await model.updateWorkStage(2,'WIP')).message,'This module is already in WIP.');
    expect(repository.writes,1);
    model.dispose();
  });
  test('pending timesheet permits another module, survives refresh, and deduplicates retries',() async {
    final repository=LogsRepository();
    final model=WorkLogViewModel(repository:repository);
    await model.submitWorkLog(request(1));
    expect(model.loadState,WorkLogLoadState.success);
    expect((await model.submitWorkLog(request(2))).success,true);
    expect(model.workLogs.map((r)=>r.moduleId).toSet(),{1,2});
    expect(model.workLogs.every((r)=>r.approvalStatus=='PENDING'),true);
    await model.submitWorkLog(request(2));
    expect(model.workLogs.length,2);
    await model.fetchMyWorkLogs();
    expect(model.workLogs.length,2);
    model.dispose();
  });
  test('old fetch cannot erase a submitted entry',() async {
    final repository=LogsRepository()..pending=Completer<ApiResult>();
    final model=WorkLogViewModel(repository:repository);
    final refresh=model.fetchMyWorkLogs();
    await model.submitWorkLog(request(1));
    repository.pending!.complete(ApiResult(success:true,message:'',data:<WorkLog>[]));
    await refresh;
    expect(model.loadState,WorkLogLoadState.success);
    expect(model.workLogs.single.moduleId,1);
    model.dispose();
  });
  for(final controllerOnly in [false,true]) {
    testWidgets('directory role filter controllerOnly=$controllerOnly',(tester) async {
      final model=EmployeeViewModel(repository:StaffRepository());
      await tester.pumpWidget(ChangeNotifierProvider.value(value:model,child:MaterialApp(
        home:EmployeeListScreen(roleFilter:controllerOnly?UserRole.projectManager:null))));
      await tester.pumpAndSettle();
      expect(find.text('CAPTAIN'),findsNothing);
      expect(find.text('PC002'),controllerOnly?findsWidgets:findsNothing);
      expect(find.text('TL003'),controllerOnly?findsNothing:findsWidgets);
      expect(find.text('EMP004'),controllerOnly?findsNothing:findsWidgets);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    });
  }
}
