param([Parameter(Mandatory=$true)][string]$OutFile)
$ErrorActionPreference='SilentlyContinue'
function Clean($v){if($null -eq $v){return ''};return (([string]$v)-replace '[\r\n\t=]',' ' -replace '\s+',' ').Trim()}
function WriteStatus($status,$message){[IO.File]::WriteAllLines($OutFile,@('status='+$status,'message='+(Clean $message)),[Text.Encoding]::ASCII)}
function FindLhmRoot {
  $roots=@("$env:ProgramFiles\LibreHardwareMonitor","$env:LOCALAPPDATA\Programs\LibreHardwareMonitor","$env:LOCALAPPDATA\RenNevTweakingUtility\tools\LibreHardwareMonitor")
  foreach($r in $roots){
    if(Test-Path (Join-Path $r 'LibreHardwareMonitorLib.dll')){return $r}
    if(Test-Path $r){try{$dll=Get-ChildItem $r -Filter LibreHardwareMonitorLib.dll -File -Recurse -ErrorAction SilentlyContinue|Select-Object -First 1;if($dll){return $dll.Directory.FullName}}catch{}}
  }
  try{$dll=Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter LibreHardwareMonitorLib.dll -File -Recurse -ErrorAction SilentlyContinue|Select-Object -First 1;if($dll){return $dll.Directory.FullName}}catch{}
  return $null
}
$root=FindLhmRoot
if(-not $root){
  $winget=Get-Command winget.exe -ErrorAction SilentlyContinue
  if($winget){
    WriteStatus 'installing' 'Installing LibreHardwareMonitor from Windows Package Manager...'
    & $winget.Source install --id LibreHardwareMonitor.LibreHardwareMonitor -e --source winget --accept-package-agreements --accept-source-agreements --silent | Out-Null
    Start-Sleep -Seconds 2;$root=FindLhmRoot
  }
}
if(-not $root){
  # Fallback: pinned official GitHub release with SHA-256 verification.
  $tools=Join-Path $env:LOCALAPPDATA 'RenNevTweakingUtility\tools';New-Item -ItemType Directory -Path $tools -Force|Out-Null
  $zip=Join-Path $tools 'LibreHardwareMonitor-0.9.6.zip';$dest=Join-Path $tools 'LibreHardwareMonitor'
  $url='https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/v0.9.6/LibreHardwareMonitor.zip'
  $sha='086D9F1B5A99E643EDC2CFAAAC16051685B551E4C5AC0B32A57C58C0E529C001'
  WriteStatus 'installing' 'Downloading the pinned official LibreHardwareMonitor v0.9.6 portable release...'
  try{
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip -ErrorAction Stop
    $got=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToUpperInvariant();if($got -ne $sha){Remove-Item $zip -Force;throw 'SHA-256 verification failed; the sensor package was not used.'}
    if(Test-Path $dest){Remove-Item $dest -Recurse -Force};Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force;Remove-Item $zip -Force
    $root=FindLhmRoot
  }catch{WriteStatus 'failed' ('Advanced sensor download/setup failed: '+$_.Exception.Message);exit 3}
}
if(-not $root){WriteStatus 'failed' 'LibreHardwareMonitorLib.dll could not be located after setup.';exit 4}
$dll=Join-Path $root 'LibreHardwareMonitorLib.dll';$worker=Join-Path $PSScriptRoot 'AdvancedSensorWorker.ps1';$stateDir=Split-Path $OutFile;$marker=Join-Path $stateDir 'advanced-sensor-library.txt';try{[IO.File]::WriteAllText($marker,$dll,[Text.Encoding]::ASCII)}catch{}
if(-not (Test-Path $worker)){WriteStatus 'failed' 'AdvancedSensorWorker.ps1 is missing from the utility folder.';exit 5}
$live=Join-Path $stateDir 'advanced-sensor-live.txt';$heartbeat=Join-Path $stateDir 'sensor-heartbeat.txt'
try{[IO.File]::WriteAllText($heartbeat,(Get-Date -Format o),[Text.Encoding]::ASCII)}catch{}
try{Start-Process -FilePath powershell.exe -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$worker+'"'),'-LibraryPath',('"'+$dll+'"'),'-OutFile',('"'+$live+'"'),'-StatusFile',('"'+$OutFile+'"'),'-HeartbeatFile',('"'+$heartbeat+'"')) -WindowStyle Hidden}catch{WriteStatus 'failed' ('Could not start the advanced sensor worker: '+$_.Exception.Message);exit 6}
for($i=0;$i -lt 36;$i++){Start-Sleep -Milliseconds 500;if(Test-Path $live){$age=((Get-Date)-(Get-Item $live).LastWriteTime).TotalSeconds;if($age -lt 6){WriteStatus 'ok' 'Advanced sensor engine is active. It will stop automatically after the utility closes.';exit 0}}}
if(Test-Path $OutFile){$d=@{};foreach($line in Get-Content $OutFile){$k=$line.IndexOf('=');if($k -gt 0){$d[$line.Substring(0,$k)]=$line.Substring($k+1)}};if($d.status -eq 'failed'){exit 7}}
WriteStatus 'failed' 'LibreHardwareMonitor was installed, but the sensor worker did not produce a fresh snapshot. This hardware/driver may not expose the requested package sensors.'
exit 8
