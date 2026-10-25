import {readFileSync} from 'node:fs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment, assertFails} from '@firebase/rules-unit-testing';
import {doc, setDoc, getDoc, getDocs, collection, query, where, limit, runTransaction, Timestamp, serverTimestamp} from 'firebase/firestore';

test('another module can be logged while the first is pending; both appear in My Timesheets', async () => {
  // Freeze the work-week boundary only in this test rules copy, so the
  // regression exercises submissions even when the test runs on Sunday.
  const rules=readFileSync('firestore.rules','utf8').replace(
    'return (request.time + duration.value(330, \'m\')).date();',
    'return timestamp.date(2026, 10, 19);');
  const env=await initializeTestEnvironment({projectId:'demo-timesheet-regression',
    firestore:{host:'127.0.0.1',port:8086,rules}});
  try {
    await env.clearFirestore();
    const day=Timestamp.fromDate(new Date('2026-10-19T00:00:00Z'));
    const dayId=4*100000000+20261019;
    await env.withSecurityRulesDisabled(async context => {
      const db=context.firestore();
      await setDoc(doc(db,'employees','4'),{id:4,active:true,role:'EMPLOYEE'});
      await setDoc(doc(db,'projects','100'),{id:100,active:true,deleted:false,memberIds:[3,4]});
      for (const id of [101,102,103]) await setDoc(doc(db,'modules',String(id)),{
        id,projectId:100,active:true,deleted:false,status:'IN_PROGRESS',teamLeadId:3,
        memberIds:[3,4],billableActivityIds:[1],nonBillableActivityIds:[]});
      await setDoc(doc(db,'attendance',String(dayId)),{employeeId:4,
        inTime:Timestamp.fromMillis(Date.now()-10800000),outTime:null});
    });
    const db=env.authenticatedContext('4').firestore();
    async function submit(moduleId,seconds=900) {
      const key=String(moduleId);
      const ref=doc(db,'work-logs',key),ledger=doc(db,'work-log-days',String(dayId));
      await runTransaction(db,async tx => {
        const existing=await tx.get(ref);
        if(existing.exists()) return;
        const previous=await tx.get(ledger);
        const attendance=await tx.get(doc(db,'attendance',String(dayId)));
        assert.equal(attendance.exists(),true);
        tx.set(ref,{id:moduleId,dayId,dayTimestamp:day,employeeId:4,employeeCode:'EMP004',
          employeeName:'Employee',moduleId,moduleName:'Module '+moduleId,projectId:100,
          projectName:'Project',projectCode:'P100',teamLeadId:3,workDate:'2026-10-19',
          workDone:'Design',billableDurationSeconds:seconds,nonBillableDurationSeconds:0,
          billableActivityIds:[1],nonBillableActivityIds:[],billableActivities:[],
          nonBillableActivities:[],approvalStatus:'PENDING',createdAt:serverTimestamp()});
        tx.set(ledger,{employeeId:4,dayTimestamp:day,workDate:'2026-10-19',
          totalSeconds:(previous.data()?.totalSeconds??0)+seconds,lastEntryId:key,lastEntrySeconds:seconds});
        tx.set(doc(db,'notifications',key),{id:moduleId,userId:3,title:'Timesheet submitted',
          message:'Design',type:'TIMESHEET_SUBMITTED',moduleId,moduleName:'Module '+moduleId,
          projectId:100,projectCode:'P100',projectName:'Project',read:false,
          pushPending:true,createdAt:serverTimestamp()});
      });
    }
    await submit(101);
    await submit(102);
    const rows=await getDocs(query(collection(db,'work-logs'),where('employeeId','==',4),limit(200)));
    assert.equal(rows.size,2);
    assert.deepEqual(rows.docs.map(d=>d.data().approvalStatus),['PENDING','PENDING']);
    await submit(102); // An identical retry cannot double-charge the ledger.
    assert.equal((await getDoc(doc(db,'work-log-days',String(dayId)))).data().totalSeconds,1800);
    await assertFails(submit(103,20000)); // Daily attendance limits still apply.
    assert.equal((await getDoc(doc(db,'work-log-days',String(dayId)))).data().totalSeconds,1800);
  } finally { await env.cleanup(); }
});
