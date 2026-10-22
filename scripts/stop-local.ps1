$projectRoot=Split-Path $PSScriptRoot -Parent
$state=Join-Path $projectRoot '.local/processes.json'
if(Test-Path -LiteralPath $state) {
  foreach($record in (Get-Content -LiteralPath $state -Raw | ConvertFrom-Json)) {
    $process=Get-CimInstance Win32_Process -Filter "ProcessId=$($record.pid)"
    if($process -and [Math]::Abs(($process.CreationDate.ToUniversalTime()-[datetime]::Parse($record.started).ToUniversalTime()).TotalSeconds) -lt 1) { & taskkill.exe /PID $record.pid /T /F | Out-Null }
  }
  Remove-Item -LiteralPath $state
}
