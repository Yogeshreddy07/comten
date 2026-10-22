// Real Firebase/FastAPI/R2 browser checks. Only disposable synthetic files.
const {chromium,expect}=require('@playwright/test');
const fs=require('node:fs/promises');
const path=require('node:path');
const root=path.resolve(__dirname,'../..');
const out=path.join(root,'tests/visual/providers');
const checks=[];const created=[];let stage='initialization';
async function main(){
 await fs.mkdir(out,{recursive:true});
 const logins=JSON.parse(await fs.readFile(path.join(root,'.local/development-logins.json'),'utf8'));
 const journey=JSON.parse(await fs.readFile(path.join(root,'tests/cloud-journey.json'),'utf8'));
 const browser=await chromium.launch();
 try{
  if(!process.argv.includes('--mobile-only')){
   stage='website cloud authentication';
   const context=await browser.newContext({viewport:{width:1440,height:900},acceptDownloads:true});
   const page=await context.newPage();
   if(process.argv.includes('--direct'))page.on('response',async response=>{
    if(response.url().endsWith('/files/authorize-upload')&&response.ok())created.push({id:(await response.json()).data.id,role:'CAP001'});
   });
   else await page.route('**/api/**',async route=>{
    try{
     const request=route.request(),url=new URL(request.url());
     const response=await context.request.fetch('http://127.0.0.1:8007'+url.pathname+url.search,{method:request.method(),headers:request.headers(),data:request.postData()||undefined});
     if(url.pathname.endsWith('/files/authorize-upload')&&response.ok())created.push({id:(await response.json()).data.id,role:'CAP001'});
     await route.fulfill({response});
    }catch{await route.abort().catch(()=>{});} // Never log request errors with Authorization headers.
   });
   page.on('request',request=>{if(request.url().includes('.r2.cloudflarestorage.com/')&&request.headers().authorization)throw Error('Unexpected bearer on object request');});
   await page.goto('http://127.0.0.1:3000/index.html');
   await page.locator('#identifier').fill('CAP001');await page.locator('#password').fill(logins.CAP001.password);
   await page.getByRole('button',{name:'Sign in',exact:true}).click();await page.waitForURL('**/dashboard.html');
   checks.push('Website uses real development Firebase login through FastAPI');
   stage='website project attachment navigation';
   await page.goto(`http://127.0.0.1:3000/reports/project-billing.html?project=${journey.projectId}`,{waitUntil:'networkidle'});
   await page.getByRole('button',{name:'Attachments',exact:true}).click();
   for(const [category,label] of [['project_attachment','project'],['billing_document','billing']]){
    stage='website '+label+' real R2 workflow';
    await page.getByLabel('Attachment category').selectOption(category);
    const name='synthetic-live-'+Date.now()+'.pdf';
    await page.getByLabel('Choose attachment').setInputFiles({name,mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.7 synthetic live browser')});
    const card=page.locator('dialog .card').filter({hasText:name});await expect(card).toBeVisible({timeout:45000});
    checks.push('Website '+label+' file selected, real R2 PUT and server confirmation');
    const downloading=page.waitForEvent('download');await card.getByRole('button',{name:'Download',exact:true}).click();
    const download=await downloading;if(download.suggestedFilename()!==name)throw Error('Wrong file name');
    const bytes=await fs.readFile(await download.path());if(bytes.toString()!=='%PDF-1.7 synthetic live browser')throw Error('Wrong file bytes');
    checks.push('Website '+label+' real browser CORS and signed GET bytes');
    await page.screenshot({path:path.join(out,'website-'+label+'-live.png')});
    page.once('dialog',d=>d.accept());await card.getByRole('button',{name:'Delete',exact:true}).click();
    await expect(card).toHaveCount(0,{timeout:30000});checks.push('Website '+label+' delete and refreshed listing');
   }
   await page.getByRole('button',{name:'Close',exact:true}).click();
   await page.unrouteAll({behavior:'wait'});
   await context.close();
  }
  if(!process.argv.includes('--website-only')){
   stage='Flutter cloud authentication';
   const context=await browser.newContext({viewport:{width:390,height:844},acceptDownloads:true});
   const page=await context.newPage();
   page.on('response',async response=>{if(response.url().endsWith('/files/authorize-upload')&&response.ok())created.push({id:(await response.json()).data.id,role:'EMP001'});});
   page.on('request',request=>{if(request.url().includes('.r2.cloudflarestorage.com/')&&request.headers().authorization)throw Error('Unexpected bearer on object request');});
   await page.goto('http://127.0.0.1:3008');await page.locator('flt-semantics-placeholder').waitFor();await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
   await page.getByRole('button',{name:'Login',exact:true}).click();
   for(const [label,value] of [['Employee Code','EMP001'],['Password',logins.EMP001.password]]){
    await page.getByRole('textbox',{name:label,exact:true}).click();await page.waitForTimeout(250);await page.keyboard.type(value);
   }
   await page.getByRole('button',{name:'Login',exact:true}).click();await page.getByRole('button',{name:'Show PIN'}).first().waitFor({timeout:45000});
   for(let i=0;i<2;i++){await page.getByRole('textbox').nth(i).evaluate(e=>e.focus());await page.waitForTimeout(250);await page.keyboard.type('1234');}
   await page.getByRole('button',{name:'Continue',exact:true}).click();await page.waitForTimeout(1500);
   if(await page.getByRole('button',{name:'Skip',exact:true}).count())await page.getByRole('button',{name:'Skip',exact:true}).click();
   await page.waitForTimeout(1500);
   for(let i=0;i<100 && !(await page.locator('body').innerText()).includes('Quick Access');i++){
    const dismiss=page.getByRole('button',{name:/Dismiss/i});if(await dismiss.count()){await dismiss.first().click();await page.waitForTimeout(200);continue;}
    const next=page.getByRole('button',{name:/^(Continue|Continue to Dashboard)$/i});if(await next.count()){await next.click();await page.waitForTimeout(1500);break;}
    throw Error('Unexpected onboarding gate');
   }
   checks.push('Flutter real Firebase login, PIN and preserved onboarding');
   await page.getByRole('button',{name:/^Settings/}).first().click();await page.waitForTimeout(500);
   await page.getByRole('button',{name:/^My attachments/}).click();
   stage='Flutter real R2 file workflow';
   await page.getByRole('button',{name:'Choose file',exact:true}).waitFor();
   const name='synthetic-flutter-'+Date.now()+'.pdf';
   const chooser=page.waitForEvent('filechooser');await page.getByRole('button',{name:'Choose file',exact:true}).click();
   await (await chooser).setFiles({name,mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.7 synthetic Flutter browser')});
   const tile=page.getByRole('button',{name:new RegExp('^'+name.replaceAll('.','\\.'))});await tile.waitFor({timeout:45000});
   checks.push('Flutter picker, real R2 PUT and FastAPI confirmation');
   const downloading=page.waitForEvent('download');await tile.click();const download=await downloading;
   if(download.suggestedFilename()!==name)throw Error('Wrong Flutter filename');
   if((await fs.readFile(await download.path())).toString()!=='%PDF-1.7 synthetic Flutter browser')throw Error('Wrong Flutter bytes');
   checks.push('Flutter real browser CORS and private signed download bytes');
   await page.screenshot({path:path.join(out,'flutter-live-file.png')});
   await context.close();
  }
 }finally{
  await browser.close();
  for(const file of created){
   const response=await fetch('http://127.0.0.1:8007/api/auth/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({employeeCode:file.role,password:logins[file.role].password})});
   const token=(await response.json()).data.token;
   const removed=await fetch('http://127.0.0.1:8007/api/files/'+file.id,{method:'DELETE',headers:{Authorization:'Bearer '+token}});
   if(!removed.ok)throw Error('Synthetic file cleanup failed');
  }
 }
}
main().then(async()=>{const result={provider:'LIVE_R2',checks,passed:true,cleanupRequests:created.length};await fs.writeFile(path.join(out,process.argv.includes('--mobile-only')?'mobile-live-results.json':'website-live-results.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));}).catch(async error=>{const reason=String(error.message).replace(/https?:\/\/[^\s"'<>]+/g,'[URL]').replace(/\b[A-Za-z0-9_-]{32,}\b/g,'[REDACTED]').slice(0,800);console.error(JSON.stringify({provider:'LIVE_R2',checks,passed:false,failedStage:stage,reason}));process.exitCode=1;});
