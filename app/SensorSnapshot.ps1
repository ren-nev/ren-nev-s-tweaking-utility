param([Parameter(Mandatory=$true)][string]$OutFile)
$ErrorActionPreference='SilentlyContinue'
function Text($v){ if($null -eq $v){return ''}; return (([string]$v)-replace '[\r\n\t=]',' ' -replace '\s+',' ').Trim() }
function TempFromNamespace($ns,$kind){
  try{
    $rows=@(Get-CimInstance -Namespace $ns -ClassName Sensor -ErrorAction Stop | Where-Object { [string]$_.SensorType -eq 'Temperature' })
    if($rows.Count -eq 0){return $null}
    $candidates=@()
    foreach($s in $rows){
      $name=(Text $s.Name).ToLowerInvariant(); $id=(Text $s.Identifier).ToLowerInvariant(); $v=[double]$s.Value
      if($v -le 0 -or $v -ge 130){continue}
      $score=0
      if($kind -eq 'cpu'){
        if($id -match '/cpu/'){$score+=10}
        if($name -match 'cpu package|tctl|tdie|core max'){$score+=30}elseif($name -match 'cpu core|core #'){$score+=15}
        if($name -match 'distance to tjmax'){$score-=30}
      }else{
        if($id -match '/gpu'){$score+=10}
        if($name -match 'gpu core|gpu temperature|core'){$score+=30}
        if($name -match 'hot spot|hotspot|memory'){$score-=10}
      }
      if($score -gt 0){$candidates += [pscustomobject]@{Score=$score;Value=$v;Name=(Text $s.Name)}}
    }
    $pick=$candidates | Sort-Object Score,Value -Descending | Select-Object -First 1
    if($pick){return $pick}
  }catch{}
  return $null
}

# CPU load. Win32_Processor is language-independent, unlike localized performance-counter names.
$cpuLoad=$null
try{ $vals=@(Get-CimInstance Win32_Processor -ErrorAction Stop | ForEach-Object {[double]$_.LoadPercentage}); if($vals.Count){$cpuLoad=[math]::Round((($vals|Measure-Object -Average).Average))} }catch{}

$cpuName='CPU'; $gpuName='GPU'
try{$cpuName=Text ((Get-CimInstance Win32_Processor -ErrorAction Stop|Select-Object -First 1).Name)}catch{}
try{$gpuName=Text ((Get-CimInstance Win32_VideoController -ErrorAction Stop|Where-Object {$_.Name -notmatch 'Microsoft Basic|Remote Display|Indirect Display'}|Select-Object -First 1).Name)}catch{}

$cpuTemp=$null;$gpuTemp=$null;$gpuLoad=$null;$cpuSrc='not exposed';$gpuSrc='not exposed';$loadSrc='Windows'
$stateDir=Split-Path $OutFile
$advancedLive = Join-Path $stateDir 'advanced-sensor-live.txt'
$heartbeat = Join-Path $stateDir 'sensor-heartbeat.txt'
try{[IO.File]::WriteAllText($heartbeat,(Get-Date -Format o),[Text.Encoding]::ASCII)}catch{}

# Prefer the persistent opt-in LibreHardwareMonitor worker when its file is fresh.
if(Test-Path $advancedLive){
  try{
    $age=((Get-Date)-(Get-Item $advancedLive).LastWriteTime).TotalSeconds
    if($age -lt 12){
      $kv=@{};foreach($line in Get-Content -LiteralPath $advancedLive){$k=$line.IndexOf('=');if($k -gt 0){$kv[$line.Substring(0,$k)]=$line.Substring($k+1)}}
      if($kv.cpuTemp){$v=[double]$kv.cpuTemp;if($v -gt 0 -and $v -lt 130){$cpuTemp=$v;$cpuSrc=if($kv.cpuTempSrc){$kv.cpuTempSrc}else{'LibreHardwareMonitor'}}}
      if($kv.gpuTemp){$v=[double]$kv.gpuTemp;if($v -gt 0 -and $v -lt 130){$gpuTemp=$v;$gpuSrc=if($kv.gpuTempSrc){$kv.gpuTempSrc}else{'LibreHardwareMonitor'}}}
      if($kv.cpuLoad -ne ''){$v=[double]$kv.cpuLoad;if($v -ge 0 -and $v -le 100){$cpuLoad=$v}}
      if($kv.gpuLoad -ne ''){$v=[double]$kv.gpuLoad;if($v -ge 0 -and $v -le 100){$gpuLoad=$v}}
      if($kv.cpuName){$cpuName=Text $kv.cpuName};if($kv.gpuName){$gpuName=Text $kv.gpuName}
      $loadSrc='LibreHardwareMonitor'
    }
  }catch{}
}

# If another hardware-monitor app already publishes the WMI namespace, use it too.
if($null -eq $cpuTemp){$c=TempFromNamespace 'root/LibreHardwareMonitor' 'cpu';if($c){$cpuTemp=[double]$c.Value;$cpuSrc='LibreHardwareMonitor | '+(Text $c.Name)}}
if($null -eq $gpuTemp){$g=TempFromNamespace 'root/LibreHardwareMonitor' 'gpu';if($g){$gpuTemp=[double]$g.Value;$gpuSrc='LibreHardwareMonitor | '+(Text $g.Name)}}
if($null -eq $cpuTemp){$c=TempFromNamespace 'root/OpenHardwareMonitor' 'cpu';if($c){$cpuTemp=[double]$c.Value;$cpuSrc='OpenHardwareMonitor | '+(Text $c.Name)}}
if($null -eq $gpuTemp){$g=TempFromNamespace 'root/OpenHardwareMonitor' 'gpu';if($g){$gpuTemp=[double]$g.Value;$gpuSrc='OpenHardwareMonitor | '+(Text $g.Name)}}

# NVIDIA vendor fallback gives a reliable NVIDIA GPU temperature and utilization without extra software.
$smipath=$null
try{$cmd=Get-Command nvidia-smi.exe -ErrorAction Stop;$smipath=$cmd.Source}catch{}
if(-not $smipath){$p=Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe';if(Test-Path $p){$smipath=$p}}
if($smipath){
  try{
    $line=& $smipath --query-gpu=name,utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    if($line){
      $parts=$line -split ','
      if($parts.Count -ge 3){
        $gpuName=Text $parts[0];$nvload=[double](Text $parts[1]);$nvtemp=[double](Text $parts[2])
        if($nvload -ge 0 -and $nvload -le 100){$gpuLoad=[math]::Round($nvload);$loadSrc='NVIDIA driver'}
        if($null -eq $gpuTemp -and $nvtemp -gt 0 -and $nvtemp -lt 130){$gpuTemp=$nvtemp;$gpuSrc='NVIDIA driver'}
      }
    }
  }catch{}
}

# Generic WDDM GPU-engine utilization fallback for AMD/Intel/NVIDIA when vendor data is unavailable.
if($null -eq $gpuLoad){
  try{
    $eng=@(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop)
    $threeD=@($eng|Where-Object {$_.Name -match 'engtype_3D'}|ForEach-Object {[double]$_.UtilizationPercentage})
    $all=@($eng|ForEach-Object {[double]$_.UtilizationPercentage})
    if($threeD.Count){$gpuLoad=[math]::Min(100,[math]::Round((($threeD|Measure-Object -Maximum).Maximum)));$loadSrc='Windows WDDM GPU engine'}
    elseif($all.Count){$gpuLoad=[math]::Min(100,[math]::Round((($all|Measure-Object -Maximum).Maximum)));$loadSrc='Windows WDDM GPU engine'}
  }catch{}
}

# Do not label ACPI thermal zones as CPU package temperature. Many laptops/boards expose a chassis zone there.
$firmwareTemp=$null
try{
  $zones=@(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop)
  $temps=@();foreach($z in $zones){$v=([double]$z.CurrentTemperature/10)-273.15;if($v -gt 10 -and $v -lt 120){$temps+=$v}}
  if($temps.Count){$firmwareTemp=[math]::Round((($temps|Measure-Object -Maximum).Maximum),1)}
}catch{}

$lines=@(
 'status=ok',('cpuLoad='+$(if($null -eq $cpuLoad){''}else{[math]::Round($cpuLoad)})),('gpuLoad='+$(if($null -eq $gpuLoad){''}else{[math]::Round($gpuLoad)})),
 ('cpuTemp='+$(if($null -eq $cpuTemp){''}else{[math]::Round($cpuTemp,1)})),('gpuTemp='+$(if($null -eq $gpuTemp){''}else{[math]::Round($gpuTemp,1)})),('firmwareTemp='+$(if($null -eq $firmwareTemp){''}else{$firmwareTemp})),
 ('cpuTempSrc='+(Text $cpuSrc)),('gpuTempSrc='+(Text $gpuSrc)),('loadSrc='+(Text $loadSrc)),('cpuName='+(Text $cpuName)),('gpuName='+(Text $gpuName)),('timestamp='+(Get-Date -Format 'HH:mm:ss'))
)
[IO.File]::WriteAllLines($OutFile,$lines,[Text.Encoding]::ASCII)
