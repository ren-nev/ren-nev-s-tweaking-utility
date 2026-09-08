param(
  [Parameter(Mandatory=$true)][string]$LibraryPath,
  [Parameter(Mandatory=$true)][string]$OutFile,
  [string]$StatusFile='',
  [string]$HeartbeatFile=''
)
$ErrorActionPreference='SilentlyContinue'
function SafeText($v){if($null -eq $v){return ''};return (([string]$v)-replace '[\r\n\t=]',' ' -replace '\s+',' ').Trim()}
function WriteStatus($state,$message){if($StatusFile){[IO.File]::WriteAllLines($StatusFile,@('status='+$state,'message='+(SafeText $message)),[Text.Encoding]::ASCII)}}
$created=$false
try{$mutex=[System.Threading.Mutex]::new($true,'Global\RenNevAdvancedSensorWorker',[ref]$created)}catch{$created=$true}
if(-not $created){WriteStatus 'ok' 'Advanced sensor worker is already running.';exit 0}
try{
  if(-not (Test-Path $LibraryPath)){throw 'LibreHardwareMonitorLib.dll was not found.'}
  $libDir=Split-Path $LibraryPath
  Push-Location $libDir
  [void][Reflection.Assembly]::LoadFrom($LibraryPath)
  $computer=New-Object LibreHardwareMonitor.Hardware.Computer
  $computer.IsCpuEnabled=$true;$computer.IsGpuEnabled=$true;$computer.IsMemoryEnabled=$false;$computer.IsMotherboardEnabled=$false;$computer.IsStorageEnabled=$false;$computer.IsNetworkEnabled=$false
  $computer.Open();WriteStatus 'ok' 'Advanced sensor engine is active.'
  $started=Get-Date
  while($true){
    # Avoid leaving an invisible worker around forever after the utility has closed.
    if($HeartbeatFile -and (Test-Path $HeartbeatFile)){
      try{if(((Get-Date)-(Get-Item $HeartbeatFile).LastWriteTime).TotalSeconds -gt 45){break}}catch{}
    }elseif(((Get-Date)-$started).TotalMinutes -gt 10){break}

    $cpuTemp=$null;$gpuTemp=$null;$cpuLoad=$null;$gpuLoad=$null;$cpuName='CPU';$gpuName='GPU';$cpuTempName='';$gpuTempName=''
    foreach($hw in @($computer.Hardware)){
      try{$hw.Update()}catch{};foreach($sub in @($hw.SubHardware)){try{$sub.Update()}catch{}}
      $type=[string]$hw.HardwareType
      if($type -eq 'Cpu'){$cpuName=SafeText $hw.Name};if($type -match '^Gpu'){$gpuName=SafeText $hw.Name}
      foreach($sensor in @($hw.Sensors)){
        $stype=[string]$sensor.SensorType;$name=SafeText $sensor.Name;$val=$sensor.Value;if($null -eq $val){continue};$v=[double]$val
        if($type -eq 'Cpu'){
          if($stype -eq 'Temperature' -and $v -gt 0 -and $v -lt 130){$score=0;if($name -match '(?i)Package|Tctl|Tdie|Core Max'){$score=30}elseif($name -match '(?i)Core'){$score=15};if($score -gt 0 -and ($null -eq $cpuTemp -or $v -gt $cpuTemp)){$cpuTemp=$v;$cpuTempName=$name}}
          if($stype -eq 'Load' -and $name -match '(?i)Total CPU|CPU Total' -and $v -ge 0 -and $v -le 100){$cpuLoad=$v}
        }elseif($type -match '^Gpu'){
          if($stype -eq 'Temperature' -and $v -gt 0 -and $v -lt 130 -and $name -notmatch '(?i)Memory|Hot Spot|Hotspot'){if($null -eq $gpuTemp -or $name -match '(?i)Core'){$gpuTemp=$v;$gpuTempName=$name}}
          if($stype -eq 'Load' -and $name -match '(?i)GPU Core|D3D 3D|Core' -and $v -ge 0 -and $v -le 100){if($null -eq $gpuLoad -or $v -gt $gpuLoad){$gpuLoad=$v}}
        }
      }
      foreach($sub in @($hw.SubHardware)){
        foreach($sensor in @($sub.Sensors)){
          $stype=[string]$sensor.SensorType;$name=SafeText $sensor.Name;$val=$sensor.Value;if($null -eq $val){continue};$v=[double]$val
          if($type -eq 'Cpu' -and $stype -eq 'Temperature' -and $v -gt 0 -and $v -lt 130 -and $name -match '(?i)Package|Tctl|Tdie|Core Max'){if($null -eq $cpuTemp -or $v -gt $cpuTemp){$cpuTemp=$v;$cpuTempName=$name}}
          if($type -match '^Gpu' -and $stype -eq 'Temperature' -and $v -gt 0 -and $v -lt 130 -and $name -match '(?i)Core'){if($null -eq $gpuTemp){$gpuTemp=$v;$gpuTempName=$name}}
        }
      }
    }
    $lines=@('status=ok',('cpuTemp='+$(if($null -eq $cpuTemp){''}else{[math]::Round($cpuTemp,1)})),('gpuTemp='+$(if($null -eq $gpuTemp){''}else{[math]::Round($gpuTemp,1)})),('cpuLoad='+$(if($null -eq $cpuLoad){''}else{[math]::Round($cpuLoad,0)})),('gpuLoad='+$(if($null -eq $gpuLoad){''}else{[math]::Round($gpuLoad,0)})),('cpuName='+(SafeText $cpuName)),('gpuName='+(SafeText $gpuName)),('cpuTempSrc=LibreHardwareMonitor | '+(SafeText $cpuTempName)),('gpuTempSrc=LibreHardwareMonitor | '+(SafeText $gpuTempName)),('timestamp='+(Get-Date -Format 'HH:mm:ss')))
    $tmp=$OutFile+'.tmp';[IO.File]::WriteAllLines($tmp,$lines,[Text.Encoding]::ASCII);Move-Item -LiteralPath $tmp -Destination $OutFile -Force
    Start-Sleep -Milliseconds 2200
  }
}catch{WriteStatus 'failed' ('Advanced sensor worker failed: '+$_.Exception.Message)}finally{
  try{if($computer){$computer.Close()}}catch{};try{Pop-Location}catch{};try{if($mutex){$mutex.ReleaseMutex();$mutex.Dispose()}}catch{}
}
