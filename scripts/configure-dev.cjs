// Uses the existing Firebase CLI login in memory; never saves or prints credentials.
const path = require('node:path');
const base=path.join(path.dirname(process.execPath),'node_modules/firebase-tools/lib');
const {getGlobalDefaultAccount,setActiveAccount}=require(path.join(base,'auth'));
const {requireAuth}=require(path.join(base,'requireAuth'));
const {ensure}=require(path.join(base,'ensureApiEnabled'));
const {Client}=require(path.join(base,'apiv2'));
async function main(){
  const project='crompton-pms-dev-20261015';
  const opts={project};
  const account=getGlobalDefaultAccount();
  if(!account) throw new Error('Run firebase login first');
  setActiveAccount(opts,account);
  await requireAuth(opts);
  for(const api of ['firestore.googleapis.com','identitytoolkit.googleapis.com','firebaseappcheck.googleapis.com','fcm.googleapis.com']) await ensure(project,api,'Crompton development',true);
  const authClient=new Client({urlPrefix:'https://identitytoolkit.googleapis.com',apiVersion:'v2'});
  await authClient.patch(`/projects/${project}/config`,{passwordPolicyConfig:{passwordPolicyEnforcementState:'ENFORCE',passwordPolicyVersions:[{customStrengthOptions:{minPasswordLength:8,maxPasswordLength:128,containsLowercaseCharacter:true,containsUppercaseCharacter:true,containsNumericCharacter:true,containsNonAlphanumericCharacter:true}}]}},{queryParams:{updateMask:'passwordPolicyConfig'}});
  console.log('Run firebase deploy --only auth,firestore --project '+project+' from firebase/ to provision email/password Auth and rules using the supported Firebase CLI.');
  console.log('Development APIs and email/password authentication configured. No billing enabled.');
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
