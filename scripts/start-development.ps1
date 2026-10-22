$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
$identity=Join-Path $projectRoot '.local/development-service-account.json'
if(-not (Test-Path -LiteralPath $identity)) {throw 'Create the development-only backend identity first'}
if((Get-Content -LiteralPath $identity -Raw | ConvertFrom-Json).project_id -ne 'crompton-pms-dev-20261015') {throw 'Unexpected credential project'}
$env:ENVIRONMENT='development'
$env:PROJECT_ID='crompton-pms-dev-20261015'
$env:GOOGLE_APPLICATION_CREDENTIALS=$identity
$env:FIREBASE_API_KEY='AIzaSyAZqQmW5Pzo1EHJjJ-sXXNBp0eT2hTnfdw'
$env:ALLOW_REAL_MESSAGES='false'
$env:MSG91_DISPATCH_ENABLED='false'
$env:ZEPTOMAIL_DISPATCH_ENABLED='false'
$env:FCM_DISPATCH_ENABLED='false'
$recoveryKey=Join-Path $projectRoot '.local/development-recovery.key'
if(-not (Test-Path -LiteralPath $recoveryKey)) {
  $bytes=New-Object byte[] 32
  $random=[Security.Cryptography.RandomNumberGenerator]::Create()
  try {$random.GetBytes($bytes)} finally {$random.Dispose()}
  [IO.File]::WriteAllText($recoveryKey,[Convert]::ToBase64String($bytes))
  Get-Acl -LiteralPath $identity | Set-Acl -LiteralPath $recoveryKey
}
$env:RECOVERY_HMAC_KEY=[IO.File]::ReadAllText($recoveryKey)
$env:WEB_ORIGIN='http://127.0.0.1:3008'
Remove-Item Env:FIRESTORE_EMULATOR_HOST -ErrorAction SilentlyContinue
Remove-Item Env:FIREBASE_AUTH_EMULATOR_HOST -ErrorAction SilentlyContinue
Set-Location (Join-Path $projectRoot 'backend')
& (Join-Path $projectRoot '.venv/Scripts/python.exe') -m uvicorn app.main:app --host 127.0.0.1 --port 8007
