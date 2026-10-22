// Enroll only this physical test installation in the dedicated development app.
const fs=require('node:fs');
const path=require('node:path');
const cp=require('node:child_process');
const crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');
const serial=process.argv[2];
if(serial!=='ZPQKY94PCMFMTSKN')throw Error('Expected development test phone');
const adb=(...args)=>cp.execFileSync('D:/SDKs/Android/platform-tools/adb.exe',['-s',serial,...args],{encoding:'utf8',stdio:['ignore','pipe','pipe']});
const base=path.join(path.dirname(process.execPath),'node_modules/firebase-tools/lib');
const {getGlobalDefaultAccount,setActiveAccount}=require(path.join(base,'auth'));
const {requireAuth}=require(path.join(base,'requireAuth'));
const {Client}=require(path.join(base,'apiv2'));
let stage='read application debug preferences';
async function main(){
 const files=adb('shell','run-as','com.crompton.pms.frontend','ls','shared_prefs').split(/\r?\n/);
 const file=files.find(v=>v.startsWith('com.google.firebase.appcheck.debug.store.')&&v.endsWith('.xml'));
 if(!file)throw Error('App Check debug preferences unavailable');
 const xml=adb('shell','run-as','com.crompton.pms.frontend','cat','shared_prefs/'+file);
 const secret=xml.match(/>([0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})</i)?.[1];
 if(!secret)throw Error('App Check debug secret unavailable');
 const opts={project:'crompton-pms-dev-20261015'};
 stage='authenticate Firebase CLI';
 const account=getGlobalDefaultAccount();if(!account)throw Error('Firebase CLI login required');
 setActiveAccount(opts,account);await requireAuth(opts);
 const client=new Client({urlPrefix:'https://firebaseappcheck.googleapis.com',apiVersion:'v1'});
 const parent='/projects/594214226228/apps/1:594214226228:android:8262d4760006f8aa61bd61';
 const displayName='OPPO physical development '+crypto.createHash('sha256').update(secret).digest('hex').slice(0,8);
 stage='list development debug enrollments';
 const listed=await client.get(parent+'/debugTokens',{skipLog:{resBody:true}});
 if(!(listed.body.debugTokens||[]).some(v=>v.displayName===displayName)){
  stage='create development debug enrollment';
  await client.post(parent+'/debugTokens',{displayName,token:secret},{skipLog:{reqBody:true,resBody:true}});
 }
 fs.writeFileSync(path.join(root,'tests/android/appcheck-enrollment.json'),JSON.stringify({project:opts.project,device:'OPPO CPH2471',debugEnrollment:true,releasePlayIntegrityTested:false},null,2));
 console.log('Physical development installation enrolled for debug App Check. Release attestation remains untested.');
}
main().catch(e=>{console.error(JSON.stringify({appCheckEnrollment:false,stage,status:e.status||e.code||null}));process.exitCode=1});
