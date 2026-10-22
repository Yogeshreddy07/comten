const {chromium}=require('@playwright/test');
const fs=require('node:fs/promises');
async function main(){
 const browser=await chromium.launch(),checks=[];
 try{
  for(const [code,allowed]of [['CAP001',true],['PC001',true],['TL001',false],['EMP001',false]]){
   const context=await browser.newContext(),page=await context.newPage();
   await page.goto('http://127.0.0.1:3000/index.html');
   await page.locator('#identifier').fill(code);await page.locator('#password').fill('SyntheticPass123!');
   await page.getByRole('button',{name:'Sign in',exact:true}).click();
   if(allowed){
    await page.waitForURL('**/dashboard.html');
    await page.getByRole('button',{name:'Log out',exact:true}).click();
    await page.waitForURL('**/index.html');
    if(await page.evaluate(()=>sessionStorage.getItem('session'))!==null)throw Error('Logout retained session');
    checks.push(code+' website login and logout');
   }else{
    await page.locator('#error.show').waitFor();
    if(!(await page.locator('#error').innerText()).includes('do not have permission'))throw Error('Wrong role rejection');
    if(await page.evaluate(()=>sessionStorage.getItem('session'))!==null)throw Error('Rejected role stored a session');
    checks.push(code+' website access rejected');
   }
   await page.goto('http://127.0.0.1:3000/reports/attendance.html');await page.waitForURL('**/index.html');
   checks.push(code+' unauthenticated report navigation rejected');
   await context.close();
  }
 }finally{await browser.close()}
 await fs.writeFile('../tests/visual/website/auth-results.json',JSON.stringify({checks,passed:true},null,2));console.log(JSON.stringify(checks,null,2));
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
