param(
  [ValidateSet('fortnite','roblox')][string]$Game,
  [ValidateSet('before','after')][string]$Phase,
  [ValidateRange(30,900)][int]$DurationSec = 180,
  [ValidateRange(0,60)][int]$WarmupSec = 10,
  [int]$TargetProcessId = 0,
  [Parameter(Mandatory=$true)][string]$ResultPath,
  [Parameter(Mandatory=$true)][string]$StatusPath,
  [Parameter(Mandatory=$true)][string]$CancelPath,
  [Parameter(Mandatory=$true)][string]$ToolsDir
)

$ErrorActionPreference = 'Stop'
$Invariant = [Globalization.CultureInfo]::InvariantCulture

function SafeValue([object]$v) {
  if ($null -eq $v) { return '' }
  return ([string]$v) -replace '[\r\n=]+',' '
}
function Write-Status([string]$state,[int]$progress,[string]$message,[int]$secondsLeft=0) {
  $dir = Split-Path -Parent $StatusPath
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  @(
    "state=$state",
    "progress=$progress",
    "message=$(SafeValue $message)",
    "secondsleft=$secondsLeft",
    "game=$Game",
    "phase=$Phase"
  ) | Set-Content -LiteralPath $StatusPath -Encoding ASCII
}
function Fail([string]$message) {
  Write-Status 'failed' 0 $message 0
  exit 2
}
function Find-PresentMon {
  $candidates = @(
    (Join-Path $ToolsDir 'PresentMon-2.5.1-x64.exe'),
    (Join-Path $ToolsDir 'PresentMon-2.4.1-x64.exe'),
    (Join-Path $ToolsDir 'PresentMon-2.3.1-x64.exe')
  )
  foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
  foreach ($n in @('PresentMon-2.5.1-x64.exe','PresentMon-2.4.1-x64.exe','PresentMon-2.3.1-x64.exe','PresentMon.exe')) {
    try { $cmd = Get-Command $n -ErrorAction Stop; if ($cmd.Path) { return $cmd.Path } } catch {}
  }
  return $null
}
function Find-GameProcess {
  $deadline = (Get-Date).AddSeconds(30)
  do {
    if (Test-Path -LiteralPath $CancelPath) { Fail 'Benchmark cancelled.' }
    if ($TargetProcessId -gt 0) {
      try { return Get-Process -Id $TargetProcessId -ErrorAction Stop } catch {}
    }
    $list = Get-Process -ErrorAction SilentlyContinue
    if ($Game -eq 'fortnite') {
      $p = $list | Where-Object { $_.ProcessName -like 'FortniteClient*' } | Sort-Object StartTime -Descending | Select-Object -First 1
    } else {
      $p = $list | Where-Object { $_.ProcessName -match '^Roblox(PlayerBeta)?$|RobloxPlayerBeta|Windows10Universal' } | Sort-Object StartTime -Descending | Select-Object -First 1
    }
    if ($p) { return $p }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  return $null
}
function Get-Percentile([double[]]$values,[double]$p) {
  if (-not $values -or $values.Count -eq 0) { return [double]::NaN }
  $s = $values | Sort-Object
  $idx = [Math]::Ceiling(($p/100.0) * $s.Count) - 1
  if ($idx -lt 0) { $idx = 0 }
  if ($idx -ge $s.Count) { $idx = $s.Count - 1 }
  return [double]$s[$idx]
}
function Avg([double[]]$values) {
  if (-not $values -or $values.Count -eq 0) { return [double]::NaN }
  return [double](($values | Measure-Object -Average).Average)
}
function MaxVal([double[]]$values) {
  if (-not $values -or $values.Count -eq 0) { return [double]::NaN }
  return [double](($values | Measure-Object -Maximum).Maximum)
}
function RoundOrBlank([double]$v,[int]$digits=1) {
  if ([double]::IsNaN($v) -or [double]::IsInfinity($v)) { return '' }
  return [Math]::Round($v,$digits).ToString($Invariant)
}
function Get-LhmTemp([string]$kind) {
  foreach ($ns in @('root\LibreHardwareMonitor','root\OpenHardwareMonitor')) {
    try {
      $rows = Get-CimInstance -Namespace $ns -ClassName Sensor -ErrorAction Stop | Where-Object { $_.SensorType -eq 'Temperature' }
      $match = if ($kind -eq 'cpu') {
        $rows | Where-Object { ($_.Name + ' ' + $_.Identifier) -match 'CPU Package|CPU Core|Tctl|Tdie|cpu' }
      } else {
        $rows | Where-Object { ($_.Name + ' ' + $_.Identifier) -match 'GPU Core|Hot Spot|gpu' }
      }
      if ($match) { return [double](($match | Measure-Object -Property Value -Maximum).Maximum) }
    } catch {}
  }
  return [double]::NaN
}
function Get-NvidiaTemp {
  try {
    $nvsmi = Get-Command nvidia-smi.exe -ErrorAction Stop
    $v = & $nvsmi.Path --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    $d = 0.0
    if ([double]::TryParse(([string]$v).Trim(),[Globalization.NumberStyles]::Float,$Invariant,[ref]$d)) { return $d }
  } catch {}
  return [double]::NaN
}
function Get-ConfigHash {
  try {
    if ($Game -eq 'fortnite') {
      $p = Join-Path $env:LOCALAPPDATA 'FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini'
    } else {
      $p = Join-Path $env:LOCALAPPDATA 'Roblox\GlobalBasicSettings_13.xml'
    }
    if (Test-Path -LiteralPath $p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
  } catch {}
  return ''
}
function Get-GpuSnapshot([int]$pid) {
  try {
    $rows = Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop | Where-Object { $_.Name -match ("pid_" + $pid + "_") }
    if (-not $rows) { return [double]::NaN }
    $sum = [double](($rows | Measure-Object -Property UtilizationPercentage -Sum).Sum)
    if ($sum -lt 0) { return [double]::NaN }
    if ($sum -gt 100) { $sum = 100 }
    return $sum
  } catch { return [double]::NaN }
}

try {
  if (Test-Path -LiteralPath $CancelPath) { Remove-Item -LiteralPath $CancelPath -Force -ErrorAction SilentlyContinue }
  if (Test-Path -LiteralPath $ResultPath) { Remove-Item -LiteralPath $ResultPath -Force -ErrorAction SilentlyContinue }
  $pm = Find-PresentMon
  if (-not $pm) { Fail 'Intel PresentMon Console is not installed. Use Install Frame Capture Engine first.' }

  Write-Status 'waiting' 2 'Looking for the game process...' 0
  $gameProc = Find-GameProcess
  if (-not $gameProc) { Fail 'Game process not found. Launch the game, enter a match/experience, then start the capture.' }
  $targetPid = [int]$gameProc.Id
  try { $gamePath = $gameProc.Path } catch { $gamePath = '' }
  try { $gameVersion = if ($gamePath) { (Get-Item -LiteralPath $gamePath).VersionInfo.FileVersion } else { '' } } catch { $gameVersion = '' }

  for ($i=$WarmupSec; $i -gt 0; $i--) {
    if (Test-Path -LiteralPath $CancelPath) { Fail 'Benchmark cancelled.' }
    if (-not (Get-Process -Id $targetPid -ErrorAction SilentlyContinue)) { Fail 'The game closed during warm-up.' }
    $pct = [Math]::Min(8,[Math]::Round((($WarmupSec-$i)/[Math]::Max(1,$WarmupSec))*8))
    Write-Status 'warmup' $pct "Warm-up: keep playing normally. Capture starts in $i second(s)." $i
    Start-Sleep -Seconds 1
  }

  $tempDir = Join-Path $env:TEMP ('RenNevBench_' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
  $csv = Join-Path $tempDir 'frames.csv'
  $session = 'RenNevBench_' + [Guid]::NewGuid().ToString('N').Substring(0,8)
  $pmArgs = "--process_id $targetPid --output_file `"$csv`" --timed $DurationSec --terminate_after_timed --no_console_stats --stop_existing_session --session_name $session --no_track_input --no_track_gpu --v2_metrics"
  $pmProc = Start-Process -FilePath $pm -ArgumentList $pmArgs -WindowStyle Hidden -PassThru

  $logical = [Environment]::ProcessorCount
  $cpuSamples = New-Object System.Collections.Generic.List[double]
  $sysCpuSamples = New-Object System.Collections.Generic.List[double]
  $memSamples = New-Object System.Collections.Generic.List[double]
  $freeRamSamples = New-Object System.Collections.Generic.List[double]
  $procCountSamples = New-Object System.Collections.Generic.List[double]
  $gpuSamples = New-Object System.Collections.Generic.List[double]
  $cpuTempSamples = New-Object System.Collections.Generic.List[double]
  $gpuTempSamples = New-Object System.Collections.Generic.List[double]
  $lastCpu = $gameProc.CPU
  $lastT = Get-Date
  $start = Get-Date
  $nvidiaTempChecked = $false

  while (-not $pmProc.HasExited) {
    if (Test-Path -LiteralPath $CancelPath) {
      try { Stop-Process -Id $pmProc.Id -Force -ErrorAction SilentlyContinue } catch {}
      Fail 'Benchmark cancelled.'
    }
    $p = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
    if (-not $p) {
      try { Stop-Process -Id $pmProc.Id -Force -ErrorAction SilentlyContinue } catch {}
      Fail 'The game closed before the benchmark finished.'
    }
    $now = Get-Date
    $dt = [Math]::Max(0.2,($now-$lastT).TotalSeconds)
    $cpuNow = [double]$p.CPU
    $gameCpu = (($cpuNow-$lastCpu)/$dt)*100.0/[Math]::Max(1,$logical)
    if ($gameCpu -ge 0 -and $gameCpu -le 100) { $cpuSamples.Add($gameCpu) }
    $lastCpu = $cpuNow; $lastT = $now

    try {
      $sys = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
      $v=[double]$sys.PercentProcessorTime; if ($v -ge 0 -and $v -le 100) { $sysCpuSamples.Add($v) }
    } catch {}
    $memSamples.Add([double]($p.WorkingSet64/1MB))
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; $freeRamSamples.Add([double]($os.FreePhysicalMemory/1024)) } catch {}
    try { $procCountSamples.Add([double](Get-Process).Count) } catch {}
    $gu = Get-GpuSnapshot $targetPid; if (-not [double]::IsNaN($gu)) { $gpuSamples.Add($gu) }
    $ct = Get-LhmTemp 'cpu'; if (-not [double]::IsNaN($ct)) { $cpuTempSamples.Add($ct) }
    $gt = Get-LhmTemp 'gpu'
    if ([double]::IsNaN($gt)) { $gt = Get-NvidiaTemp }
    if (-not [double]::IsNaN($gt)) { $gpuTempSamples.Add($gt) }

    $elapsed = [Math]::Min($DurationSec,([datetime]::Now-$start).TotalSeconds)
    $left = [Math]::Max(0,[int][Math]::Ceiling($DurationSec-$elapsed))
    $progress = 8 + [int][Math]::Round(($elapsed/[Math]::Max(1,$DurationSec))*88)
    Write-Status 'capturing' $progress "Capturing real frame times. Keep playing the same route/scenario." $left
    Start-Sleep -Seconds 1
    try { $pmProc.Refresh() } catch {}
  }

  Write-Status 'processing' 97 'Processing frame times and 1% / 0.1% lows...' 0
  if (-not (Test-Path -LiteralPath $csv)) { Fail 'PresentMon finished without producing a frame capture.' }
  $rows = Import-Csv -LiteralPath $csv
  if (-not $rows -or $rows.Count -lt 20) { Fail 'Not enough rendered frames were captured. Make sure the game was actively rendering during the test.' }
  $headers = $rows[0].PSObject.Properties.Name
  $frameCol = @('MsBetweenDisplayChange','MsBetweenPresents','MsBetweenAppStart','msBetweenDisplayChange','msBetweenPresents','FrameTime') | Where-Object { $headers -contains $_ } | Select-Object -First 1
  if (-not $frameCol) { Fail 'The PresentMon CSV did not contain a supported frame-time column.' }
  $frameTimes = New-Object System.Collections.Generic.List[double]
  foreach ($r in $rows) {
    $raw = [string]$r.$frameCol; $d = 0.0
    if ([double]::TryParse($raw,[Globalization.NumberStyles]::Float,$Invariant,[ref]$d) -and $d -gt 0.05 -and $d -lt 2000) { $frameTimes.Add($d) }
  }
  if ($frameTimes.Count -lt 20) { Fail 'PresentMon captured frames, but too few valid frame intervals were available for analysis.' }
  $arr = [double[]]$frameTimes.ToArray()
  $meanFt = Avg $arr
  $medianFt = Get-Percentile $arr 50
  $p95 = Get-Percentile $arr 95
  $p99 = Get-Percentile $arr 99
  $p999 = Get-Percentile $arr 99.9
  $avgFps = 1000.0 / $meanFt
  $medianFps = 1000.0 / $medianFt
  $low1 = 1000.0 / $p99
  $low01 = 1000.0 / $p999
  $over50 = [double](($arr | Where-Object { $_ -gt 50 }).Count) / $arr.Count * 100
  $over333 = [double](($arr | Where-Object { $_ -gt 33.333 }).Count) / $arr.Count * 100
  $over166 = [double](($arr | Where-Object { $_ -gt 16.667 }).Count) / $arr.Count * 100
  $capturedSec = ($arr | Measure-Object -Sum).Sum / 1000.0

  $gpuInfo = try { Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Remote|Basic Display' } | ForEach-Object { "$($_.Name)|$($_.DriverVersion)" } } catch { @() }
  $osInfo = try { Get-CimInstance Win32_OperatingSystem } catch { $null }
  $vc = try { Get-CimInstance Win32_VideoController | Where-Object { $_.CurrentHorizontalResolution -gt 0 -and $_.CurrentVerticalResolution -gt 0 } | Sort-Object @{Expression={ [double]$_.CurrentHorizontalResolution * [double]$_.CurrentVerticalResolution};Descending=$true} | Select-Object -First 1 } catch { $null }
  $powerText = try { (powercfg /getactivescheme 2>$null) -join ' ' } catch { '' }
  $powerGuid = if ($powerText -match '([0-9a-fA-F-]{36})') { $matches[1] } else { '' }
  $configHash = Get-ConfigHash
  $quality = if ($capturedSec -ge ($DurationSec*0.80) -and $arr.Count -ge 500) { 'GOOD' } elseif ($capturedSec -ge ($DurationSec*0.50) -and $arr.Count -ge 200) { 'OKAY' } else { 'POOR' }

  $result = @(
    "timestamp=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "game=$Game",
    "phase=$Phase",
    "duration=$DurationSec",
    "frames=$($arr.Count)",
    "framecolumn=$(SafeValue $frameCol)",
    "capturequality=$quality",
    "capturedseconds=$(RoundOrBlank $capturedSec 1)",
    "avgfps=$(RoundOrBlank $avgFps 1)",
    "medianfps=$(RoundOrBlank $medianFps 1)",
    "low1=$(RoundOrBlank $low1 1)",
    "low01=$(RoundOrBlank $low01 1)",
    "lowmethod=FPS percentile derived from captured frame-time percentiles",
    "avgframetime=$(RoundOrBlank $meanFt 2)",
    "p95frametime=$(RoundOrBlank $p95 2)",
    "p99frametime=$(RoundOrBlank $p99 2)",
    "over50pct=$(RoundOrBlank $over50 2)",
    "below30pct=$(RoundOrBlank $over333 2)",
    "below60pct=$(RoundOrBlank $over166 2)",
    "gamecpuavg=$(RoundOrBlank (Avg ([double[]]$cpuSamples.ToArray())) 1)",
    "gamecpupeak=$(RoundOrBlank (MaxVal ([double[]]$cpuSamples.ToArray())) 1)",
    "systemcpuavg=$(RoundOrBlank (Avg ([double[]]$sysCpuSamples.ToArray())) 1)",
    "gamegpuavg=$(RoundOrBlank (Avg ([double[]]$gpuSamples.ToArray())) 1)",
    "gamegpupeak=$(RoundOrBlank (MaxVal ([double[]]$gpuSamples.ToArray())) 1)",
    "gamememavg=$(RoundOrBlank (Avg ([double[]]$memSamples.ToArray())) 0)",
    "freeramavg=$(RoundOrBlank (Avg ([double[]]$freeRamSamples.ToArray())) 0)",
    "processavg=$(RoundOrBlank (Avg ([double[]]$procCountSamples.ToArray())) 0)",
    "cputempavg=$(RoundOrBlank (Avg ([double[]]$cpuTempSamples.ToArray())) 1)",
    "cputemppeak=$(RoundOrBlank (MaxVal ([double[]]$cpuTempSamples.ToArray())) 1)",
    "gputempavg=$(RoundOrBlank (Avg ([double[]]$gpuTempSamples.ToArray())) 1)",
    "gputemppeak=$(RoundOrBlank (MaxVal ([double[]]$gpuTempSamples.ToArray())) 1)",
    "gameversion=$(SafeValue $gameVersion)",
    "confighash=$(SafeValue $configHash)",
    "gpudriver=$(SafeValue (($gpuInfo -join '; ')))",
    "windowsbuild=$(SafeValue $(if($osInfo){$osInfo.Version + '.' + $osInfo.BuildNumber}else{''}))",
    "resolution=$(SafeValue $(if($vc){$vc.CurrentHorizontalResolution.ToString()+'x'+$vc.CurrentVerticalResolution.ToString()}else{''}))",
    "refreshrate=$(SafeValue $(if($vc){$vc.CurrentRefreshRate}else{''}))",
    "powerguid=$(SafeValue $powerGuid)",
    "presentmon=$(SafeValue ([IO.Path]::GetFileName($pm)))"
  )
  $dir = Split-Path -Parent $ResultPath
  if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $result | Set-Content -LiteralPath $ResultPath -Encoding ASCII
  Write-Status 'complete' 100 "Capture complete: $([Math]::Round($avgFps,1)) FPS average, $([Math]::Round($low1,1)) FPS 1% low." 0
  try { Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  exit 0
}
catch {
  Fail ("Benchmark error: " + $_.Exception.Message)
}
