import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:frontend/core/services/firebase_environment.dart';
import 'package:frontend/core/network/api_service.dart';
import 'package:frontend/features/modules/model/module_summary.dart';
import 'package:frontend/features/projects/model/project_member_option.dart';

// Protocol integration test. Credentials are supplied at runtime by the local
// test runner, never compiled into this browser artifact or written to results.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final checks=<String>[];
  void check(bool condition,String label) { if(!condition) throw StateError(label); checks.add(label); }
  try {
    if(!FirebaseEnvironment.emulator && FirebaseEnvironment.options.projectId!='crompton-pms-dev-20261015') throw StateError('Dedicated development project required');
    await FirebaseEnvironment.initialize();
    final fixture=jsonDecode((await http.get(Uri.base.resolve('/probe-fixture'))).body) as Map;
    final api=ApiService();
    Map data(http.Response r) { if(r.statusCode!=200) throw StateError('Operation rejected: ${r.statusCode} ${jsonDecode(r.body)['message']}'); return jsonDecode(r.body)['data'] as Map; }
    Future<void> login(String code) async { data(await api.post('/auth/login',Map<String,dynamic>.from(fixture[code]))); }
    await login('PC001');
    final code='JNY${DateTime.now().millisecondsSinceEpoch}';
    final employee=data(await api.post('/employees',{'employeeCode':code,'name':'Synthetic journey employee','email':'${code.toLowerCase()}@example.invalid','role':'EMPLOYEE'}));
    check(employee['temporaryPassword']!=null,'Controller creates synthetic employee');
    final project=data(await api.post('/projects',{'projectCode':code,'projectName':'Synthetic journey project','moduleName':'Design','clientId':code,'teamLeadId':3,'memberIds':[employee['id']],'estimatedMinutes':120,'billableActivityIds':[1],'nonBillableActivityIds':[2]}));
    final module=(project['modules'] as List).first as Map;
    check((module['memberIds'] as List).contains(3),'Project assignment includes team leader');
    final options=jsonDecode((await api.get('/projects/users?role=TEAM_LEADER')).body)['data'] as List;
    check(options.map((r)=>ProjectMemberOption.fromJson(Map<String,dynamic>.from(r))).any((r)=>r.id==3),'Existing assignment picker contract');
    await api.post('/auth/logout',{});
    data(await api.post('/auth/login',{'employeeCode':code,'password':employee['temporaryPassword']}));
    check(data(await api.get('/users/me'))['id']==employee['id'],'New employee authenticates');
    final detail=ModuleSummary.fromJson(Map<String,dynamic>.from(data(await api.get('/modules/${module['id']}'))));
    check(detail.members.any((m)=>m.userId==employee['id']) && detail.billableActivities.isNotEmpty,'Module screen DTO includes membership and activities');
    var attendance=data(await api.post('/attendance/check-in',{'latitude':12.97,'longitude':77.59,'attendanceType':'OFFICE','locationName':'Synthetic GPS fixture'}));
    check(attendance['inTime']!=null,'Employee checks in through direct Firestore transaction');
    check((await api.put('/modules/${module['id']}',{'moduleName':'Forbidden'})).statusCode==403,'Employee cannot mutate privileged module fields');
    data(await api.get('/modules/${module['id']}'));
    await FirebaseFirestore.instance.disableNetwork();
    check((await api.get('/modules/${module['id']}')).statusCode==200,'Encrypted module snapshot available offline');
    await FirebaseFirestore.instance.enableNetwork();
    check(data(await api.get('/users/me'))['id']==employee['id'],'Reconnection refreshes authoritative profile');
    // Real elapsed attendance, without manufacturing server timestamps.
    final started=DateTime.parse(attendance['inTime'] as String);
    final remaining=65-DateTime.now().difference(started).inSeconds;
    if(remaining>0) await Future<void>.delayed(Duration(seconds:remaining.clamp(0,60)));
    final day=DateTime.now().toUtc().add(const Duration(minutes:330)).toIso8601String().substring(0,10);
    final log=data(await api.post('/work-logs',{'moduleId':module['id'],'workDate':day,'workDone':'Synthetic complete journey','billableDurationSeconds':60,'nonBillableDurationSeconds':0,'billableActivityIds':[1],'nonBillableActivityIds':[]}));
    check(log['approvalStatus']=='PENDING','Employee submits one minute within actual attendance');
    attendance=data(await api.post('/attendance/check-out',{'latitude':12.97,'longitude':77.59,'attendanceType':'OFFICE'}));
    check(attendance['outTime']!=null,'Employee checks out');
    await api.post('/auth/logout',{});
    await login('TL001');
    final eligible=jsonDecode((await api.get('/modules/led/completed')).body)['data'] as List;
    check(eligible.any((m)=>m['id']==module['id']),'In-progress module appears in status update screen');
    final team=jsonDecode((await api.get('/attendance/team')).body)['data'] as List;
    check(team.any((r)=>r['employeeId']==employee['id']),'Assigned leader sees employee attendance');
    check(data(await api.put('/work-logs/${log['id']}/approve',{}))['approvalStatus']=='APPROVED','Assigned leader approves timesheet');
    check(data(await api.get('/modules/${module['id']}'))['completedMinutes']==1,'Approved work updates module/dashboard totals');
    check((await api.post('/notifications/delay-requests',{'moduleId':module['id'],'reason':'Synthetic schedule review'})).statusCode==200,'Leader submits delay reason');
    check((await api.put('/modules/${module['id']}/work-stage',{'workStage':'BILLING'})).statusCode==200,'Leader submits module for billing');
    await api.post('/auth/logout',{});
    await login('PC001');
    check(data(await api.put('/billing/${module['id']}',{'status':'INVOICE_RAISED','spocName':'Synthetic','remarks':'Test only'}))['status']=='INVOICE_RAISED','Controller updates billing');
    final request=data(await api.post('/module-change-requests',{'moduleId':module['id'],'proposedEstimatedMinutes':150}));
    await api.post('/auth/logout',{});
    await login('CAP001');
    check(data(await api.put('/module-change-requests/${request['id']}/approve',{}))['approvalStatus']=='APPROVED','Captain approves revised hours');
    final notifications=jsonDecode((await api.get('/notifications')).body)['data'] as List;
    check(notifications.any((n)=>n['type']=='DELAY_REQUESTED' && n['moduleId']==module['id']),'Notification retains existing delay screen deep link');
    await api.post('/auth/logout',{});
    data(await api.post('/auth/login',{'employeeCode':code,'password':employee['temporaryPassword']}));
    final received=jsonDecode((await api.get('/notifications')).body)['data'] as List;
    check(received.any((n)=>n['type']=='TIMESHEET_APPROVED'),'Employee receives approval notification');
    check(data(await api.get('/work-logs/${log['id']}'))['approvalStatus']=='APPROVED','Employee reads consistent approved timesheet');
    await api.post('/auth/logout',{});
    final result={'checks':checks,'projectId':project['id'],'moduleId':module['id'],'employeeId':employee['id'],'clientId':code,'worklogId':log['id'],'workDate':day};
    final text='PMS_JOURNEY_PASS ${jsonEncode(result)}';debugPrint(text);runApp(MaterialApp(home:Scaffold(body:SelectableText(text))));
  } catch(e) { final text='PMS_JOURNEY_FAIL $e';debugPrint(text);runApp(MaterialApp(home:Scaffold(body:SelectableText(text)))); }
}
