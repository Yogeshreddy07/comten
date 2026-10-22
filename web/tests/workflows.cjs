const {chromium}=require('@playwright/test');
const fs=require('node:fs/promises');
const path=require('node:path');
async function main(){
 const cloud=process.argv.includes('--cloud');
 const android=process.argv.includes('--android');
 const fixture=cloud?JSON.parse(await fs.readFile(path.resolve('../.local/development-logins.json'),'utf8')):null;
 const journey=android?JSON.parse(await fs.readFile(path.resolve('../tests/android/device-results.json'),'utf8')).workflow:cloud?JSON.parse(await fs.readFile(path.resolve('../tests/cloud-journey.json'),'utf8')):{employeeId:4,projectId:100,clientId:'DEMO-CLIENT'};
 if(android && !cloud)throw Error('Android workflow reporting requires development cloud mode');
 const browser=await chromium.launch();
 const context=await browser.newContext({acceptDownloads:true});
 const page=await context.newPage();const failures=[];
 if(cloud)await page.route('**/api/**',async route=>{
  const request=route.request(),url=new URL(request.url());
  const response=await context.request.fetch('http://127.0.0.1:8007'+url.pathname+url.search,{method:request.method(),headers:request.headers(),data:request.postData()||undefined});
  await route.fulfill({response});
 });
 page.on('pageerror',e=>failures.push(e.message));
 page.on('dialog',async d=>{failures.push(d.message());await d.dismiss()});
 await page.goto('http://127.0.0.1:3000/index.html');
 await page.locator('#identifier').fill('CAP001');await page.locator('#password').fill(cloud?fixture.CAP001.password:'SyntheticPass123!');
 await page.getByRole('button',{name:'Sign in',exact:true}).click();
 await page.waitForURL('**/dashboard.html');
 await page.waitForLoadState('networkidle');
 if(!(await page.locator('body').innerText()).includes(cloud?'Welcome, Synthetic Development Captain':'Welcome, Demo Captain'))throw Error('Dashboard did not load authenticated API data');
 const urls=['reports/attendance.html',`reports/attendance.html?employee=${journey.employeeId}`,`reports/working-hours.html?employee=${journey.employeeId}`,`reports/project-utilization.html?project=${journey.projectId}`,`reports/project-billing.html?project=${journey.projectId}`,`reports/clients.html?client=${journey.clientId}`,'reports/billing-status.html'];
 const checks=[],exports=[];
 for(const url of urls){
  await page.goto('http://127.0.0.1:3000/'+url,{waitUntil:'networkidle'});
  if(await page.locator('canvas').count()) await page.locator('canvas').first().waitFor();
  const text=await page.locator('body').innerText();
  if(text.includes('Request failed')||text.includes('Cannot reach'))throw Error(url+' failed');
  checks.push(url);
 }
 const out=path.resolve(android?'../tests/exports/android':cloud?'../tests/exports/cloud':'../tests/exports');await fs.mkdir(out,{recursive:true});
 for(const name of ['attendance','working-hours','project-billing','project-utilization','clients','billing-status']){
  await page.goto(`http://127.0.0.1:3000/reports/${name}.html`,{waitUntil:'networkidle'});
  await page.evaluate(()=>{const original=window.xlsxExport.download;window.__exported=[];window.xlsxExport.download=(name,sheets)=>{window.__exported.push({name,sheets});return original(name,sheets)}});
  const download=page.waitForEvent('download',{timeout:20000});
  await page.getByRole('button',{name:/Excel/}).first().click();
  if(await page.locator('dialog[open]').count()){
   if(cloud && name==='project-billing')await page.locator('dialog select').first().selectOption(String(journey.projectId));
   await page.getByRole('button',{name:'Generate',exact:true}).click();
  }
  const file=await download;await file.saveAs(path.join(out,file.suggestedFilename()));exports.push(...await page.evaluate(()=>window.__exported));checks.push(name+' XLSX downloaded');
 }
 await fs.writeFile(path.join(out,'expected-cells.json'),JSON.stringify(exports,null,2));
 await fs.writeFile(path.resolve(android?'../tests/android/website-workflow-results.json':cloud?'../tests/visual/website/cloud-workflow-results.json':'../tests/visual/website/workflow-results.json'),JSON.stringify({checks,failures},null,2));
 await browser.close();console.log(JSON.stringify({checks,failures},null,2));
 if(failures.length)process.exitCode=1;
}
main().catch(e=>{console.error(e);process.exitCode=1});
