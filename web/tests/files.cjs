// Browser UI integration with mocked provider capabilities. Never contacts R2.
const {chromium,expect}=require('@playwright/test');
const fs=require('node:fs/promises');
async function main(){
 const login=await fetch('http://127.0.0.1:8006/api/auth/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({employeeCode:'CAP001',password:'SyntheticPass123!'})}).then(r=>r.json());
 if(!login.success)throw Error('Synthetic login failed');
 const browser=await chromium.launch(),checks=[];
 try{
  for(const width of [390,1440]){
   const context=await browser.newContext({viewport:{width,height:900}}),page=await context.newPage();
   const errors=[];page.on('pageerror',error=>errors.push(error.message));
   await page.addInitScript(session=>{sessionStorage.setItem('session',JSON.stringify(session));localStorage.setItem('sessionLastActivity',String(Date.now()));},login.data);
   let rows=[],uploads=0,deletes=0,fail=false;
   await page.route('**/api/files**',async route=>{
    const request=route.request(),path=new URL(request.url()).pathname;
    let data;
    if(path.endsWith('/authorize-upload')){
     const body=request.postDataJSON();if(body.targetId!==100 || body.category!=='project_attachment')throw Error('Incorrect attachment scope');
     data={id:'a'.repeat(32),url:'https://synthetic.r2.invalid/object',headers:{'Content-Type':'application/pdf','If-None-Match':'*'}};
    }else if(path.endsWith('/complete')){
     rows=[{id:'a'.repeat(32),name:'synthetic.pdf',size:18,contentType:'application/pdf'}];data=rows[0];
    }else if(path.endsWith('/download'))data={url:'https://synthetic.r2.invalid/object',headers:{'If-Match':'synthetic-etag'}};
    else if(request.method()==='DELETE'){deletes++;rows=[];data=null;}
    else data=rows;
    if(fail && request.method()==='GET' && !path.endsWith('/download')){fail=false;return route.fulfill({status:503,json:{success:false,message:'Synthetic provider unavailable'}});}
    await route.fulfill({json:{success:true,data,message:'Synthetic'}});
   });
   await page.route('https://synthetic.r2.invalid/**',async route=>{
    const request=route.request();if(request.headers().authorization)throw Error('Bearer credential leaked to object store');
    if(request.method()==='PUT'){uploads++;if(request.headers()['if-none-match']!=='*')throw Error('Missing create-once header');}
    await route.fulfill({status:200,headers:{'access-control-allow-origin':'http://127.0.0.1:3000'},contentType:'application/pdf',body:'%PDF-1.7 synthetic'});
   });
   await page.goto('http://127.0.0.1:3000/reports/project-billing.html?project=100',{waitUntil:'networkidle'});
   await page.getByRole('button',{name:'Attachments',exact:true}).click();
   await expect(page.getByRole('status')).toHaveText('No attachments yet');checks.push(width+' empty file dialog');
   await page.getByLabel('Choose attachment').setInputFiles({name:'synthetic.pdf',mimeType:'application/pdf',buffer:Buffer.from('%PDF-1.7 synthetic')});
   await expect(page.locator('dialog .card')).toContainText('synthetic.pdf');if(uploads!==1)throw Error('Upload did not run exactly once');checks.push(width+' select, upload and confirm');
   const download=page.waitForEvent('download');await page.getByRole('button',{name:'Download',exact:true}).click();
   if((await download).suggestedFilename()!=='synthetic.pdf')throw Error('Wrong download filename');checks.push(width+' authorized download');
   page.once('dialog',dialog=>dialog.accept());await page.getByRole('button',{name:'Delete',exact:true}).click();
   await expect(page.getByRole('status')).toHaveText('No attachments yet');if(deletes!==1)throw Error('Delete did not run');checks.push(width+' delete and refresh');
   fail=true;await page.getByLabel('Attachment category').selectOption('billing_document');
   await expect(page.getByRole('status')).toHaveText('Synthetic provider unavailable');
   await page.getByRole('button',{name:'Retry',exact:true}).click();await expect(page.getByRole('status')).toHaveText('No attachments yet');checks.push(width+' provider error and retry');
   await page.screenshot({path:`../tests/visual/website/files-${width}.png`});
   await page.getByRole('button',{name:'Close',exact:true}).click();
   if(await page.locator('body').evaluate(node=>node.scrollWidth>innerWidth))throw Error('Attachment control caused horizontal overflow');
   if(errors.length)throw Error(errors.join('; '));checks.push(width+' responsive dialog and close');await context.close();
  }
 }finally{await browser.close();}
 await fs.writeFile('../tests/visual/website/files-results.json',JSON.stringify({provider:'MOCKED',checks,passed:true},null,2));console.log(JSON.stringify({provider:'MOCKED',checks,passed:true},null,2));
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
