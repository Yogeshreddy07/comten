import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {test, before, after} from 'node:test';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,getDocs,collection,query,where,limit,updateDoc,Timestamp,serverTimestamp,writeBatch} from 'firebase/firestore';
let env;
before(async()=>{
 env=await initializeTestEnvironment({projectId:'demo-crompton-rules',firestore:{host:'127.0.0.1',port:8086,rules:readFileSync('firestore.rules','utf8')}});
 await env.clearFirestore();
 await env.withSecurityRulesDisabled(async c=>{
  const db=c.firestore();
  for(const [id,role] of [[11,'CAPTAIN'],[12,'PROJECT_CONTROLLER'],[13,'TEAM_LEADER'],[14,'EMPLOYEE'],[15,'EMPLOYEE']]) await setDoc(doc(db,'employees',String(id)),{id,role,active:id!==15,name:'Synthetic',permissionVersion:1});
  await setDoc(doc(db,'projects','200'),{id:200,projectCode:'TEST',projectName:'Test project',active:true,deleted:false,memberIds:[13,14]});
  await setDoc(doc(db,'projects','201'),{id:201,projectCode:'OTHER',projectName:'Other project',active:true,deleted:false,memberIds:[]});
  await setDoc(doc(db,'modules','202'),{id:202,projectId:200,teamLeadId:13,memberIds:[13,14],billableActivityIds:[1],nonBillableActivityIds:[],active:true});
  await setDoc(doc(db,'modules','204'),{id:204,projectId:200,teamLeadId:13,memberIds:[13],active:true});
  const d=new Date(Date.now()+330*60000);d.setUTCHours(0,0,0,0);
  const dayId=14*100000000+d.getUTCFullYear()*10000+(d.getUTCMonth()+1)*100+d.getUTCDate();
  await setDoc(doc(db,'attendance',String(dayId)),{id:dayId,employeeId:14,attendanceDate:d.toISOString().slice(0,10),inTime:Timestamp.fromMillis(Date.now()-10800000),outTime:null});
  await setDoc(doc(db,'notifications','203'),{id:203,userId:14,read:false});
 });
});
after(async()=>{await env.cleanup()});
test('activity deletion requires authoritative assignment checks',async()=>{
 const db=env.authenticatedContext('12').firestore();
 await assertSucceeds(setDoc(doc(db,'activities','700'),{id:700,name:'Unused',active:true}));
 await assertFails(updateDoc(doc(db,'activities','700'),{active:false}));
 await assertFails(setDoc(doc(db,'project-codes','reserved'),{projectId:200}));
});
test('pending email activation cannot access Firestore even with a token',async()=>{
 await env.withSecurityRulesDisabled(async c=>setDoc(doc(c.firestore(),'employees','16'),{id:16,role:'EMPLOYEE',active:true,activationStatus:'PENDING'}));
 const db=env.authenticatedContext('16').firestore();
 await assertFails(getDoc(doc(db,'employees','16')));
 await assertFails(getDocs(query(collection(db,'activities'),limit(10))));
});
test('pending phone activation cannot access Firestore even with a token',async()=>{
 await env.withSecurityRulesDisabled(async c=>setDoc(doc(c.firestore(),'employees','17'),{id:17,role:'EMPLOYEE',active:true,emailVerified:true,activationStatus:'PHONE_PENDING'}));
 const db=env.authenticatedContext('17').firestore();
 await assertFails(getDoc(doc(db,'employees','17')));
 await assertFails(getDocs(query(collection(db,'activities'),limit(10))));
});
test('lead picker can read assigned modules without reading employee profiles',async()=>{
 const db=env.authenticatedContext('13').firestore();
 // Historical module members need not be present in the current peer roster.
 await assertFails(getDoc(doc(db,'employees','14')));
 const snapshot=await assertSucceeds(getDocs(query(collection(db,'modules'),where('memberIds','array-contains',13),limit(200))));
 // Project-scoped module loading keeps the mandatory membership restriction.
 const scoped=await assertSucceeds(getDocs(query(collection(db,'modules'),where('memberIds','array-contains',13),where('projectId','==',200),limit(200))));
 assert.equal(scoped.size,snapshot.size);
 if(!snapshot.docs.some(d=>d.id==='202')) throw new Error('Assigned module missing');
 await assertFails(getDocs(query(collection(db,'modules'),limit(200))));
});
test('all client roles are denied provider secrets, challenges, delivery and file metadata',async()=>{
 for(const uid of ['11','12','13','14']){
  const db=env.authenticatedContext(uid).firestore();
  for(const name of ['files','file-rate-limits','email-outbox','provider-deliveries','phone-challenges','phone-rate-limits','recovery']){
   await assertFails(getDoc(doc(db,name,'synthetic')));
   await assertFails(setDoc(doc(db,name,'synthetic'),{userId:Number(uid),state:'READY'}));
  }
 }
});
test('anonymous and deactivated accounts cannot read',async()=>{
 await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'projects','200')));
 await assertFails(getDoc(doc(env.authenticatedContext('15').firestore(),'projects','200')));
});
for(const [id,role] of [[11,'CAPTAIN'],[12,'PROJECT_CONTROLLER'],[13,'TEAM_LEADER'],[14,'EMPLOYEE']]) test(`${role} reads permitted assigned project`,async()=>{
 await assertSucceeds(getDoc(doc(env.authenticatedContext(String(id)).firestore(),'projects','200')));
});
test('employee cannot read unassigned project or change role',async()=>{
 const db=env.authenticatedContext('14').firestore();
 await assertFails(getDoc(doc(db,'projects','201')));
 await assertFails(updateDoc(doc(db,'employees','14'),{role:'CAPTAIN'}));
 await assertFails(updateDoc(doc(db,'modules','202'),{estimatedMinutes:1}));
 await assertFails(getDoc(doc(db,'modules','204')));
});
test('bounded scoped query required',async()=>{
 const db=env.authenticatedContext('14').firestore();
 await assertFails(getDocs(collection(db,'projects')));
 await assertSucceeds(getDocs(query(collection(db,'projects'),where('memberIds','array-contains',14),limit(50))));
 await assertFails(getDocs(query(collection(db,'employees'),limit(50))));
 await assertFails(getDoc(doc(db,'employees','11')));
 await assertSucceeds(getDoc(doc(db,'employees','14')));
});
test('notification recipient can mark read only',async()=>{
 const db=env.authenticatedContext('14').firestore();
 await assertSucceeds(updateDoc(doc(db,'notifications','203'),{read:true}));
 await assertFails(updateDoc(doc(db,'notifications','203'),{userId:11}));
 await assertFails(getDoc(doc(env.authenticatedContext('13').firestore(),'notifications','203')));
});
test('project assignment and lifecycle require server authority',async()=>{
 const db=env.authenticatedContext('11').firestore();
 await assertFails(updateDoc(doc(db,'projects','200'),{memberIds:[11]}));
 await assertFails(updateDoc(doc(db,'projects','200'),{active:false}));
 await assertSucceeds(updateDoc(doc(db,'projects','200'),{projectName:'Renamed project'}));
});
test('device registration cannot steal another account token',async()=>{
 const mine=env.authenticatedContext('14').firestore(),other=env.authenticatedContext('13').firestore();
 await assertSucceeds(setDoc(doc(mine,'device-tokens','synthetic-token'),{userId:14,token:'synthetic-token',updatedAt:serverTimestamp()}));
 await assertFails(setDoc(doc(other,'device-tokens','synthetic-token'),{userId:13,token:'synthetic-token',updatedAt:serverTimestamp()}));
 await assertFails(getDoc(doc(other,'device-tokens','synthetic-token')));
});
test('work log has bounded duration, unique day, no client approval',async()=>{
 const db=env.authenticatedContext('14').firestore();
 const d=new Date(Date.now()+330*60000);d.setUTCHours(0,0,0,0);
 const dayId=14*100000000+d.getUTCFullYear()*10000+(d.getUTCMonth()+1)*100+d.getUTCDate();
 const key=String(Date.now());
 const row={id:Number(key),dayId,dayTimestamp:Timestamp.fromDate(d),employeeId:14,employeeCode:'TEST14',employeeName:'Synthetic',moduleId:202,moduleName:'Test',projectId:200,projectCode:'TEST',projectName:'Test project',teamLeadId:13,workDate:d.toISOString().slice(0,10),workDone:'Synthetic design',billableDurationSeconds:3600,nonBillableDurationSeconds:0,billableActivityIds:[1],nonBillableActivityIds:[],billableActivities:[],nonBillableActivities:[],approvalStatus:'PENDING',createdAt:serverTimestamp()};
 await assertFails(setDoc(doc(db,'work-logs',String(key)),{...row,billableDurationSeconds:90000}));
 await assertFails(setDoc(doc(db,'work-logs',String(key)),{...row,approvalStatus:'APPROVED'}));
 const batch=writeBatch(db);
 batch.set(doc(db,'work-logs',key),row);
 batch.set(doc(db,'work-log-days',String(dayId)),{employeeId:14,dayTimestamp:Timestamp.fromDate(d),workDate:row.workDate,totalSeconds:3600,lastEntryId:key,lastEntrySeconds:3600});
 await assertSucceeds(batch.commit());
 await assertFails(updateDoc(doc(db,'work-logs',String(key)),{approvalStatus:'APPROVED'}));
 const next=String(Number(key)+1),over=writeBatch(db);
 over.set(doc(db,'work-logs',next),{...row,id:Number(next),billableDurationSeconds:10000});
 over.set(doc(db,'work-log-days',String(dayId)),{employeeId:14,dayTimestamp:Timestamp.fromDate(d),workDate:row.workDate,totalSeconds:13600,lastEntryId:next,lastEntrySeconds:10000});
 await assertFails(over.commit());
});
