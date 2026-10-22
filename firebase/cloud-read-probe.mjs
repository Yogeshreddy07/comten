import {readFileSync,writeFileSync} from 'node:fs';
import {initializeApp} from 'firebase/app';
import {getAuth,signInWithEmailAndPassword,signOut} from 'firebase/auth';
import {getFirestore,getDoc,getDocs,doc,query,collection,where,limit,orderBy,documentId} from 'firebase/firestore';
const config=JSON.parse(readFileSync('development.web.json','utf8'));
if(config.FIREBASE_PROJECT_ID!=='crompton-pms-dev-20261015')throw Error('Dedicated development project required');
const logins=JSON.parse(readFileSync('../.local/development-logins.json','utf8'));
const app=initializeApp({projectId:config.FIREBASE_PROJECT_ID,apiKey:config.FIREBASE_API_KEY,appId:config.FIREBASE_APP_ID});
const auth=getAuth(app),db=getFirestore(app),checks=[];
function check(value,label){if(!value)throw Error(label);checks.push(label)}
async function rejected(operation,label){try{await operation;throw Error('Unexpected authorization')}catch(e){if(e.code!=='permission-denied')throw e;checks.push(label)}}
try{
 for(const [code,id,manager]of [['EMP001',4,false],['TL001',3,false],['CAP001',1,true],['PC001',2,true]]){
  await signInWithEmailAndPassword(auth,code.toLowerCase()+'@accounts.crompton.invalid',logins[code].password);
  check((await getDoc(doc(db,'employees',String(id)))).data().active,code+' authoritative profile');
  const projects=await getDocs(query(collection(db,'projects'),...(manager?[]:[where('memberIds','array-contains',id)]),orderBy(documentId()),limit(200)));
  check(projects.docs.some(p=>p.id==='100'),code+' bounded project query');
  const modules=await getDocs(query(collection(db,'modules'),where('projectId','==',100),...(manager?[]:[where('memberIds','array-contains',id)]),orderBy(documentId()),limit(200)));
  check(modules.docs.some(m=>m.id==='101'),code+' project/module composite index');
  await getDocs(query(collection(db,'notifications'),where('userId','==',id),orderBy(documentId()),limit(200)));checks.push(code+' recipient notification query');
  if(!manager){
   await rejected(getDocs(query(collection(db,'employees'),limit(200))),code+' staff enumeration rejected');
   await rejected(getDoc(doc(db,'employees','1')),code+' unrelated employee profile rejected');
  }
  if(code==='TL001')check((await getDoc(doc(db,'employees','4'))).data().id===4,'Assigned leader reads team member profile');
  await signOut(auth);
 }
 await rejected(getDoc(doc(db,'projects','100')),'Anonymous project access rejected');
 writeFileSync('../tests/cloud-query-results.json',JSON.stringify({project:config.FIREBASE_PROJECT_ID,checks},null,2));
 console.log(JSON.stringify(checks,null,2));
}catch(e){console.error(e.code||e.message);process.exitCode=1}
process.exit(process.exitCode||0);
