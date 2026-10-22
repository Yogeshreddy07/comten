import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:frontend/core/services/firebase_environment.dart';
import 'package:frontend/core/network/api_service.dart';
import 'package:frontend/core/services/account_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if(!FirebaseEnvironment.emulator) throw StateError('Synthetic probe requires emulators');
  try {
    await FirebaseEnvironment.initialize();
    final api=ApiService(),checks=<String>[];
    void check(bool value,String name){if(!value) throw StateError(name);checks.add(name);}
    var r=await api.post('/auth/login',{'employeeCode':'EMP001','password':'SyntheticPass123!'});
    check(r.statusCode==200,'Firebase login');
    r=await api.get('/projects');check(r.statusCode==200 && (jsonDecode(r.body)['data'] as List).any((p)=>p['id']==100),'Assigned projects');
    r=await api.get('/modules/101');check(r.statusCode==200,'Module details');
    r=await api.get('/attendance/today');check(r.statusCode==200,'Attendance read');
    if(jsonDecode(r.body)['data']==null){r=await api.post('/attendance/check-in',{'latitude':12.97,'longitude':77.59,'attendanceType':'OFFICE'});check(r.statusCode==200,'GPS attendance transaction');}
    check((await AccountCache.instance.restoreProfile('4'))?['employeeCode']=='EMP001','Hive profile restore');
    r=await api.get('/projects');check(r.statusCode==200,'Project refresh after mutation');
    await FirebaseFirestore.instance.disableNetwork();
    r=await api.get('/projects');check(r.statusCode==200,'Hive offline project read');
    await FirebaseFirestore.instance.enableNetwork();
    final day=DateTime.now().toUtc().add(const Duration(minutes:330)).toIso8601String().substring(0,10);
    r=await api.post('/work-logs',{'moduleId':101,'workDate':day,'workDone':'Synthetic browser integration work','billableDurationSeconds':3600,'nonBillableDurationSeconds':900,'billableActivityIds':[1],'nonBillableActivityIds':[2]});
    check(r.statusCode==200,'Direct Firestore timesheet submission (${r.statusCode})');
    final worklog=jsonDecode(r.body)['data'] as Map;
    r=await api.post('/auth/logout',{});check(r.statusCode==200 && AccountCache.instance.read('/projects')==null,'Logout clears cache');
    r=await api.post('/auth/login',{'employeeCode':'TL001','password':'SyntheticPass123!'});check(r.statusCode==200,'Account switch');
    r=await api.get('/attendance/team');check(r.statusCode==200 && (jsonDecode(r.body)['data'] as List).any((p)=>p['employeeId']==4),'Team attendance');
    if(worklog['approvalStatus']=='PENDING') {
      r=await api.put('/work-logs/${worklog['id']}/approve',{});
      check(r.statusCode==200,'Trusted timesheet approval (${r.statusCode})');
    }
    r=await api.get('/notifications');check(r.statusCode==200,'Recipient notifications');
    await api.post('/auth/logout',{});
    r=await api.post('/auth/login',{'employeeCode':'CAP001','password':'SyntheticPass123!'});check(r.statusCode==200,'Captain login');
    final code='PRB${DateTime.now().millisecondsSinceEpoch}';
    r=await api.post('/projects',{'projectCode':code,'projectName':'Synthetic browser project','moduleName':'Design','clientId':'PROBE','teamLeadId':3,'memberIds':[4],'estimatedMinutes':600});
    check(r.statusCode==200,'Privileged project and module creation (${r.statusCode})');
    final project=jsonDecode(r.body)['data'] as Map;
    r=await api.put('/projects/${project['id']}',{'projectName':'Edited synthetic browser project'});
    check(r.statusCode==200,'Direct Firestore project update');
    r=await api.post('/employees',{'employeeCode':code,'name':'Synthetic browser employee','email':'probe@example.invalid','phone':'9000000000','role':'EMPLOYEE'});
    check(r.statusCode==200,'Privileged employee provisioning (${r.statusCode})');
    await api.post('/auth/logout',{});
    final result='PMS_PROBE_PASS ${jsonEncode(checks)}';
    debugPrint(result);runApp(MaterialApp(home:Scaffold(body:SelectableText(result))));
  } catch(e) {
    final result='PMS_PROBE_FAIL $e';
    debugPrint(result);runApp(MaterialApp(home:Scaffold(body:SelectableText(result))));
  }
}
