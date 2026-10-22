import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:frontend/main.dart' as app;
import 'package:frontend/core/network/api_service.dart';
import 'package:frontend/core/services/file_service.dart';
import 'package:frontend/core/services/push_notification_service.dart';
import 'package:frontend/core/utils/location_helper.dart';
import 'package:frontend/core/utils/secure_storage_service.dart';
import 'package:frontend/features/auth/view/login_screen.dart';
import 'package:frontend/features/auth/view/create_pin_screen.dart';
import 'package:frontend/features/auth/view/fingerprint_setup_screen.dart';
import 'native_workflow.dart';

const broker='http://127.0.0.1:8011';
void main(){
 final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 testWidgets('Physical Android development journeys',(tester) async{
  final checks=<String>[];
  final limitations=<String>[];
  Map<String,dynamic>? workflow;
  LocationResult? physicalLocation;
  var surfaceConverted=false;
  Future<T> network<T>(Future<T> Function() action) async {
   T? value;Object? failure;StackTrace? stack;
   await tester.runAsync<void>(() async {try{value=await action();}catch(e,s){failure=e;stack=s;}});
   if(failure!=null)Error.throwWithStackTrace(failure!,stack!);
   return value as T;
  }
  Future<void> directReport(String name) async{
   checks.add(name);
   await http.post(Uri.parse('$broker/stage'),body:jsonEncode({'name':name}));
  }
  Future<void> report(String name)=>network(()=>directReport(name));
  Future<void> waitFor(Finder finder,{int seconds=45}) async{
   final end=DateTime.now().add(Duration(seconds:seconds));
   while(finder.evaluate().isEmpty && DateTime.now().isBefore(end)){await tester.pump(const Duration(milliseconds:300));}
   if(finder.evaluate().isEmpty)throw StateError('Expected application control did not appear');
  }
  Future<void> tapText(String text) async{
   if(text=='Logout'){
    await waitFor(find.text('My attachments'));
    await tester.scrollUntilVisible(find.text('Logout'),200,scrollable:find.byType(Scrollable).last,maxScrolls:12);
   }
   Finder resolve(){
    final textTarget=find.text(text);
    return textTarget.evaluate().isNotEmpty?textTarget:
     text=='Notifications'?find.byIcon(Icons.notifications_outlined):
     text=='Settings'?find.byIcon(Icons.settings_outlined):find.byTooltip(text);
   }
   var target=resolve();final end=DateTime.now().add(const Duration(seconds:45));
   while(target.evaluate().isEmpty && DateTime.now().isBefore(end)){
    await tester.pump(const Duration(milliseconds:300));target=resolve();
   }
   if(target.evaluate().isEmpty)throw StateError('Application action unavailable: $text');
   await tester.ensureVisible(target.first);await tester.pump(const Duration(milliseconds:300));
   await tester.tap(target.first);await tester.pump(const Duration(milliseconds:700));
  }
  Future<void> capture(String name) async{
   if(!surfaceConverted){await binding.convertFlutterSurfaceToImage();surfaceConverted=true;}
   await tester.pump();
   final bytes=await binding.takeScreenshot(name);
   await network(()=>http.post(Uri.parse('$broker/screenshot/$name'),body:bytes));
  }
  final fixture=jsonDecode((await network(()=>http.get(Uri.parse('$broker/fixtures')))).body) as Map;
  var passed=false;
  try{
   // Reset this harness's synthetic session through the app's own storage API.
   await network(()=>SecureStorageService().clearActiveUser());
   app.main();await tester.pumpAndSettle(const Duration(milliseconds:300));
   await waitFor(find.text('Welcome to Comten'));
   await report('Native startup and Firebase initialization');
   if(const bool.fromEnvironment('DEVICE_WORKFLOW_ONLY')){
    workflow=await network(()=>runPhysicalWorkflow(fixture,directReport));
    passed=true;return;
   }
   for(final entry in <String,List<String>>{
    'CAP001':['Projects','Project Controller Management','Billing Management','Approval','Notifications','Settings'],
    'PC001':['Projects','Employee Management','Billing Management','Activities','Notifications','Settings'],
    'TL001':['Attendance','Timesheet Approvals','Project Database','Status Update','Reason for Delay','Notifications','Settings'],
    'EMP001':['My Projects','Attendance','Timesheet','Notifications','Settings'],
   }.entries){
    const resume=bool.fromEnvironment('DEVICE_RESUME');
    const workflowOnly=bool.fromEnvironment('DEVICE_WORKFLOW_ONLY');
    if(workflowOnly && entry.key!='EMP001')continue;
    if(resume && (entry.key=='CAP001'||entry.key=='PC001'))continue;
    await tapText('Login');await waitFor(find.byType(LoginScreen));
    final fields=find.byType(TextFormField);
    await tester.enterText(fields.at(0),entry.key);await tester.enterText(fields.at(1),fixture[entry.key]['password'] as String);
    await tester.testTextInput.receiveAction(TextInputAction.done);await tapText('Login');
    final end=DateTime.now().add(const Duration(seconds:50));
    while(DateTime.now().isBefore(end)){
     await tester.pump(const Duration(milliseconds:400));
     if(find.byType(CreatePinScreen).evaluate().isNotEmpty){
      final pins=find.byType(EditableText);await tester.enterText(pins.at(0),'1234');await tester.enterText(pins.at(1),'1234');await tapText('Continue');
     }
     if(find.byType(FingerprintSetupScreen).evaluate().isNotEmpty)await tapText('Skip');
     if(find.text('Skip').hitTestable().evaluate().isNotEmpty)await tapText('Skip');
     if(find.text('Continue').hitTestable().evaluate().isNotEmpty)await tapText('Continue');
     if(find.text('Quick Access').evaluate().isNotEmpty)break;
    }
    await waitFor(find.text('Quick Access'));await report('${entry.key} native login, PIN and onboarding');
    await capture('${entry.key}-dashboard');
    for(final destination in entry.value){
     if(workflowOnly)continue;
     if(resume && entry.key=='TL001' && destination!='Settings')continue;
     await tapText(destination);await tester.pump(const Duration(seconds:2));
     if(find.text('OK').hitTestable().evaluate().isNotEmpty)await tapText('OK');
     await report('${entry.key} $destination native navigation');
     if(destination=='Settings'){
      await tapText('Change Password');await report('${entry.key} password form opens');
      await tester.pageBack();await tester.pump(const Duration(milliseconds:700));
      await tapText('My attachments');await tester.pump(const Duration(seconds:2));
      await waitFor(find.text('Choose file'));await report('${entry.key} native attachment controls load');
      await tester.pageBack();await tester.pump(const Duration(milliseconds:700));
     }
     await tester.pageBack();await tester.pump(const Duration(milliseconds:700));
    }
    if(entry.key=='EMP001'){
     await report('Native GPS permission and acquisition starting');
     await network(()=>http.post(Uri.parse('$broker/native/location-permission')));
     final position=await network(LocationHelper.getCurrentLocation);
     physicalLocation=position;
     if(position.isSuccess){await report('Real physical GPS acquired; coordinates omitted from evidence');}
     else {limitations.add('Native GPS result: ${position.failure?.name}');}
     final accuracy=await network(()=>Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.best)).timeout(const Duration(seconds:20)));
     if(accuracy.isMocked)throw StateError('Mock location cannot count as physical GPS acceptance');
     await report('Native location accuracy ${accuracy.accuracy.toStringAsFixed(1)} metres; OS reports non-mocked fix');
     final biometric=LocalAuthentication();
     final supported=await network(biometric.isDeviceSupported);
     final enrolled=await network(biometric.getAvailableBiometrics);
     await report('Native biometric capability queried');
     limitations.add('Biometric support=$supported, enrolled=${enrolled.isNotEmpty}; fingerprint authentication needs owner interaction');
     try{
      final token=await network(()=>FirebaseAppCheck.instance.getToken(true).timeout(const Duration(seconds:15)));
      if(token!=null && token.isNotEmpty)await report('Native App Check debug attestation token obtained');
     }catch(_){limitations.add('App Check debug token not yet enrolled; Play Integrity release attestation untested');}
     if(!workflowOnly){
     await network(()=>PushNotificationService.instance.syncToken(entry.key));
     final token=await network(()=>FirebaseMessaging.instance.getToken());
     if(token!=null && token.isNotEmpty){
      await report('Native FCM registration token obtained');
      final received=FirebaseMessaging.onMessage.firstWhere((m)=>m.notification?.title=='Crompton synthetic device test').timeout(const Duration(seconds:30));
      final response=await network(()=>http.post(Uri.parse('$broker/push'),body:jsonEncode({'token':token})));
      if(jsonDecode(response.body)['accepted']==true){
       await network(()=>received);
       await report('Actual FCM notification received on the foreground physical phone');
      }else{limitations.add('Finite FCM provider test was rejected before acceptance');}
     }
     final files=FileService();
     final payload=Uint8List.fromList(utf8.encode('%PDF-1.7 synthetic physical Android fixture'));
     await network(()=>files.upload('employee_document',4,'synthetic-android.pdf','application/pdf',payload,(_, _){}));
     final uploaded=await network(()=>files.list('employee_document',4));
     final file=uploaded.firstWhere((row)=>row['name']=='synthetic-android.pdf');
     final id=file['id'] as String;
     try{
      final bytes=await network(()=>files.download(id));
      if(utf8.decode(bytes)!=utf8.decode(payload))throw StateError('Native download bytes differ');
      await report('Physical Android real R2 upload, confirmation and download bytes');
     }finally{await network(()=>files.delete(id));}
     await report('Physical Android synthetic R2 object deleted');
     final api=ApiService();
     await network(()=>api.get('/users/me'));
     await network(()=>FirebaseFirestore.instance.disableNetwork());
     final offline=await network(()=>api.get('/users/me'));
     await network(()=>FirebaseFirestore.instance.enableNetwork());
     if(offline.statusCode!=200)throw StateError('Offline profile unavailable');
     await report('Native encrypted offline profile and reconnection');
     }
    }
    await tapText('Settings');await tapText('Logout');
    final confirmation=find.widgetWithText(TextButton,'Logout');
    await waitFor(confirmation);await tester.tap(confirmation.last);await tester.pump(const Duration(milliseconds:700));
    await waitFor(find.text('Welcome to Comten'));await report('${entry.key} native logout');
    if(FirebaseAuth.instance.currentUser!=null)throw StateError('Firebase session survived logout');
   }
   if(physicalLocation?.isSuccess==true){
    workflow=await network(()=>runPhysicalWorkflow(fixture,directReport));
   }else{limitations.add('Full real-GPS attendance workflow could not run without a physical fix');}
   passed=true;
  }finally{
   await network(()=>http.post(Uri.parse('$broker/result'),body:jsonEncode({'device':'OPPO CPH2471','android':'12','checks':checks,'limitations':limitations,'workflow':workflow,'passed':passed})));
  }
 },timeout:const Timeout(Duration(minutes:18)));
}
