const {chromium}=require('@playwright/test');
const fs=require('node:fs/promises');
const path=require('node:path');
async function main(){
 const cloud=process.argv.includes('--cloud');
 const root=path.resolve('..'),api=`http://127.0.0.1:${cloud?8007:8006}`;
 const fixture=cloud?JSON.parse(await fs.readFile(path.join(root,'.local/development-logins.json'),'utf8')):Object.fromEntries(['CAP001','PC001','TL001','EMP001'].map(employeeCode=>[employeeCode,{employeeCode,password:'SyntheticPass123!'}]));
 const browser=await chromium.launch();
 try {
  const page=await browser.newPage();
  await page.route('**/probe-fixture',r=>r.fulfill({contentType:'application/json',body:JSON.stringify(fixture)}));
  const messages=[];page.on('console',m=>{if(m.text().includes('PMS_JOURNEY_'))messages.push(m.text())});
  await page.goto('http://127.0.0.1:3009');
  const deadline=Date.now()+240000;
  while(!messages.length && Date.now()<deadline) await page.waitForTimeout(250);
  const text=messages.at(-1)||'Journey timed out before emitting a result';
  if(!text.includes('PMS_JOURNEY_PASS')) throw Error(messages.at(-1)||text);
  const result=JSON.parse(text.slice(text.indexOf('PMS_JOURNEY_PASS ')+17).trim());
  const login=await fetch(api+'/api/auth/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(fixture.CAP001)}).then(r=>r.json());
  const reports={};
  for(const [name,url] of Object.entries({attendance:`attendance/employees/${result.employeeId}`,working:`working-hours/employees/${result.employeeId}`,utilization:`projects/${result.projectId}/modules/${result.moduleId}`,billing:`billing/modules/${result.moduleId}`,client:`clients/${result.clientId}`,status:'billing-status'})){
   const r=await fetch(api+'/api/reports/'+url,{headers:{Authorization:'Bearer '+login.data.token}});
   if(!r.ok) throw Error(name+' report failed '+r.status);
   reports[name]=(await r.json()).data;
  }
  if(reports.working.billableHours!==0.02 || reports.utilization.module.actualHours!==0.02 || reports.attendance.presentDays!==1)throw Error('Cross-application report totals disagree');
  result.checks.push('All six FastAPI reporting families read the new workflow','Attendance, working hours and module totals agree');
  result.environment=cloud?'crompton-pms-dev-20261015':'demo-crompton-pms';
  await fs.writeFile(path.join(root,'tests',cloud?'cloud-journey.json':'emulator-journey.json'),JSON.stringify(result,null,2));
  console.log(JSON.stringify(result,null,2));
 }finally{await browser.close()}
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
