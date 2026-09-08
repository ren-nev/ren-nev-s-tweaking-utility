param([Parameter(Mandatory=$true)][string]$Id,[Parameter(Mandatory=$true)][string]$OutFile)
$ErrorActionPreference='SilentlyContinue'
function FindWinget{ $c=Get-Command winget.exe -ErrorAction SilentlyContinue;if($c){return $c.Source};$p=Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe';if(Test-Path $p){return $p};try{$pkg=Get-AppxPackage Microsoft.DesktopAppInstaller|Sort-Object Version -Descending|Select-Object -First 1;if($pkg){$x=Join-Path $pkg.InstallLocation 'winget.exe';if(Test-Path $x){return $x}}}catch{};try{$dirs=Get-ChildItem (Join-Path $env:ProgramFiles 'WindowsApps') -Filter 'Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe' -Directory -ErrorAction SilentlyContinue|Sort-Object Name -Descending;foreach($d in $dirs){$x=Join-Path $d.FullName 'winget.exe';if(Test-Path $x){return $x}}}catch{};return $null }
$wg=FindWinget
if(-not $wg){@('status=failed','message=Windows Package Manager (winget) was not found. Install App Installer from Microsoft Store first.')|Set-Content $OutFile -Encoding ASCII;exit 2}
try{
  $p=Start-Process -FilePath $wg -ArgumentList @('install','--id',$Id,'--exact','--silent','--accept-source-agreements','--accept-package-agreements','--disable-interactivity','--source','winget') -Wait -PassThru -WindowStyle Hidden
  if($p.ExitCode -eq 0){@('status=ok',('message=Installed '+$Id))|Set-Content $OutFile -Encoding ASCII;exit 0}
  @('status=failed',('message=winget exited with code '+$p.ExitCode))|Set-Content $OutFile -Encoding ASCII;exit $p.ExitCode
}catch{@('status=failed',('message='+($_.Exception.Message -replace '[\r\n=]',' ')))|Set-Content $OutFile -Encoding ASCII;exit 3}
