param([Parameter(Mandatory=$true)][string]$StateDir)
$ErrorActionPreference='SilentlyContinue'
function FindLhmDll {
  $marker=Join-Path $StateDir 'advanced-sensor-library.txt'
  if(Test-Path $marker){try{$m=(Get-Content -LiteralPath $marker -Raw).Trim();if($m -and (Test-Path $m)){return $m}}catch{}}
  $roots=@("$env:ProgramFiles\LibreHardwareMonitor","$env:LOCALAPPDATA\Programs\LibreHardwareMonitor","$env:LOCALAPPDATA\RenNevTweakingUtility\tools\LibreHardwareMonitor","$env:LOCALAPPDATA\Microsoft\WinGet\Packages")
  foreach($r in $roots){if(Test-Path $r){try{$dll=Get-ChildItem $r -Filter LibreHardwareMonitorLib.dll -File -Recurse -ErrorAction SilentlyContinue|Select-Object -First 1;if($dll){return $dll.FullName}}catch{}}}
  return $null
}
New-Item -ItemType Directory -Path $StateDir -Force|Out-Null
$live=Join-Path $StateDir 'advanced-sensor-live.txt';$heartbeat=Join-Path $StateDir 'sensor-heartbeat.txt';$status=Join-Path $StateDir 'advanced-sensors-status.txt'
if(Test-Path $live){try{if(((Get-Date)-(Get-Item $live).LastWriteTime).TotalSeconds -lt 10){exit 0}}catch{}}
$dll=FindLhmDll;if(-not $dll){exit 2}
$worker=Join-Path $PSScriptRoot 'AdvancedSensorWorker.ps1';if(-not (Test-Path $worker)){exit 3}
try{[IO.File]::WriteAllText($heartbeat,(Get-Date -Format o),[Text.Encoding]::ASCII)}catch{}
try{Start-Process -FilePath powershell.exe -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$worker+'"'),'-LibraryPath',('"'+$dll+'"'),'-OutFile',('"'+$live+'"'),'-StatusFile',('"'+$status+'"'),'-HeartbeatFile',('"'+$heartbeat+'"')) -WindowStyle Hidden;exit 0}catch{exit 4}
