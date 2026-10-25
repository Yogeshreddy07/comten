import 'package:crypto/crypto.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../services/account_cache.dart';
import '../utils/validators.dart';
import '../constant/api_constants.dart';

/// Adapts the preserved screen contracts to direct Firebase SDK operations.
/// A null result delegates only privileged operations to the trusted backend.
class FirebaseTransport {
  final db=FirebaseFirestore.instance;
  final auth=FirebaseAuth.instance;
  Map<String,dynamic>? _profile;
  Future<List<QueryDocumentSnapshot<Map<String,dynamic>>>> pages(Query<Map<String,dynamic>> query,{bool singlePage=false}) async {
    final result=<QueryDocumentSnapshot<Map<String,dynamic>>>[];
    QueryDocumentSnapshot<Map<String,dynamic>>? cursor;
    while(true) {
      var page=query.orderBy(FieldPath.documentId).limit(200);
      if(cursor!=null) page=page.startAfterDocument(cursor);
      final snapshot=await page.get();result.addAll(snapshot.docs);
      if(singlePage || snapshot.docs.length<200) return result;
      cursor=snapshot.docs.last;
    }
  }
  static String email(String identifier) => identifier.contains('@') ? identifier.trim().toLowerCase() : '${identifier.trim().toLowerCase()}@accounts.crompton.invalid';
  dynamic serial(dynamic value) {
    if(value is Timestamp) return value.toDate().toIso8601String();
    if(value is Map) { return {
      ...value.map((k,v)=>MapEntry(k.toString(),serial(v))),
      if(value.containsKey('read')) 'isRead':value['read'],
      if(value.containsKey('active')) 'isActive':value['active'],
      if(value.containsKey('deleted')) 'isDeleted':value['deleted'],
    }; }
    if(value is List) return value.map(serial).toList();
    return value;
  }
  http.Response response(dynamic data,{String message='Success',int status=200}) => http.Response(jsonEncode({'success':status<400,'message':message,'data':serial(data)}),status,headers:{'content-type':'application/json'});
  Future<Map<String,dynamic>> profile() async {
    final user=auth.currentUser;
    if(user==null) throw StateError('Sign in required');
    final data=(await db.collection('employees').doc(user.uid).get(const GetOptions(source:Source.server)).timeout(const Duration(seconds:8))).data();
    if(data==null || data['active']!=true || ['PENDING','PHONE_PENDING'].contains(data['activationStatus'])) {
      await AccountCache.instance.clear(); await auth.signOut();
      throw StateError('Account is inactive');
    }
    data['userId']=data['id'];
    _profile=data;
    await AccountCache.instance.bind(user.uid,(data['permissionVersion'] as num?)?.toInt()??1);
    await AccountCache.instance.put('auth_profile',data);
    return data;
  }
  Future<http.Response?> request(String method,String endpoint,Map<String,dynamic> body) async {
    final uri=Uri.parse(endpoint),parts=Uri.parse(endpoint).pathSegments;
    if(parts.isEmpty) return null;
    final collection=parts.first;
    try {
      if(endpoint=='/auth/login') {
        await AccountCache.instance.clear(accountUid:auth.currentUser?.uid);
        await auth.signOut();
        var identifier=body['employeeCode'] as String;
        if(identifier.contains('@')) {
          // Contact aliases require authoritative uniqueness and credential checks.
          final resolved=await http.post(Uri.parse('${ApiConstants.baseUrl}/auth/login'),headers:{'Content-Type':'application/json'},body:jsonEncode(body));
          if(resolved.statusCode!=200) return resolved;
          identifier=jsonDecode(resolved.body)['data']['employeeCode'] as String;
        }
        final result=await auth.signInWithEmailAndPassword(email:email(identifier),password:body['password'] as String);
        final p=await profile();
        return response({...p,'userId':p['id'],'token':await result.user!.getIdToken()});
      }
      if(endpoint.startsWith('/auth/signup/')) return null;
      if(endpoint=='/auth/logout') {
        await AccountCache.instance.clear(accountUid:auth.currentUser?.uid); _profile=null; await auth.signOut();return response(null);
      }
      if(endpoint=='/auth/change-password') {
        final u=auth.currentUser!;
        if(body['newPassword']!=body['confirmPassword']) throw StateError('Passwords must match');
        final problem=Validators.password(body['newPassword'] as String?);
        if(problem!=null) throw StateError(problem);
        await u.reauthenticateWithCredential(EmailAuthProvider.credential(email:u.email!,password:body['oldPassword'] as String));
        await u.updatePassword(body['newPassword'] as String);return response(null);
      }
      if(collection=='auth') return null;
      // Contact validation is authoritative, read-only backend work.
      if(endpoint=='/employees/validate-identity') return null;
      // These writes are authorized by the backend. Avoid a redundant profile
      // round trip before sending the authenticated request.
      if ((method == 'POST' && ['projects', 'modules'].contains(collection)) ||
          (method != 'GET' && ['projects', 'modules'].contains(collection) &&
              (method == 'DELETE' || parts.length > 2))) {
        await AccountCache.instance.invalidateData();
        return null;
      }
      Map<String,dynamic> p;
      try { p=await profile(); }
      on Exception catch(e) {
        if(method=='GET' && (e is TimeoutException || (e is FirebaseException && e.code=='unavailable')) && auth.currentUser!=null) {
          _profile = await AccountCache.instance.restoreProfile(auth.currentUser!.uid);
          if(_profile==null) rethrow;
          if(endpoint=='/users/me') return response(_profile,message:'Offline cached profile');
          final cached=AccountCache.instance.read(endpoint);
          if(cached!=null) return response(cached,message:'Offline cached data');
        }
        rethrow;
      }
      final id=p['id'];
      final manager=['CAPTAIN','PROJECT_CONTROLLER'].contains(p['role']);
      if(endpoint=='/users/me') return response(p);
      if(method!='GET') await AccountCache.instance.invalidateData();
      if(method=='GET' && !['notifications','attendance','work-logs'].contains(collection)) {
        final cached=AccountCache.instance.read(endpoint,stale:false);
        if(cached!=null) return response(cached);
      }
      if(collection=='notifications' && parts.contains('device-tokens')) {
        final key=base64UrlEncode(utf8.encode(body['token'] as String));
        final ref=db.collection('device-tokens').doc(key);
        if(parts.contains('unregister')) { await ref.delete(); }
        else { await ref.set({'userId':id,'token':body['token'],'updatedAt':FieldValue.serverTimestamp()}); }
        return response(null);
      }
      if(collection=='notifications' && parts.last=='read') {
        final ref=db.collection(collection).doc(parts[1]);await ref.update({'read':true});return response((await ref.get()).data());
      }
      if(collection=='attendance') return await attendance(method,parts,body,p,uri);
      if(collection=='work-logs' && method=='POST' && parts.length==1) return await submitWorkLog(body,p);
      if(method!='GET') {
        if(collection=='activities' && method=='DELETE') {
          await db.collection(collection).doc(parts[1]).update({'active':false});return response(null);
        }
        if(collection=='activities' && (method=='POST'||method=='PUT')) {
          final key=parts.length>1?parts[1]:DateTime.now().microsecondsSinceEpoch.toString();
          final row={'id':int.parse(key),'name':body['name'],'active':true};
          await db.collection(collection).doc(key).set(row);return response(row);
        }
        if(collection=='projects' && method=='PUT' && parts.length==2) {
          final changes={for(final k in ['projectName','clientId']) if(body.containsKey(k)) k:body[k]};
          await db.collection(collection).doc(parts[1]).update(changes);return response(await decorate('projects',(await db.collection(collection).doc(parts[1]).get()).data()!));
        }
        return null;
      }
      final supported=['employees','projects','modules','activities','work-logs','notifications','module-change-requests','project-deactivation-requests','billing-status-change-requests'];
      if(collection=='projects' && parts.last=='users') {
        final result=await pages(db.collection('employees').where('role',isEqualTo:uri.queryParameters['role']));return response(result.map((d)=>{...d.data(),'userId':d.data()['id']}).where((e)=>e['active']==true && e['deleted']!=true).toList());
      }
      if(collection=='work-logs' && parts.last=='reminder') {
        final previous=DateTime.now().subtract(const Duration(days:1)).toIso8601String().substring(0,10);
        final day=DateTime.parse(previous);
        final key=(id as int)*100000000+day.year*10000+day.month*100+day.day;
        final s=await db.collection('work-log-days').doc(key.toString()).get();
        return response({'missingDayLabel':!s.exists && day.weekday!=DateTime.sunday ? previous:null});
      }
      if(!supported.contains(collection)) return null;
      if(parts.length==2 && !['my','led','completed','unread-count'].contains(parts.last)) {
        final d=await db.collection(collection).doc(parts[1]).get();
        if(!d.exists) return response(null,status:404,message:'Record not found');
        final row=await decorate(collection,d.data()!);
        await AccountCache.instance.put(endpoint,serial(row));return response(row);
      }
      Query<Map<String,dynamic>> query=db.collection(collection);
      if(collection=='notifications') query=query.where('userId',isEqualTo:id);
      if(['projects','modules'].contains(collection)&&!manager) query=query.where('memberIds',arrayContains:id);
      if(collection=='work-logs'&&!manager) query=query.where(parts.contains('my')?'employeeId':'teamLeadId',isEqualTo:id);
      if(collection.endsWith('requests')&&!manager) query=query.where('requestedById',isEqualTo:id);
      if(uri.queryParameters['after']!=null) {
        final cursor=await db.collection(collection).doc(uri.queryParameters['after']).get();
        if(cursor.exists) query=query.startAfterDocument(cursor);
      }
      // Single-field indexed query + bounded page; secondary UI filters apply to that page.
      final documents=await pages(query,singlePage:uri.queryParameters['after']!=null);
      var data=documents.map((d)=>d.data()).where((r)=>r['deleted']!=true).toList();
      if(collection=='activities') data=data.where((r)=>r['active']!=false).toList();
      if(collection=='modules' && parts.contains('led')) data=data.where((r)=>r['teamLeadId']==id).toList();
      if(collection=='modules' && parts.contains('completed')) data=data.where((r)=>r['teamLeadId']==id && r['active']==true && (['NOT_STARTED','IN_PROGRESS','COMPLETED'].contains(r['status']) || r['workStage']=='BILLING')).toList();
      if(collection=='notifications') data.sort((a,b)=>b['createdAt'].toString().compareTo(a['createdAt'].toString()));
      for(final entry in uri.queryParameters.entries) {
        if(['active','role','moduleId','employeeId','status','projectId'].contains(entry.key)) {
          final key=collection=='work-logs' && entry.key=='status'?'approvalStatus':entry.key;
          data=data.where((r)=>r[key].toString()==entry.value).toList();
        }
      }
      if(uri.queryParameters['fromDate']!=null) data=data.where((r)=>r['workDate'].toString().compareTo(uri.queryParameters['fromDate']!)>=0).toList();
      if(uri.queryParameters['toDate']!=null) data=data.where((r)=>r['workDate'].toString().compareTo(uri.queryParameters['toDate']!)<=0).toList();
      if(collection=='notifications'&&parts.last=='unread-count') return response(data.where((r)=>r['read']!=true).length);
      // The led-module pickers only need module fields. Decorating them reads
      // every employee profile, including historical members no longer in the
      // lead's peer roster, and can deny the entire picker unnecessarily.
      final ledPicker=collection=='modules' && parts.contains('led');
      if(ledPicker) data=data.where((r)=>r['active']==true).toList();
      var result=ledPicker ? data : await Future.wait(data.map((r)=>decorate(collection,r,summaryOnly:true)));
      if(collection=='projects' && uri.queryParameters['hasInProgressModule']=='true') {
        result=result.where((r)=>(r['modules'] as List).any((m)=>m['active']==true && m['status']=='IN_PROGRESS' && (m['memberIds'] as List).contains(id))).toList();
      }
      await AccountCache.instance.put(endpoint,serial(result));return response(result);
    } on FirebaseAuthException catch(e) { return response(null,status:401,message:e.message??'Authentication failed'); }
      on TimeoutException { return response(null,status:503,message:'Firebase connection timed out'); }
      on FirebaseException catch(e) { return response(null,status:e.code=='permission-denied'?403:503,message:e.code=='permission-denied'?'Permission denied':'Firebase is unavailable'); }
      on StateError catch(e) { return response(null,status:409,message:e.message); }
  }
  Future<Map<String,dynamic>> decorate(String collection,Map<String,dynamic> row,{bool summaryOnly=false}) async {
    final result={...row,'isActive':row['active']??true};
    if(collection=='projects') {
      Query<Map<String,dynamic>> q=db.collection('modules').where('projectId',isEqualTo:row['id']);
      if(!['CAPTAIN','PROJECT_CONTROLLER'].contains(_profile?['role'])) q=q.where('memberIds',arrayContains:_profile!['id']);
      final modules=await pages(q);
      final visible=modules.map((d)=>d.data()).where((m)=>m['deleted']!=true).toList();
      final current=visible.where((m)=>m['active']!=false).toList();
      result['modules']=await Future.wait(visible.map((m)=>decorate('modules',m,summaryOnly:true)));
      result['moduleCount']=current.length;
      final states=current.map((m)=>m['status']).toSet();
      result['status']=row['active']==false?'INACTIVE':states.isEmpty?'NOT_STARTED':states.length==1?states.first:'IN_PROGRESS';
      final starts=current.map((m)=>m['startDate']).whereType<String>().toList()..sort();
      final ends=current.map((m)=>m['endDate']).whereType<String>().toList()..sort();
      result['startDate']=starts.firstOrNull;result['endDate']=ends.lastOrNull;
      result['estimatedMinutes']=current.fold<int>(0,(n,m)=>n+((m['estimatedMinutes'] as num?)?.toInt()??0));
      result['workedMinutes']=current.fold<int>(0,(n,m)=>n+((m['completedMinutes'] as num?)?.toInt()??0));
      result['pendingMinutes']=((result['estimatedMinutes'] as int)-(result['workedMinutes'] as int)).clamp(0,1<<40);
    }
      if(collection=='modules') {
      if(row['active']==false) result['status']='INACTIVE';
      result['completedHours']=row['completedHours']??0;
      result['completedMinutes']=row['completedMinutes']??0;
      // Lists display names/status only. Load the full assignment graph for
      // module details, with independent document reads running together.
      final reads=<String,Future<DocumentSnapshot<Map<String,dynamic>>>>{};
      void read(String collection,dynamic id) {
        final path='$collection/$id';
        reads.putIfAbsent(path,()=>db.doc(path).get());
      }
      if(row['teamLeadId']!=null) read('employees',row['teamLeadId']);
      if(!summaryOnly) {
        for(final id in (row['memberIds'] as List? ?? [])) { read('employees',id); }
        for(final category in ['billable','nonBillable']) {
          for(final id in (row['${category}ActivityIds'] as List? ?? [])) { read('activities',id); }
        }
      }
      final docs=await Future.wait(reads.values);
      final records={for(final doc in docs) doc.reference.path:doc.data()};
      if(row['teamLeadId']!=null) result['teamLeadName']=records['employees/${row['teamLeadId']}']?['name'];
      if(!summaryOnly) {
        result['members']=[for(final id in (row['memberIds'] as List? ?? []))
          if(records['employees/$id']!=null) {...records['employees/$id']!,'userId':id}];
        for(final category in ['billable','nonBillable']) {
          result['${category}Activities']=[for(final id in (row['${category}ActivityIds'] as List? ?? []))
            if(records['activities/$id']!=null) records['activities/$id']!];
        }
      }
    }
    return result;
  }
  Future<http.Response> attendance(String method,List<String> parts,Map<String,dynamic> body,Map<String,dynamic> p,Uri uri) async {
    final now=DateTime.now().toUtc().add(const Duration(minutes:330));
    final day=DateTime.utc(now.year,now.month,now.day);
    final dayId=(p['id'] as int)*100000000+day.year*10000+day.month*100+day.day;
    final ref=db.collection('attendance').doc(dayId.toString());
    if(parts.last=='team') {
      final modules=await pages(db.collection('modules').where('memberIds',arrayContains:p['id']));
      final ids=<int>{};
      for(final snapshot in modules) {
        final m=snapshot.data();
        if(m['teamLeadId']!=p['id'] || m['active']!=true || m['deleted']==true) continue;
        final parent=(await db.collection('projects').doc(m['projectId'].toString()).get()).data();
        if(parent?['active']==true && parent?['deleted']!=true) ids.addAll((m['memberIds'] as List).cast<int>());
      }
      final date=DateTime.parse(uri.queryParameters['date']??now.toIso8601String().substring(0,10));
      final result=<Map<String,dynamic>>[];
      for(final id in ids.where((id)=>id!=p['id'])) {
        final employee=(await db.collection('employees').doc(id.toString()).get()).data();
        if(employee==null) continue;
        final key=id*100000000+date.year*10000+date.month*100+date.day;
        final a=(await db.collection('attendance').doc(key.toString()).get()).data();
        result.add({'employeeId':id,'employeeCode':employee['employeeCode'],'employeeName':employee['name'],'attendanceDate':date.toIso8601String().substring(0,10),'status':a==null?'NOT_CHECKED_IN':a['outTime']==null?'CHECKED_IN':'CHECKED_OUT',...?a});
      }
      return response(result);
    }
    if(method=='GET') return response((await ref.get()).data());
    final latitude=body['latitude']??body['checkOutLatitude'],longitude=body['longitude']??body['checkOutLongitude'];
    if(latitude is! num||longitude is! num) throw StateError('GPS location is required');
    await db.runTransaction((tx) async {
      final old=await tx.get(ref);
      if(parts.last=='check-in') {
        if(old.exists) throw StateError('Already checked in');
        tx.set(ref,{'id':dayId,'employeeId':p['id'],'employeeCode':p['employeeCode'],'employeeName':p['name'],'attendanceType':body['attendanceType']??'OFFICE','attendanceDate':now.toIso8601String().substring(0,10),'dayTimestamp':Timestamp.fromDate(day),'inTime':FieldValue.serverTimestamp(),'outTime':null,'latitude':latitude,'longitude':longitude,'locationName':body['locationName']});
      } else {
        if(!old.exists || old.data()?['outTime']!=null) throw StateError('No open attendance');
        tx.update(ref,{'outTime':FieldValue.serverTimestamp(),'checkOutLatitude':latitude,'checkOutLongitude':longitude,'checkOutLocationName':body['locationName'],'checkOutAttendanceType':body['attendanceType']??'OFFICE'});
      }
    });
    return response((await ref.get()).data());
  }
  Future<http.Response> submitWorkLog(Map<String,dynamic> body,Map<String,dynamic> p) async {
    final date=DateTime.parse(body['workDate'] as String);
    if(date.weekday==DateTime.sunday||date.isAfter(DateTime.now())) throw StateError('Select a valid working day');
    final bill=(body['billableDurationSeconds'] as num?)?.toInt()??0,non=(body['nonBillableDurationSeconds'] as num?)?.toInt()??0;
    if(bill<0||non<0||bill+non<=0||bill+non>86400) throw StateError('Duration must be between zero and 24 hours');
    final m=(await db.collection('modules').doc(body['moduleId'].toString()).get()).data();
    if(m==null) throw StateError('Module not found');
    final dayId=(p['id'] as int)*100000000+date.year*10000+date.month*100+date.day;
    final key=int.parse(sha256.convert(utf8.encode('${p['id']}:${jsonEncode(body)}')).toString().substring(0,13),radix:16).toString();
    final billIds=List<int>.from(body['billableActivityIds'] as List? ?? []), nonIds=List<int>.from(body['nonBillableActivityIds'] as List? ?? []);
    final activities=<String,List<Map<String,dynamic>>>{};
    for(final category in ['billable','nonBillable']) {
      activities[category]=[];
      for(final id in category=='billable'?billIds:nonIds) {
        if(!(m['${category}ActivityIds'] as List? ?? []).contains(id)) throw StateError('Activity is not configured for this module');
        final a=(await db.collection('activities').doc(id.toString()).get()).data();
        if(a!=null) activities[category]!.add(a);
      }
    }
    final row={'id':int.parse(key),'dayId':dayId,'dayTimestamp':Timestamp.fromDate(DateTime.utc(date.year,date.month,date.day)),'employeeId':p['id'],'employeeCode':p['employeeCode'],'employeeName':p['name'],'moduleId':m['id'],'moduleName':m['moduleName'],'projectId':m['projectId'],'projectCode':m['projectCode'],'projectName':m['projectName'],'teamLeadId':m['teamLeadId'],'workDate':body['workDate'],'workDone':body['workDone'],'billableDurationSeconds':bill,'nonBillableDurationSeconds':non,'billableActivityIds':billIds,'nonBillableActivityIds':nonIds,'billableActivities':activities['billable'],'nonBillableActivities':activities['nonBillable'],'approvalStatus':'PENDING','createdAt':FieldValue.serverTimestamp()};
    final ref=db.collection('work-logs').doc(key),ledger=db.collection('work-log-days').doc(dayId.toString());
    await db.runTransaction((tx) async {
      final existing=await tx.get(ref);
      if(existing.exists) return;
      final previous=await tx.get(ledger);
      final attendance=await tx.get(db.collection('attendance').doc(dayId.toString()));
      if(!attendance.exists) throw StateError('Check in before logging hours');
      final a=attendance.data()!;
      final elapsed=((a['outTime'] as Timestamp?)?.toDate()??DateTime.now()).difference((a['inTime'] as Timestamp).toDate()).inSeconds;
      final total=((previous.data()?['totalSeconds'] as num?)?.toInt()??0)+bill+non;
      // Closed attendance has two authoritative server timestamps. For an open
      // shift, the phone clock may lag the server; Firestore Rules enforce the
      // request.time boundary atomically instead of rejecting on an untrusted clock.
      if(a['outTime']!=null && total>elapsed) throw StateError('Timesheet hours exceed your attendance duration');
      tx.set(ref,row);
      tx.set(ledger,{'employeeId':p['id'],'dayTimestamp':row['dayTimestamp'],'workDate':body['workDate'],'totalSeconds':total,'lastEntryId':key,'lastEntrySeconds':bill+non});
      tx.set(db.collection('notifications').doc(key),{'id':int.parse(key),'userId':m['teamLeadId'],'title':'Timesheet submitted','message':'${p['name']} submitted working hours for ${m['moduleName']}.','type':'TIMESHEET_SUBMITTED','moduleId':m['id'],'moduleName':m['moduleName'],'projectId':m['projectId'],'projectCode':m['projectCode'],'projectName':m['projectName'],'read':false,'pushPending':true,'createdAt':FieldValue.serverTimestamp()});
    });
    return response((await ref.get()).data());
  }
}
