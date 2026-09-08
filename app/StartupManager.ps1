param(
  [ValidateSet('Scan','Set')][string]$Action='Scan',
  [string]$OutFile='',
  [string]$Source='',
  [string]$Name='',
  [string]$NameEncoded='',
  [ValidateSet('0','1')][string]$Enabled='1'
)
$ErrorActionPreference='SilentlyContinue'
function Clean([object]$v){ if($null -eq $v){return ''}; return (([string]$v)-replace "[\r\n\t]",' ' -replace '\s+',' ').Trim() }
function ApprovedPath([string]$s){
  switch($s){
    'HKCURun' {'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'}
    'HKLMRun' {'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'}
    'HKLMRun32' {'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'}
    'UserFolder' {'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'}
    'CommonFolder' {'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'}
    default {''}
  }
}
function BlobEnabled($blob){
  try { $b=@($blob); if($b.Count -lt 1){return $true}; return (([int]$b[0] -band 1) -eq 0) } catch { return $true }
}
function MakeBlob([bool]$on){
  $b=New-Object byte[] 12
  if($on){$b[0]=2}else{$b[0]=3;[Array]::Copy([BitConverter]::GetBytes((Get-Date).ToFileTime()),0,$b,4,8)}
  return $b
}
function ReadApproved([string]$s,[string]$n){
  $p=ApprovedPath $s;if(-not $p){return $null}
  try { $o=Get-ItemProperty -LiteralPath $p -ErrorAction Stop; if($o.PSObject.Properties[$n]){return $o.PSObject.Properties[$n].Value} } catch {}
  return $null
}
function IsRecommended([string]$name,[string]$cmd){
  $x=(($name+' '+$cmd).ToLowerInvariant())
  return [bool]($x -match 'discord|spotify|steam|epicgameslauncher|epic games|msteams|teams\.exe|onedrive|creative cloud|ccxprocess|battle\.net|overwolf|skype|telegram|whatsapp|riotclient|riot client|eadesktop|ea desktop|adobe updater|googleupdate|opera browser assistant')
}

function IsProtected([string]$name,[string]$cmd){
  $x=(($name+' '+$cmd).ToLowerInvariant())
  return [bool]($x -match 'securityhealth|windows defender|microsoft defender|antivirus|antimalware|realtek.*audio|rtkaud|nahimic|synaptics|elan.*touch|touchpad|fingerprint|biometric|intel.*graphics|nvidia.*container|amd.*external events|audio service|bluetooth.*driver|wireless.*driver|wifi.*driver')
}
function AddRow([System.Collections.ArrayList]$rows,$id,$name,$cmd,$source,$where,$scope,[bool]$enabled,[bool]$recommended){
  $protected=IsProtected $name $cmd
  [void]$rows.Add([pscustomobject]@{Id=$id;Name=(Clean $name);Command=(Clean $cmd);Source=$source;Where=$where;Scope=$scope;Enabled=$enabled;Recommended=($recommended -and -not $protected);Protected=$protected})
}

function ScanItems {
  $rows=New-Object System.Collections.ArrayList
  $keys=@(
    @{Source='HKCURun';Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';Scope='this account'},
    @{Source='HKLMRun';Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';Scope='all users'},
    @{Source='HKLMRun32';Path='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';Scope='all users (32-bit)'}
  )
  foreach($k in $keys){
    if(-not (Test-Path -LiteralPath $k.Path)){continue}
    $p=Get-ItemProperty -LiteralPath $k.Path -ErrorAction SilentlyContinue
    foreach($v in @($p.PSObject.Properties)){
      if($v.Name -like 'PS*'){continue}
      $en=BlobEnabled (ReadApproved $k.Source $v.Name)
      AddRow $rows ($k.Source+'|'+$v.Name) $v.Name $v.Value $k.Source 'Registry Run' $k.Scope $en (IsRecommended $v.Name $v.Value)
    }
  }
  $folders=@(
    @{Source='UserFolder';Path=(Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup');Scope='this account'},
    @{Source='CommonFolder';Path=(Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup');Scope='all users'}
  )
  foreach($f in $folders){
    if(-not (Test-Path -LiteralPath $f.Path)){continue}
    foreach($file in @(Get-ChildItem -LiteralPath $f.Path -File -ErrorAction SilentlyContinue)){
      if($file.Name -eq 'desktop.ini'){continue}
      $en=BlobEnabled (ReadApproved $f.Source $file.Name)
      AddRow $rows ($f.Source+'|'+$file.Name) ([IO.Path]::GetFileNameWithoutExtension($file.Name)) $file.FullName $f.Source 'Startup folder' $f.Scope $en (IsRecommended $file.Name $file.FullName)
    }
  }
  try{
    foreach($task in @(Get-ScheduledTask -ErrorAction Stop)){
      if($task.TaskPath -like '\Microsoft\*'){continue}
      $hasLogon=@($task.Triggers | Where-Object { $_ -and $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }).Count -gt 0
      if(-not $hasLogon){continue}
      $full=$task.TaskPath.TrimEnd('\')+'\'+$task.TaskName
      $cmd=(@($task.Actions|ForEach-Object {[string]$_.Execute}) -join ' ').Trim()
      $en=([string]$task.State -ne 'Disabled')
      AddRow $rows ('Task|'+$full) $task.TaskName $cmd 'Task' 'Scheduled task at logon' ($task.TaskPath.TrimEnd('\')) $en (IsRecommended $task.TaskName $cmd)
    }
  }catch{}
  return @($rows|Sort-Object -Property @{Expression='Recommended';Descending=$true},Name)
}
function SetItemState([string]$s,[string]$n,[bool]$on){
  if($s -eq 'Task'){
    try{
      $leaf=Split-Path -Path $n -Leaf;$path=Split-Path -Path $n -Parent
      if([string]::IsNullOrWhiteSpace($path)){$path='\'};if(-not $path.StartsWith('\')){$path='\'+$path};if(-not $path.EndsWith('\')){$path+='\'}
      $t=Get-ScheduledTask -TaskPath $path -TaskName $leaf -ErrorAction Stop
      if($on){$t|Enable-ScheduledTask -ErrorAction Stop|Out-Null}else{$t|Disable-ScheduledTask -ErrorAction Stop|Out-Null}
      return $true
    }catch{return $false}
  }
  $p=ApprovedPath $s;if(-not $p){return $false}
  try{
    if(-not (Test-Path -LiteralPath $p)){New-Item -Path $p -Force|Out-Null}
    New-ItemProperty -LiteralPath $p -Name $n -PropertyType Binary -Value (MakeBlob $on) -Force -ErrorAction Stop|Out-Null
    return $true
  }catch{return $false}
}
if($Action -eq 'Set'){
  if($NameEncoded){ try{$Name=[uri]::UnescapeDataString($NameEncoded)}catch{} }
  $want=($Enabled -eq '1')
  $ok=SetItemState $Source $Name $want
  if($OutFile){@('status='+(if($ok){'ok'}else{'failed'}),'enabled='+$want,'source='+(Clean $Source),'name='+(Clean $Name))|Set-Content -LiteralPath $OutFile -Encoding ASCII}
  if($ok){exit 0}else{exit 2}
}
$items=ScanItems
$lines=New-Object System.Collections.Generic.List[string]
$lines.Add('status=ok');$lines.Add('count='+$items.Count);$lines.Add('recommended='+(@($items|Where-Object {$_.Recommended -and $_.Enabled}).Count));$lines.Add('enabled='+(@($items|Where-Object {$_.Enabled}).Count))
foreach($x in $items){
  $lines.Add(('item='+[uri]::EscapeDataString($x.Id)+'|'+[uri]::EscapeDataString($x.Name)+'|'+[uri]::EscapeDataString($x.Command)+'|'+$x.Source+'|'+[uri]::EscapeDataString($x.Where)+'|'+[uri]::EscapeDataString($x.Scope)+'|'+$(if($x.Enabled){'1'}else{'0'})+'|'+$(if($x.Recommended){'1'}else{'0'})+'|'+$(if($x.Protected){'1'}else{'0'})))
}
if($OutFile){[IO.File]::WriteAllLines($OutFile,$lines,[Text.Encoding]::ASCII)}else{$lines}
