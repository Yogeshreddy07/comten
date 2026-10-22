const {chromium}=require('@playwright/test');
const fs=require('node:fs/promises');
const path=require('node:path');
const out=path.resolve(__dirname,'../../tests/visual/mobile');
async function type(page,label,value){
 await page.getByRole('textbox',{name:label,exact:true}).click();await page.waitForTimeout(250);await page.keyboard.press('Control+A');await page.keyboard.type(value);
}
async function main(){
 const browser=await chromium.launch();const checks=[],failures=[],fileChecks=[];
 try{
  for(const [code,modules] of Object.entries({CAP001:['Projects','Project Controller Management','Billing Management','Approval','Notifications','Settings'],PC001:['Projects','Employee Management','Billing Management','Activities','Notifications','Settings'],TL001:['Attendance','Timesheet Approvals','Project Database','Status Update','Reason for Delay','Notifications','Settings'],EMP001:['My Projects','Attendance','Timesheet','Notifications','Settings']})){
   if(process.argv.includes('--role') && process.argv[process.argv.indexOf('--role')+1]!==code)continue;
   const context=await browser.newContext({viewport:{width:390,height:844}});const page=await context.newPage();
   page.on('pageerror',e=>failures.push(code+': '+e.message));
   await page.goto('http://127.0.0.1:3008');
   await page.locator('flt-semantics-placeholder').waitFor();await page.locator('flt-semantics-placeholder').evaluate(e=>e.click());
   await page.getByRole('button',{name:'Login',exact:true}).click();
   await type(page,'Employee Code',code);await type(page,'Password','SyntheticPass123!');
   await page.getByRole('button',{name:'Login',exact:true}).click();
   await page.getByRole('button',{name:'Show PIN'}).first().waitFor({timeout:30000});
   for(let i=0;i<2;i++){
    const input=page.getByRole('textbox').nth(i);
    await input.evaluate(e=>e.focus());await page.waitForTimeout(250);await page.keyboard.type('1234');
   }
   await page.getByRole('button',{name:'Continue',exact:true}).click();await page.waitForTimeout(2000);
   if(await page.getByRole('button',{name:'Skip',exact:true}).count())await page.getByRole('button',{name:'Skip',exact:true}).click();
   await page.waitForTimeout(1500);
   await page.screenshot({path:path.join(out,code+'-landing.png')});
   console.log(code+' landing: '+(await page.locator('body').innerText()).slice(0,1700));
   // Gates are part of the preserved flow. Do not bypass state in the test.
   for(let i=0;i<100 && !(await page.locator('body').innerText()).includes('Quick Access');i++){
    const dismiss=page.getByRole('button',{name:/Dismiss/i});
    if(await dismiss.count()){await dismiss.first().click();await page.waitForTimeout(150);continue}
    const continueButton=page.getByRole('button',{name:/^(Continue|Continue to Dashboard)$/i});
    if(await continueButton.count()){await continueButton.click();await page.waitForTimeout(1200);console.log(code+' after gate: '+(await page.locator('body').innerText()).slice(0,2000));break}
    throw Error(code+' did not reach dashboard: '+(await page.locator('body').innerText()).slice(0,700));
   }
   checks.push(code+' login, PIN onboarding, tour and notification gate');
   for(const module of modules){
    const name=new RegExp('^'+module+'(?: |$)');
    const target=page.getByRole('button',{name});
    if(await target.count()) await target.first().click();
    else await page.getByText(name).first().click();
    await page.waitForTimeout(1800);
    if(module==='Timesheet' && await page.getByRole('button',{name:'OK',exact:true}).count()){
     await page.getByRole('button',{name:'OK',exact:true}).click();await page.waitForTimeout(500);checks.push(code+' dismisses missing-timesheet reminder');
    }
    let text=await page.locator('body').innerText();
    const deadline=Date.now()+45000;
    while(/\bLoading\b/i.test(text) && Date.now()<deadline){await page.waitForTimeout(250);text=await page.locator('body').innerText()}
    if(/\bLoading\b/i.test(text))throw Error(code+' '+module+' timed out loading');
    if(/Unable to connect|Unable to load|Failed to load|Permission denied|Firebase is unavailable|Firebase connection timed out|coming soon/i.test(text))throw Error(code+' '+module+' failed: '+text.slice(0,600));
    await page.screenshot({path:path.join(out,`${code}-${module.replaceAll(' ','-')}.png`)});
    checks.push(code+' '+module+' screen loads');
    console.log(code+' '+module+': '+text.slice(0,250));
    if(code==='CAP001' && module==='Project Controller Management'){
     await page.getByRole('button',{name:'Add Project Controller',exact:true}).click();
     const unique='UI'+Date.now();
     for(const [label,value]of [['Name','Synthetic UI Controller'],['Employee Code',unique],['Mobile Number','9000000000'],['Email ID',unique.toLowerCase()+'@example.invalid']])await type(page,label,value);
     await page.mouse.move(190,650);await page.mouse.wheel(0,400);await page.waitForTimeout(300);
     await page.getByRole('button',{name:'Next',exact:true}).click();await page.waitForTimeout(400);
     if(!(await page.locator('body').innerText()).includes('Only .com email addresses are allowed'))throw Error('Existing employee email policy changed');
     await type(page,'Email ID',unique.toLowerCase()+'@example.com');
     await page.getByRole('button',{name:'Next',exact:true}).click();await page.waitForTimeout(400);
     await page.mouse.move(190,650);await page.mouse.wheel(0,400);await page.waitForTimeout(300);
     await page.getByRole('button',{name:'Confirm',exact:true}).click();
     await page.getByRole('button',{name:'Save',exact:true}).click();
     await page.getByRole('button',{name:'Done',exact:true}).waitFor({timeout:30000});
     await page.getByRole('button',{name:'Done',exact:true}).click();await page.waitForTimeout(500);
     checks.push(code+' creates controller through form, review, confirmation and one-time credential dialog');
    }
    if(module==='Activities'){
     await page.getByRole('button',{name:'Add Activity',exact:true}).click();
     await page.getByRole('textbox').click();await page.waitForTimeout(200);await page.keyboard.type('Synthetic UI activity '+Date.now());
     await page.getByRole('button',{name:'Add',exact:true}).click();await page.waitForTimeout(600);
     if((await page.locator('body').innerText()).includes('Permission denied'))throw Error('Activity creation denied');
     checks.push(code+' adds activity through existing dialog');
    }
    if(module==='Settings'){
     await page.getByRole('button',{name:/^Change Password/}).click();await page.waitForTimeout(300);
     if(await page.getByRole('textbox',{name:'Current Password',exact:true}).count()!==1)throw Error('Password form missing');
     await page.getByRole('button',{name:'Back',exact:true}).click();await page.waitForTimeout(400);
     checks.push(code+' password settings navigation');
     const uid={CAP001:1,PC001:2,TL001:3,EMP001:4}[code];let fileRows=[],puts=0;
     await page.route('**/api/files**',async route=>{
      const request=route.request(),uri=new URL(request.url());let data;
      if(uri.pathname.endsWith('/authorize-upload')){
       const body=request.postDataJSON();if(body.targetId!==uid || body.category!=='employee_document')throw Error('Wrong mobile file scope');
       data={id:'a'.repeat(32),url:'https://synthetic.r2.invalid/mobile-object',headers:{'Content-Type':'application/pdf','If-None-Match':'*'}};
      }else if(uri.pathname.endsWith('/complete')){fileRows=[{id:'a'.repeat(32),name:'synthetic.pdf',ownerId:uid,size:18,contentType:'application/pdf'}];data=fileRows[0];}
      else if(uri.pathname.endsWith('/download'))data={url:'https://synthetic.r2.invalid/mobile-object',headers:{'If-Match':'synthetic-etag'}};
      else if(request.method()==='DELETE'){fileRows=[];data=null;}else data=fileRows;
      await route.fulfill({json:{success:true,data,message:'Synthetic'}});
     });
     await page.route('https://synthetic.r2.invalid/**',async route=>{
      const request=route.request();if(request.headers().authorization)throw Error('Mobile bearer leaked to object store');
      if(request.method()==='PUT'){puts++;if(request.headers()['if-none-match']!=='*')throw Error('Missing mobile conditional PUT');}
      await route.fulfill({status:200,headers:{'access-control-allow-origin':'http://127.0.0.1:3008','access-control-allow-methods':'PUT,GET,HEAD,OPTIONS','access-control-allow-headers':'content-type,if-none-match,if-match'},contentType:'application/pdf',body:'%PDF-1.7 synthetic'});
     });
     await page.getByRole('button',{name:/^My attachments/}).click();
     await page.getByText('No attachments yet',{exact:true}).waitFor();fileChecks.push(code+' own file scope and empty state');
     const choose=page.waitForEvent('filechooser');await page.getByRole('button',{name:'Choose file',exact:true}).click();
     await (await choose).setFiles({name:'synthetic.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.7 synthetic')});
     await page.getByRole('button',{name:/^synthetic\.pdf/}).waitFor({timeout:20000}).catch(async error=>{console.log('Attachment state: '+await page.locator('body').innerText());throw error;});if(puts!==1)throw Error('Mobile upload failed');fileChecks.push(code+' picks, streams upload and confirms');
     const download=page.waitForEvent('download');await page.getByRole('button',{name:/^synthetic\.pdf/}).click();
     if((await download).suggestedFilename()!=='synthetic.pdf')throw Error('Wrong mobile download');fileChecks.push(code+' downloads with fresh signed capability');
     await page.screenshot({path:path.join(out,code+'-attachments.png')});
     await page.getByRole('button',{name:'Back',exact:true}).click();
     // Wait for the attachment route to finish popping before the next Back.
     await page.getByRole('button',{name:/^My attachments/}).waitFor();
     await page.waitForTimeout(500);
     await page.unroute('**/api/files**');await page.unroute('https://synthetic.r2.invalid/**');

    }
    const back=page.getByRole('button',{name:'Back',exact:true});
    if(await back.count())await back.first().click();else await page.goBack();
    await page.waitForTimeout(500);
   }
   await page.getByRole('button',{name:'Settings',exact:true}).click();await page.waitForTimeout(500);
   await page.mouse.move(190,650);await page.mouse.wheel(0,600);await page.waitForTimeout(300);
   await page.getByRole('button',{name:'Logout',exact:true}).click();await page.getByRole('button',{name:'Logout',exact:true}).last().click();
   await page.getByRole('button',{name:'Login',exact:true}).waitFor({timeout:20000});
   checks.push(code+' confirms logout and returns to welcome');
   await context.close();
  }
 }catch(e){failures.push(e.message)}finally{await browser.close()}
 await fs.writeFile(path.join(out,'ui-results.json'),JSON.stringify({checks,failures},null,2));
 await fs.writeFile(path.join(out,'file-ui-results.json'),JSON.stringify({provider:'MOCKED',checks:fileChecks,failures},null,2));
 console.log(JSON.stringify({checks,files:fileChecks,failures},null,2));if(failures.length)process.exitCode=1;
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
