// Restricted to the newly created development project. Never prints private key material.
const path=require('node:path');
const fs=require('node:fs/promises');
const base=path.join(path.dirname(process.execPath),'node_modules/firebase-tools/lib');
const {getGlobalDefaultAccount,setActiveAccount}=require(path.join(base,'auth'));
const {requireAuth}=require(path.join(base,'requireAuth'));
const {ensure}=require(path.join(base,'ensureApiEnabled'));
const {Client}=require(path.join(base,'apiv2'));
async function main(){
 const project='crompton-pms-dev-20261015';
 const output=path.resolve(__dirname,'../.local/development-service-account.json');
 try{await fs.access(output);console.log('Development identity already exists locally; reusing it.');return;}catch{}
 const options={project};const account=getGlobalDefaultAccount();
 if(!account)throw Error('Firebase CLI login is required');
 setActiveAccount(options,account);await requireAuth(options);
 await ensure(project,'iam.googleapis.com','Crompton development',true);
 const iam=new Client({urlPrefix:'https://iam.googleapis.com',apiVersion:'v1'});
 const email=`crompton-dev-backend@${project}.iam.gserviceaccount.com`;
 try{await iam.get(`/projects/${project}/serviceAccounts/${email}`);}
 catch(e){if(e.status!==404 && !String(e.message).includes('404'))throw e;await iam.post(`/projects/${project}/serviceAccounts`,{accountId:'crompton-dev-backend',serviceAccount:{displayName:'Crompton development backend only'}});}
 const crm=new Client({urlPrefix:'https://cloudresourcemanager.googleapis.com',apiVersion:'v1'});
 const result=await crm.post(`/projects/${project}:getIamPolicy`,{});
 const policy=result.body;policy.bindings=policy.bindings||[];
 for(const role of ['roles/datastore.user','roles/firebaseauth.admin','roles/firebasecloudmessaging.admin']){
  let binding=policy.bindings.find(b=>b.role===role&&!b.condition);
  if(!binding){binding={role,members:[]};policy.bindings.push(binding);}
  const member='serviceAccount:'+email;if(!binding.members.includes(member))binding.members.push(member);
 }
 await crm.post(`/projects/${project}:setIamPolicy`,{policy});
 const key=await iam.post(`/projects/${project}/serviceAccounts/${email}/keys`,{privateKeyType:'TYPE_GOOGLE_CREDENTIALS_FILE'},{skipLog:{resBody:true}});
 await fs.mkdir(path.dirname(output),{recursive:true});
 await fs.writeFile(output,Buffer.from(key.body.privateKeyData,'base64'),{mode:0o600});
 console.log('Development-only backend identity created in ignored .local/development-service-account.json.');
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
