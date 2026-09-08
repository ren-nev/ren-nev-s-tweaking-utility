param([Parameter(Mandatory=$true)][string]$OutFile)
$ErrorActionPreference='SilentlyContinue'
function Clean($v){if($null -eq $v){return ''};return (([string]$v)-replace '[\r\n\t=]',' ' -replace '\s+',' ').Trim()}
$fnExe='';$fnRoot='';$fnVer='';$fnCfg=Join-Path $env:LOCALAPPDATA 'FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini';$epicExe=''
try{
  $dat=Join-Path $env:ProgramData 'Epic\UnrealEngineLauncher\LauncherInstalled.dat'
  if(Test-Path $dat){
    $j=Get-Content $dat -Raw|ConvertFrom-Json
    $e=@($j.InstallationList|Where-Object {$_.AppName -eq 'Fortnite' -or $_.ArtifactId -eq 'Fortnite'})|Select-Object -First 1
    if($e){$fnRoot=[string]$e.InstallLocation;$fnVer=[string]$e.AppVersion}
  }
}catch{}
if(-not $fnRoot){
  try{
    $manifestDir=Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    foreach($f in @(Get-ChildItem $manifestDir -Filter *.item -File -ErrorAction SilentlyContinue)){
      try{$m=Get-Content $f.FullName -Raw|ConvertFrom-Json}catch{continue}
      if($m.AppName -eq 'Fortnite' -or $m.DisplayName -eq 'Fortnite'){$fnRoot=[string]$m.InstallLocation;$fnVer=[string]$(if($m.AppVersionString){$m.AppVersionString}else{$m.AppVersion});break}
    }
  }catch{}
}
if($fnRoot){$p=Join-Path $fnRoot 'FortniteGame\Binaries\Win64\FortniteClient-Win64-Shipping.exe';if(Test-Path $p){$fnExe=$p}}
foreach($p in @("${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe","${env:ProgramFiles(x86)}\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe")){if(Test-Path $p){$epicExe=$p;break}}
$rbExe='';$rbType='';$rbVersion=''
try{
  $r=Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Roblox\Versions') -Filter RobloxPlayerBeta.exe -Recurse -File -ErrorAction Stop|Sort-Object LastWriteTime -Descending|Select-Object -First 1
  if($r){$rbExe=$r.FullName;$rbType='Desktop';$rbVersion=$r.Directory.Name}
}catch{}
$rbProto=$false;try{$null=Get-Item Registry::HKEY_CLASSES_ROOT\roblox-player -ErrorAction Stop;$rbProto=$true}catch{}
$rbStore='';if(-not $rbExe){try{$rbStore=(Get-StartApps|Where-Object {$_.Name -like '*Roblox*' -and $_.Name -notlike '*Studio*'}|Select-Object -First 1 -ExpandProperty AppID)}catch{};if($rbStore){$rbType='Store'}}
$lines=@(
 'status=ok',('fortniteInstalled='+$(if($fnExe -or $fnRoot){'true'}else{'false'})),('fortniteExe='+(Clean $fnExe)),('fortniteRoot='+(Clean $fnRoot)),('fortniteVersion='+(Clean $fnVer)),('fortniteConfig='+(Clean $fnCfg)),('fortniteConfigExists='+$(if(Test-Path $fnCfg){'true'}else{'false'})),('epicExe='+(Clean $epicExe)),
 ('robloxInstalled='+$(if($rbExe -or $rbProto -or $rbStore){'true'}else{'false'})),('robloxExe='+(Clean $rbExe)),('robloxType='+(Clean $rbType)),('robloxVersion='+(Clean $rbVersion)),('robloxProtocol='+$(if($rbProto){'true'}else{'false'})),('robloxStoreId='+(Clean $rbStore)),('timestamp='+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
)
[IO.File]::WriteAllLines($OutFile,$lines,[Text.Encoding]::ASCII)
