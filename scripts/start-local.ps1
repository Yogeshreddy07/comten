param([switch]$Mobile)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$env:ENVIRONMENT='local'
$env:PROJECT_ID='demo-crompton-pms'
$env:FIREBASE_API_KEY='demo-key'
$env:FIRESTORE_EMULATOR_HOST='127.0.0.1:8086'
$env:FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9099'
$env:ALLOW_REAL_MESSAGES='false'
$env:MSG91_DISPATCH_ENABLED='false'
$env:ZEPTOMAIL_DISPATCH_ENABLED='false'
$env:FCM_DISPATCH_ENABLED='false'
$runtime=Join-Path $projectRoot '.local'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$ports=@(3000,4006,8006,8086,9099)
if($Mobile){$ports+=3008}
foreach($port in $ports) {
  if(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {throw "Port $port is already in use. Reuse the running stack or stop its owned processes first."}
}
$children=@()
function Start-Component($Name,$Program,$Arguments,$Directory) {
  $process=Start-Process -FilePath $Program -ArgumentList $Arguments -WorkingDirectory $Directory -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runtime "$Name.out.log") -RedirectStandardError (Join-Path $runtime "$Name.err.log")
  $script:children+=@{name=$Name;pid=$process.Id;started=$process.StartTime.ToUniversalTime().ToString('o')}
  $script:children | ConvertTo-Json | Set-Content (Join-Path $runtime 'processes.json')
}
Start-Component 'emulators' 'firebase.exe' @('emulators:start','--only','auth,firestore','--project','demo-crompton-pms') (Join-Path $projectRoot 'firebase')
$ready=$false
for($attempt=0;$attempt -lt 30;$attempt++) {
  try { Invoke-RestMethod 'http://127.0.0.1:9099/' -TimeoutSec 1 | Out-Null;$ready=$true;break } catch {Start-Sleep -Seconds 1}
}
if(-not $ready) { throw 'Emulators did not become ready; inspect .local logs' }
& (Join-Path $projectRoot '.venv/Scripts/python.exe') (Join-Path $PSScriptRoot 'seed.py')
if($LASTEXITCODE -ne 0) {throw 'Synthetic seeding failed; inspect the emulator logs'}
Start-Component 'backend' (Join-Path $projectRoot '.venv/Scripts/python.exe') @('-m','uvicorn','app.main:app','--host','127.0.0.1','--port','8006') (Join-Path $projectRoot 'backend')
Start-Component 'web' 'npm.exe' @('run','dev') (Join-Path $projectRoot 'web')
if($Mobile) {Start-Component 'mobile' 'python.exe' @('-m','http.server','3008','--bind','127.0.0.1','--directory','mobile/build/web') $projectRoot}
$children | ConvertTo-Json | Set-Content (Join-Path $runtime 'processes.json')
Write-Output 'Reports: http://127.0.0.1:3000 | API: http://127.0.0.1:8006/docs | Emulators: http://127.0.0.1:4006'
