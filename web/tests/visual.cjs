const {chromium}=require('@playwright/test');
const fs=require('node:fs/promises');
const path=require('node:path');
async function main(){
 const out=path.resolve('../tests/visual/website');await fs.mkdir(out,{recursive:true});
 const login=await fetch('http://127.0.0.1:8006/api/auth/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({employeeCode:'CAP001',password:'SyntheticPass123!'})}).then(r=>r.json());
 if(!login.success) throw Error('Synthetic login failed');
 const session=login.data;
 const browser=await chromium.launch({headless:true});
 const results=[];
 for(const width of [1440,390]) for(const pageName of ['index.html','dashboard.html','reports/attendance.html','reports/working-hours.html','reports/project-utilization.html','reports/project-billing.html','reports/clients.html','reports/billing-status.html','reports/attendance.html?employee=4','reports/working-hours.html?employee=4','reports/project-utilization.html?project=100','reports/project-utilization.html?project=100&module=101','reports/project-billing.html?project=100','reports/project-billing.html?project=100&module=101','reports/clients.html?client=DEMO-CLIENT']){
  const captures=[];
  for(const [label,port] of [['original',3007],['new',3000]]){
   const context=await browser.newContext({viewport:{width,height:900},deviceScaleFactor:1,colorScheme:'light'});
   const page=await context.newPage();const errors=[];
   page.on('pageerror',e=>errors.push(e.message));
   await page.clock.setFixedTime(new Date('2026-10-15T13:00:00Z'));
   await page.route('**/assets/js/config.js',route=>route.fulfill({contentType:'text/javascript',body:"window.APP_CONFIG={API_BASE_URL:''};"}));
   await page.route('**/api/**',async route=>{
    const url=new URL(route.request().url());
    const r=await context.request.fetch('http://127.0.0.1:8006'+url.pathname+url.search,{method:route.request().method(),headers:{Authorization:'Bearer '+session.token,'Content-Type':'application/json'},data:route.request().postData()||undefined});
    await route.fulfill({response:r});
   });
   if(pageName!=='index.html') await page.addInitScript(({session,label})=>{
    const storage=sessionStorage;
    storage.setItem('session',JSON.stringify(session));localStorage.setItem('sessionLastActivity',String(Date.now()));
   },{session,label});
   await page.goto(`http://127.0.0.1:${port}/${pageName}`,{waitUntil:'networkidle'});
   await page.evaluate(()=>document.fonts.ready);
   await page.screenshot({path:path.join(out,`${label}-${width}-${pageName.replace(/[^a-z0-9.-]/gi,'-')}.png`),fullPage:true});
   let content=await page.locator('body').innerText();
   const addition=label==='new'?await page.locator('[data-attachments]').count():0;
   if(addition){
    if(addition!==1 || await page.locator('[data-attachments]').innerText()!=='Attachments')throw Error('Unexpected visual addition');
    // Retain the actual new UI screenshot above. A second capture isolates
    // unchanged content so the intentional new control cannot hide regressions.
    await page.locator('[data-attachments]').evaluate(node=>node.remove());
    content=await page.locator('body').innerText();
    await page.screenshot({path:path.join(out,`regression-${width}-${pageName.replace(/[^a-z0-9.-]/gi,'-')}.png`),fullPage:true});
   }
   captures.push({label,content,errors,addition});
   await context.close();
  }
  results.push({page:pageName,width,intentionalAttachmentControl:captures[1].addition===1,textMatches:captures[0].content===captures[1].content,errors:captures.flatMap(c=>c.errors)});
 }
 await fs.writeFile(path.join(out,'results.json'),JSON.stringify(results,null,2));
 await browser.close();
 console.log(JSON.stringify(results,null,2));
 if(results.some(r=>!r.textMatches||r.errors.length))process.exitCode=1;
}
main().catch(e=>{console.error(e);process.exitCode=1});
