import {initializeApp} from 'firebase/app';
import {getAuth,connectAuthEmulator,signInWithEmailAndPassword} from 'firebase/auth';
import {getFirestore,connectFirestoreEmulator,getDoc,getDocs,doc,query,collection,where,limit,orderBy,documentId} from 'firebase/firestore';
const app=initializeApp({projectId:'demo-crompton-pms',apiKey:'demo-key'});
const auth=getAuth(app);connectAuthEmulator(auth,'http://127.0.0.1:9099',{disableWarnings:true});
const db=getFirestore(app);connectFirestoreEmulator(db,'127.0.0.1',8086);
try{
 await signInWithEmailAndPassword(auth,'tl001@accounts.crompton.invalid','SyntheticPass123!');
 const profile=(await getDoc(doc(db,'employees','3'))).data();console.log('Profile',profile.peerIds);
 const modules=await getDocs(query(collection(db,'modules'),where('memberIds','array-contains',3),orderBy(documentId()),limit(200)));
 const ids=new Set();
 for(const snap of modules.docs){
  const m=snap.data();if(m.teamLeadId!==3 || !m.active || m.deleted)continue;
  const project=(await getDoc(doc(db,'projects',String(m.projectId)))).data();
  if(project.active&&!project.deleted)m.memberIds.forEach(id=>ids.add(id));
 }
 const d=new Date(Date.now()+330*60000);const day=d.getUTCFullYear()*10000+(d.getUTCMonth()+1)*100+d.getUTCDate();
 for(const id of ids){
  if(id===3)continue;
  console.log('Employee',id);await getDoc(doc(db,'employees',String(id)));
  console.log('Attendance',id*100000000+day);await getDoc(doc(db,'attendance',String(id*100000000+day)));
 }
 console.log('PASS');
}catch(e){console.error(e.code,e.message);process.exitCode=1}
process.exit(process.exitCode||0);
