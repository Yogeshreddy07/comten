import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:frontend/core/network/api_service.dart';
import 'package:frontend/core/utils/location_helper.dart';

/// Resume only the saved synthetic workflow; credentials stay in the USB broker.
Future<Map<String,dynamic>> runPhysicalWorkflow(Map fixture,Future<void> Function(String) check) async {
 final api=ApiService();
 const broker='http://127.0.0.1:8011';
 Map data(http.Response response){
  if(response.statusCode!=200)throw StateError('Native workflow operation rejected (${response.statusCode})');
  return jsonDecode(response.body)['data'] as Map;
 }
 Future<void> login(String code) async{
  data(await api.post('/auth/login',{'employeeCode':code,'password':fixture[code]['password']}));
 }
 final saved=jsonDecode((await http.get(Uri.parse('$broker/workflow'))).body);
 if(saved==null)throw StateError('Saved Android workflow required; do not recreate completed steps');
 final state=Map<String,dynamic>.from(saved as Map);
 Future<void> save(String stage) async{
  state['stage']=stage;
  await http.post(Uri.parse('$broker/workflow'),body:jsonEncode(state));
 }
 await check('Native E2E: resume existing synthetic workflow at ${state['stage']}');
 await api.post('/auth/logout',{});
 data(await api.post('/auth/login',{'employeeCode':state['employeeCode'],'password':state['password']}));
 if(state['stage']=='worklogSubmitted'){
  var checkout=await LocationHelper.getCurrentLocation();
  for(var retry=0;!checkout.isSuccess && retry<2;retry++){
   await check('Native E2E: checkout location acquisition ${checkout.failure?.name}; bounded retry');
   await Future<void>.delayed(const Duration(seconds:2));
   checkout=await LocationHelper.getCurrentLocation();
  }
  if(!checkout.isSuccess)throw StateError('Fresh checkout GPS unavailable: ${checkout.failure?.name}');
  final attendance=data(await api.post('/attendance/check-out',{'latitude':checkout.latitude,'longitude':checkout.longitude,'attendanceType':'AT_OFFICE'}));
  if(attendance['outTime']==null)throw StateError('Checkout missing');
  await save('checkedOut');
  await check('Native E2E: fresh real GPS attendance checkout');
 }
 await api.post('/auth/logout',{});await login('TL001');
 final team=jsonDecode((await api.get('/attendance/team')).body)['data'] as List;
 if(!team.any((row)=>row['employeeId']==state['employeeId']))throw StateError('Team attendance missing');
 var log=data(await api.get('/work-logs/${state['worklogId']}'));
 if(log['approvalStatus']!='APPROVED')log=data(await api.put('/work-logs/${state['worklogId']}/approve',{}));
 if(log['approvalStatus']!='APPROVED')throw StateError('Approval missing');
 if(state['extraWorklogId']!=null){
  var extra=data(await api.get('/work-logs/${state['extraWorklogId']}'));
  if(extra['approvalStatus']!='APPROVED')extra=data(await api.put('/work-logs/${state['extraWorklogId']}/approve',{}));
  if(extra['approvalStatus']!='APPROVED')throw StateError('UI work-log approval missing');
 }
 await check('Native E2E: assigned leader sees attendance and approves timesheet');
 final minutes=1+((state['extraWorklogSeconds'] as int? ?? 0)~/60);
 if(data(await api.get('/modules/${state['moduleId']}'))['completedMinutes']!=minutes)throw StateError('Module totals differ');
 await check('Native E2E: dashboard/module approved totals match');
 if(state['stage']=='checkedOut'){
  data(await api.post('/notifications/delay-requests',{'moduleId':state['moduleId'],'reason':'Synthetic Android schedule review'}));
  data(await api.put('/modules/${state['moduleId']}/work-stage',{'workStage':'BILLING'}));
  await save('billingSubmitted');
 }
 await api.post('/auth/logout',{});await login('PC001');
 if(state['stage']=='billingSubmitted'){
  data(await api.put('/billing/${state['moduleId']}',{'status':'INVOICE_RAISED','spocName':'Synthetic Android','remarks':'Development test only'}));
  final request=data(await api.post('/module-change-requests',{'moduleId':state['moduleId'],'proposedEstimatedMinutes':150}));
  state['changeRequestId']=request['id'];await save('budgetRequested');
 }
 await api.post('/auth/logout',{});await login('CAP001');
 if(state['stage']=='budgetRequested'){
  if(data(await api.put('/module-change-requests/${state['changeRequestId']}/approve',{}))['approvalStatus']!='APPROVED')throw StateError('Captain approval missing');
  await save('budgetApproved');
 }
 await check('Native E2E: billing and Captain budget approval commit');
 await api.post('/auth/logout',{});
 data(await api.post('/auth/login',{'employeeCode':state['employeeCode'],'password':state['password']}));
 final notifications=jsonDecode((await api.get('/notifications')).body)['data'] as List;
 if(!notifications.any((row)=>row['type']=='TIMESHEET_APPROVED'))throw StateError('Employee notification missing');
 if(data(await api.get('/work-logs/${state['worklogId']}'))['approvalStatus']!='APPROVED')throw StateError('Employee approval inconsistent');
 await check('Native E2E: employee notification and final timesheet consistent');
 await api.post('/auth/logout',{});await save('complete');
 return {for(final key in ['projectId','moduleId','employeeId','clientId','worklogId','workDate'])key:state[key],'approvedSeconds':minutes*60};
}
