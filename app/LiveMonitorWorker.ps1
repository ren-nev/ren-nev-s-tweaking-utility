param([Parameter(Mandatory=$true)][string]$StateDir)
$ErrorActionPreference='SilentlyContinue'

# Ren Nev v21 live monitor.
# The language-neutral PDH/native sampling approach in this file is adapted from
# unknowntweaks (MIT, copyright 2026 unknowntweaks contributors). See
# licenses/unknowntweaks-MIT.txt and THIRD_PARTY_NOTICES.md.

$out=Join-Path $StateDir 'monitor-live.txt'
$heart=Join-Path $StateDir 'monitor-heartbeat.txt'
$advanced=Join-Path $StateDir 'advanced-sensor-live.txt'
$mutex=$null;$ownsMutex=$false
try{$mutex=New-Object System.Threading.Mutex -ArgumentList $false,'Global\RenNevLiveMonitorV21';$ownsMutex=$mutex.WaitOne(0,$false);if(-not $ownsMutex){exit 0}}catch{}

function Clean($v){if($null -eq $v){return ''};return (([string]$v)-replace '[\r\n\t=]',' ' -replace '\s+',' ').Trim()}

# CPU/RAM come directly from kernel32. PDH uses PdhAddEnglishCounterW so the
# counter paths do not break on non-English Windows installations.
if(-not ('RenNev21.Native.PdhQuery' -as [type])){
$cs=@'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
namespace RenNev21.Native {
  public class PdhSample { public string Instance; public double Value; public uint Status; }
  public static class Pdh {
    public const uint FMT_DOUBLE=0x00000200, FMT_NOCAP100=0x00008000, MORE_DATA=0x800007D2;
    public const uint VALID=0, NEWDATA=1;
    [StructLayout(LayoutKind.Explicit, Size=16)] public struct VALUE { [FieldOffset(0)] public uint Status; [FieldOffset(8)] public double DoubleValue; }
    [DllImport("pdh.dll",CharSet=CharSet.Unicode)] public static extern uint PdhOpenQueryW(string src,IntPtr user,out IntPtr query);
    [DllImport("pdh.dll",CharSet=CharSet.Unicode)] public static extern uint PdhAddEnglishCounterW(IntPtr query,string path,IntPtr user,out IntPtr counter);
    [DllImport("pdh.dll")] public static extern uint PdhCollectQueryData(IntPtr query);
    [DllImport("pdh.dll")] public static extern uint PdhGetFormattedCounterValue(IntPtr counter,uint fmt,IntPtr type,out VALUE value);
    [DllImport("pdh.dll",CharSet=CharSet.Unicode)] public static extern uint PdhGetFormattedCounterArrayW(IntPtr counter,uint fmt,ref uint size,out uint count,IntPtr buffer);
    [DllImport("pdh.dll")] public static extern uint PdhCloseQuery(IntPtr query);
  }
  public class PdhQuery : IDisposable {
    IntPtr q=IntPtr.Zero; readonly Dictionary<string,IntPtr> counters=new Dictionary<string,IntPtr>(StringComparer.OrdinalIgnoreCase);
    public PdhQuery(){uint rc=Pdh.PdhOpenQueryW(null,IntPtr.Zero,out q);if(rc!=0)throw new InvalidOperationException("PdhOpenQuery 0x"+rc.ToString("X8"));}
    public bool Add(string key,string path){IntPtr c;uint rc=Pdh.PdhAddEnglishCounterW(q,path,IntPtr.Zero,out c);if(rc!=0)return false;counters[key]=c;return true;}
    public uint Collect(){return Pdh.PdhCollectQueryData(q);}
    public double Get(string key,bool noCap){IntPtr c;if(!counters.TryGetValue(key,out c))return double.NaN;Pdh.VALUE v;uint fmt=Pdh.FMT_DOUBLE|(noCap?Pdh.FMT_NOCAP100:0u);uint rc=Pdh.PdhGetFormattedCounterValue(c,fmt,IntPtr.Zero,out v);if(rc!=0|| (v.Status!=Pdh.VALID&&v.Status!=Pdh.NEWDATA))return double.NaN;return v.DoubleValue;}
    public List<PdhSample> GetArray(string key,bool noCap){var list=new List<PdhSample>();IntPtr c;if(!counters.TryGetValue(key,out c))return list;uint fmt=Pdh.FMT_DOUBLE|(noCap?Pdh.FMT_NOCAP100:0u);uint size=0,count=0;uint rc=Pdh.PdhGetFormattedCounterArrayW(c,fmt,ref size,out count,IntPtr.Zero);if(rc!=Pdh.MORE_DATA||size==0)return list;IntPtr b=Marshal.AllocHGlobal((int)size);try{rc=Pdh.PdhGetFormattedCounterArrayW(c,fmt,ref size,out count,b);if(rc!=0)return list;int itemSize=IntPtr.Size==8?24:16;int statusOffset=IntPtr.Size;int valueOffset=IntPtr.Size==8?16:8;for(int i=0;i<count;i++){IntPtr item=new IntPtr(b.ToInt64()+(long)i*itemSize);IntPtr namePtr=Marshal.ReadIntPtr(item,0);uint st=(uint)Marshal.ReadInt32(item,statusOffset);double val=BitConverter.Int64BitsToDouble(Marshal.ReadInt64(item,valueOffset));var s=new PdhSample();s.Instance=namePtr==IntPtr.Zero?"":Marshal.PtrToStringUni(namePtr);s.Status=st;s.Value=(st==Pdh.VALID||st==Pdh.NEWDATA)?val:double.NaN;list.Add(s);} } finally {Marshal.FreeHGlobal(b);} return list;}
    public void Dispose(){if(q!=IntPtr.Zero){Pdh.PdhCloseQuery(q);q=IntPtr.Zero;}}
  }
  public static class Sys {
    [StructLayout(LayoutKind.Sequential)] public struct FT { public uint Low; public uint High; }
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetSystemTimes(out FT idle,out FT kernel,out FT user);
    [StructLayout(LayoutKind.Sequential)] public class MEM { public uint Length=64,Load; public ulong Total,Avail,TotalPage,AvailPage,TotalVirt,AvailVirt,Ext; }
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GlobalMemoryStatusEx([In,Out] MEM m);
    static ulong U(FT f){return ((ulong)f.High<<32)|f.Low;}
    public class CpuTimes { public ulong Idle,Kernel,User; public bool Ok; }
    public static CpuTimes Cpu(){FT i,k,u;var t=new CpuTimes();t.Ok=GetSystemTimes(out i,out k,out u);if(t.Ok){t.Idle=U(i);t.Kernel=U(k);t.User=U(u);}return t;}
    public static MEM Memory(){var m=new MEM();return GlobalMemoryStatusEx(m)?m:null;}
  }
}
'@
  try{Add-Type -TypeDefinition $cs -ErrorAction Stop}catch{}
}

function Get-NetRows {
  $virtual='Virtual|VMware|VirtualBox|Hyper-V|vEthernet|WAN Miniport|Bluetooth|Npcap|WinPcap|TAP-|Wintun|WireGuard|Loopback|ISATAP|Teredo|Pseudo|Kernel Debug|Wi-Fi Direct|Miniport|Tunnel|Tailscale|ZeroTier|Radmin|Hamachi'
  $rows=@()
  try{
    foreach($i in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()){
      if($i.OperationalStatus -ne 'Up'){continue}
      if([string]$i.NetworkInterfaceType -in 'Loopback','Tunnel','Ppp'){continue}
      if($i.Description -match $virtual){continue}
      try{$s=$i.GetIPStatistics();$rows += [pscustomobject]@{Id=$i.Id;Rx=[int64]$s.BytesReceived;Tx=[int64]$s.BytesSent;Speed=[int64]$i.Speed}}catch{}
    }
  }catch{}
  return $rows
}
function NamespaceTemp([string]$ns,[string]$kind){
  try{
    $rows=@(Get-CimInstance -Namespace $ns -ClassName Sensor -ErrorAction Stop|Where-Object {[string]$_.SensorType -eq 'Temperature'})
    $cand=@();foreach($s in $rows){$name=(Clean $s.Name).ToLowerInvariant();$id=(Clean $s.Identifier).ToLowerInvariant();$v=[double]$s.Value;if($v -le 0 -or $v -ge 130){continue};$score=0;if($kind -eq 'cpu'){if($id -match '/cpu/'){$score+=10};if($name -match 'cpu package|tctl|tdie|core max'){$score+=40}elseif($name -match 'cpu core|core #'){$score+=15};if($name -match 'distance to tjmax'){$score-=50}}else{if($id -match '/gpu'){$score+=10};if($name -match 'gpu core|gpu temperature'){$score+=40}elseif($name -match '^core$'){$score+=15};if($name -match 'hot spot|hotspot|memory'){$score-=10}};if($score -gt 0){$cand += [pscustomobject]@{Score=$score;Value=$v;Name=(Clean $s.Name)}}};$p=$cand|Sort-Object Score,Value -Descending|Select-Object -First 1;if($p){return $p}
  }catch{}
  return $null
}
function ReadAdvancedTemps {
  $ct=$null;$gt=$null;$cs='not exposed';$gs='not exposed'
  if(Test-Path $advanced){try{if(((Get-Date)-(Get-Item $advanced).LastWriteTime).TotalSeconds -lt 12){$kv=@{};foreach($l in Get-Content -LiteralPath $advanced){$x=$l.IndexOf('=');if($x -gt 0){$kv[$l.Substring(0,$x)]=$l.Substring($x+1)}};if($kv.cpuTemp){$v=[double]$kv.cpuTemp;if($v -gt 0 -and $v -lt 130){$ct=$v;$cs=if($kv.cpuTempSrc){$kv.cpuTempSrc}else{'LibreHardwareMonitor'}}};if($kv.gpuTemp){$v=[double]$kv.gpuTemp;if($v -gt 0 -and $v -lt 130){$gt=$v;$gs=if($kv.gpuTempSrc){$kv.gpuTempSrc}else{'LibreHardwareMonitor'}}}}}catch{}}
  if($null -eq $ct){foreach($ns in @('root/LibreHardwareMonitor','root/OpenHardwareMonitor')){$p=NamespaceTemp $ns 'cpu';if($p){$ct=[double]$p.Value;$cs=($ns.Split('/')[-1]+' | '+$p.Name);break}}}
  if($null -eq $gt){foreach($ns in @('root/LibreHardwareMonitor','root/OpenHardwareMonitor')){$p=NamespaceTemp $ns 'gpu';if($p){$gt=[double]$p.Value;$gs=($ns.Split('/')[-1]+' | '+$p.Name);break}}}
  return @($ct,$gt,$cs,$gs)
}

$cpuName='CPU';$gpuName='GPU'
try{$cpuName=(Clean ((Get-CimInstance Win32_Processor -ErrorAction Stop|Select-Object -First 1).Name))}catch{}
try{$g=@(Get-CimInstance Win32_VideoController -ErrorAction Stop|Where-Object {$_.Name -and $_.Name -notmatch 'Microsoft Basic|Remote Display|Indirect Display'});$p=@($g|Where-Object {$_.Name -match 'NVIDIA|GeForce|RTX|GTX|AMD|Radeon|Intel Arc'}|Select-Object -First 1);if(-not $p.Count){$p=@($g|Select-Object -First 1)};if($p.Count){$gpuName=(Clean $p[0].Name)}}catch{}
$nvidiaSmi=$null;try{$nvidiaSmi=(Get-Command nvidia-smi.exe -ErrorAction Stop).Source}catch{}

$pdh=$null;$backend='native+wmi';$pdhGpu=$false
try{
  if('RenNev21.Native.PdhQuery' -as [type]){
    $pdh=New-Object RenNev21.Native.PdhQuery
    $core=$true
    foreach($c in @(
      @('cpuUtil','\Processor Information(_Total)\% Processor Utility'),
      @('cpuTime','\Processor Information(_Total)\% Processor Time'),
      @('dskIdle','\PhysicalDisk(_Total)\% Idle Time'),
      @('dskRead','\PhysicalDisk(_Total)\Disk Read Bytes/sec'),
      @('dskWrite','\PhysicalDisk(_Total)\Disk Write Bytes/sec')
    )){if(-not $pdh.Add($c[0],$c[1])){$core=$false}}
    $pdhGpu=$pdh.Add('gpuEng','\GPU Engine(*)\Utilization Percentage')
    $null=$pdh.Add('gpuMem','\GPU Adapter Memory(*)\Dedicated Usage')
    if($core){$backend='native+pdh';$null=$pdh.Collect()}else{$pdh.Dispose();$pdh=$null}
  }
}catch{if($pdh){try{$pdh.Dispose()}catch{}};$pdh=$null}

$prevCpu=$null;try{if('RenNev21.Native.Sys' -as [type]){$prevCpu=[RenNev21.Native.Sys]::Cpu()}}catch{}
$prevNet=@{};foreach($n in (Get-NetRows)){$prevNet[$n.Id]=$n};$prevTime=[DateTime]::UtcNow
$lastGpu=$null;$lastDisk=$null;$lastRead=0;$lastWrite=0;$lastTemps=@($null,$null,'not exposed','not exposed');$tick=0

try{
while($true){
  $tick++
  try{if(Test-Path $heart){if(((Get-Date)-(Get-Item $heart).LastWriteTime).TotalSeconds -gt 18){break}}else{Start-Sleep -Seconds 2;continue}}catch{}
  $now=[DateTime]::UtcNow;$dt=[math]::Max(.25,($now-$prevTime).TotalSeconds)

  # CPU from GetSystemTimes, with PDH Processor Utility preferred on pre-24H2 systems when available.
  $cpu=$null;$cpuTime=$null;$cpuUtil=$null
  try{$cur=[RenNev21.Native.Sys]::Cpu();if($cur -and $cur.Ok -and $prevCpu -and $prevCpu.Ok){$idle=[double]($cur.Idle-$prevCpu.Idle);$total=[double](($cur.Kernel+$cur.User)-($prevCpu.Kernel+$prevCpu.User));if($total -gt 0){$cpuTime=[math]::Round(100*(1-$idle/$total),1)}};$prevCpu=$cur}catch{}

  $gpu=$null;$gpuEngine='';$gpuVram=0;$disk=$null;$readBps=0;$writeBps=0
  if($pdh){
    try{$null=$pdh.Collect();$v=$pdh.Get('cpuUtil',$true);if(-not [double]::IsNaN($v)){$cpuUtil=[math]::Round([math]::Min(100,[math]::Max(0,$v)),1)};$v=$pdh.Get('cpuTime',$false);if($null -eq $cpuTime -and -not [double]::IsNaN($v)){$cpuTime=[math]::Round([math]::Min(100,[math]::Max(0,$v)),1)};$v=$pdh.Get('dskIdle',$false);if(-not [double]::IsNaN($v)){$disk=[math]::Round([math]::Min(100,[math]::Max(0,100-$v)),1)};$v=$pdh.Get('dskRead',$false);if(-not [double]::IsNaN($v)){$readBps=[math]::Max(0,$v)};$v=$pdh.Get('dskWrite',$false);if(-not [double]::IsNaN($v)){$writeBps=[math]::Max(0,$v)}
      $eng=@{};$adapters=@{};foreach($s in @($pdh.GetArray('gpuEng',$false))){if($null -eq $s -or [double]::IsNaN($s.Value) -or $s.Value -le 0){continue};if($s.Instance -match '^pid_(\d+)_luid_(0x[0-9A-Fa-f]+_0x[0-9A-Fa-f]+)_phys_(\d+)_eng_(\d+)_engtype_(.+)$'){$k=$Matches[2]+'|'+$Matches[4]+'|'+$Matches[5];$eng[$k]=[double]$eng[$k]+[double]$s.Value}}
      foreach($k in @($eng.Keys)){$parts=$k.Split('|');$luid=$parts[0];$val=[math]::Min(100,[double]$eng[$k]);if(-not $adapters.ContainsKey($luid)){$adapters[$luid]=@{Max=0.0;Engine=''}};if($val -gt $adapters[$luid].Max){$adapters[$luid].Max=$val;$adapters[$luid].Engine=$parts[2]}}
      if($adapters.Count){$best=@($adapters.GetEnumerator()|Sort-Object {$_.Value.Max} -Descending|Select-Object -First 1)[0];$gpu=[math]::Round([double]$best.Value.Max,1);$gpuEngine=[string]$best.Value.Engine;$luid=[string]$best.Key;foreach($m in @($pdh.GetArray('gpuMem',$false))){if($null -eq $m -or [double]::IsNaN($m.Value)){continue};if($m.Instance -match '^luid_(0x[0-9A-Fa-f]+_0x[0-9A-Fa-f]+)_phys_\d+$' -and $Matches[1] -eq $luid){$gpuVram=[int64]$m.Value;break}}}
    }catch{}
  }
  if($null -eq $gpu -and $nvidiaSmi){try{$line=& $nvidiaSmi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>$null|Select-Object -First 1;$v=[double]$line;if($v -ge 0 -and $v -le 100){$gpu=[math]::Round($v);$gpuEngine='NVIDIA'}}catch{}}
  if($null -eq $gpu -and ($tick%2 -eq 0)){try{$rows=@(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop);$vals=@($rows|ForEach-Object {[double]$_.UtilizationPercentage});if($vals.Count){$gpu=[math]::Min(100,[math]::Round((($vals|Measure-Object -Maximum).Maximum)));$gpuEngine='Windows GPU counter'}}catch{}}
  if($null -eq $disk -and ($tick%2 -eq 0)){try{$d=Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction Stop|Select-Object -First 1;if($d){$disk=[math]::Min(100,[math]::Max(0,[math]::Round(100-[double]$d.PercentIdleTime)));$readBps=[double]$d.DiskReadBytesPersec;$writeBps=[double]$d.DiskWriteBytesPersec}}catch{}}
  if($null -eq $gpu){$gpu=$lastGpu}else{$lastGpu=$gpu};if($null -eq $disk){$disk=$lastDisk}else{$lastDisk=$disk};if($readBps -le 0){$readBps=$lastRead}else{$lastRead=$readBps};if($writeBps -le 0){$writeBps=$lastWrite}else{$lastWrite=$writeBps}

  $osBuild=[Environment]::OSVersion.Version.Build;$cpu=$cpuTime;if($osBuild -lt 26100 -and $null -ne $cpuUtil){$cpu=$cpuUtil};if($null -eq $cpu){$cpu=$cpuUtil}
  $ram=$null;try{$m=[RenNev21.Native.Sys]::Memory();if($m -and $m.Total -gt 0){$ram=[math]::Round(100*([double]($m.Total-$m.Avail)/[double]$m.Total),1)}}catch{}

  # Network is sampled from actual connected physical interfaces; no localized counter names.
  $netRx=0.0;$netTx=0.0;$linkBps=0;foreach($n in (Get-NetRows)){if($prevNet.ContainsKey($n.Id) -and $dt -gt 0){$netRx += [math]::Max(0,([double]($n.Rx-$prevNet[$n.Id].Rx))/$dt);$netTx += [math]::Max(0,([double]($n.Tx-$prevNet[$n.Id].Tx))/$dt)};if($n.Speed -gt $linkBps){$linkBps=$n.Speed};$prevNet[$n.Id]=$n};$prevTime=$now

  # Temperatures: cached advanced worker first, then already-running LHM/OHM namespaces, then NVIDIA driver.
  if(($tick%2) -eq 1){$lastTemps=ReadAdvancedTemps;if($null -eq $lastTemps[1] -and $nvidiaSmi){try{$line=& $nvidiaSmi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>$null|Select-Object -First 1;$v=[double]$line;if($v -gt 0 -and $v -lt 130){$lastTemps[1]=$v;$lastTemps[3]='NVIDIA driver'}}catch{}}}
  $temps=$lastTemps

  $lines=@(
    'status=ok',('backend='+$backend),
    ('cpuLoad='+$(if($null -eq $cpu){''}else{[math]::Round([double]$cpu,1)})),
    ('gpuLoad='+$(if($null -eq $gpu){''}else{[math]::Round([double]$gpu,1)})),
    ('gpuEngine='+(Clean $gpuEngine)),('gpuVramUsedB='+[int64]$gpuVram),
    ('ramLoad='+$(if($null -eq $ram){''}else{[math]::Round([double]$ram,1)})),
    ('diskLoad='+$(if($null -eq $disk){''}else{[math]::Round([double]$disk,1)})),('diskReadBps='+[math]::Round([double]$readBps)),('diskWriteBps='+[math]::Round([double]$writeBps)),
    ('netDownBps='+[math]::Round($netRx)),('netUpBps='+[math]::Round($netTx)),('linkBps='+[int64]$linkBps),
    ('cpuTemp='+$(if($null -eq $temps[0]){''}else{[math]::Round([double]$temps[0],1)})),('gpuTemp='+$(if($null -eq $temps[1]){''}else{[math]::Round([double]$temps[1],1)})),
    ('cpuTempSrc='+(Clean $temps[2])),('gpuTempSrc='+(Clean $temps[3])),('cpuName='+(Clean $cpuName)),('gpuName='+(Clean $gpuName)),('timestamp='+(Get-Date -Format 'HH:mm:ss'))
  )
  try{[IO.File]::WriteAllLines($out,$lines,[Text.Encoding]::ASCII)}catch{}
  Start-Sleep -Milliseconds 1000
}
} finally {
  try{if($pdh){$pdh.Dispose()}}catch{}
  try{if($ownsMutex -and $mutex){$mutex.ReleaseMutex()}}catch{}
  try{if($mutex){$mutex.Dispose()}}catch{}
}
