param([Parameter(Mandatory=$true)][string]$OutFile)
$ErrorActionPreference = 'SilentlyContinue'

function Text($v) {
    if ($null -eq $v) { return '' }
    $s = [string]$v
    $s = $s -replace '[\r\n\t=]', ' '
    $s = $s -replace '\s+', ' '
    return $s.Trim()
}
function BoolText([bool]$v) { if($v){'true'}else{'false'} }
function MemoryTypeName($code) {
    # Win32_PhysicalMemory.SMBIOSMemoryType / SMBIOS Type 17 common values.
    switch([int]$code) {
        20 {'DDR'} 21 {'DDR2'} 22 {'DDR2 FB-DIMM'} 24 {'DDR3'} 26 {'DDR4'}
        30 {'LPDDR4'} 34 {'DDR5'} 35 {'LPDDR5'} default {''}
    }
}
function ArchitectureName($code) {
    switch([int]$code) { 0 {'x86'} 5 {'ARM'} 9 {'x64'} 12 {'ARM64'} default {'Unknown'} }
}
function SafeCim($class,$namespace='root/cimv2') {
    try { return @(Get-CimInstance -Namespace $namespace -ClassName $class -ErrorAction Stop) }
    catch {
        try { return @(Get-WmiObject -Namespace ($namespace -replace '/','\') -Class $class -ErrorAction Stop) }
        catch { return @() }
    }
}
function AddIssue([System.Collections.ArrayList]$list,[string]$s) { if($s){[void]$list.Add($s)} }

function GetGpuVramBytes([string]$driverDesc) {
    if(-not $driverDesc){ return 0L }
    try {
        $base='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        foreach($sub in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
            $v=Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue
            if((Text $v.DriverDesc) -eq $driverDesc) {
                if($v.'HardwareInformation.qwMemorySize'){ return [int64]$v.'HardwareInformation.qwMemorySize' }
                if($v.'HardwareInformation.MemorySize'){ return [int64][uint32]$v.'HardwareInformation.MemorySize' }
            }
        }
    } catch {}
    return 0L
}

$issues = New-Object System.Collections.ArrayList
$sources = New-Object System.Collections.ArrayList

$cpuRows = SafeCim 'Win32_Processor'
$cpu = $cpuRows | Select-Object -First 1
$gpuRows = @(SafeCim 'Win32_VideoController' | Where-Object { $_.Name -and $_.Name -notmatch 'Microsoft Basic|Remote Display|Indirect Display' })
$ramRows = @(SafeCim 'Win32_PhysicalMemory')
$cs = (SafeCim 'Win32_ComputerSystem' | Select-Object -First 1)
$board = (SafeCim 'Win32_BaseBoard' | Select-Object -First 1)
$bios = (SafeCim 'Win32_BIOS' | Select-Object -First 1)
$os = (SafeCim 'Win32_OperatingSystem' | Select-Object -First 1)
$chassis = (SafeCim 'Win32_SystemEnclosure' | Select-Object -First 1)
$battery = @(SafeCim 'Win32_Battery')
$portableBattery = @(SafeCim 'Win32_PortableBattery')
if($cpu){[void]$sources.Add('CIM CPU')}; if($gpuRows.Count){[void]$sources.Add('CIM GPU')}; if($ramRows.Count){[void]$sources.Add('CIM memory')}

# Fallbacks for customized/debloated Windows builds with incomplete providers.
if(-not $cpu -or -not $cpu.Name){
    try{
        $cpuReg=Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -ErrorAction Stop
        $cpu=[pscustomobject]@{Name=$cpuReg.ProcessorNameString;Manufacturer=$cpuReg.VendorIdentifier;NumberOfCores=0;NumberOfLogicalProcessors=$env:NUMBER_OF_PROCESSORS;MaxClockSpeed=0;Architecture=9}
        [void]$sources.Add('Registry CPU fallback')
    }catch{AddIssue $issues 'CPU identity unavailable'}
}
if($gpuRows.Count -eq 0){
    try{
        $gpuRows=@(Get-PnpDevice -Class Display -Status OK -ErrorAction Stop | Where-Object {$_.FriendlyName -and $_.FriendlyName -notmatch 'Microsoft Basic|Remote Display|Indirect Display'} | ForEach-Object {[pscustomobject]@{Name=$_.FriendlyName;DriverVersion='';CurrentRefreshRate=0;CurrentHorizontalResolution=0;CurrentVerticalResolution=0;PNPDeviceID=$_.InstanceId}})
        if($gpuRows.Count){[void]$sources.Add('PnP GPU fallback')}
    }catch{}
}
if($gpuRows.Count -eq 0){
    try{
        $video=@()
        Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Video' -ErrorAction Stop | ForEach-Object {
            Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | ForEach-Object {
                $v=Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if($v.DriverDesc -and $v.DriverDesc -notmatch 'Microsoft Basic|Remote Display|Indirect Display'){
                    $video += [pscustomobject]@{Name=$v.DriverDesc;DriverVersion=$v.DriverVersion;CurrentRefreshRate=0;CurrentHorizontalResolution=0;CurrentVerticalResolution=0;PNPDeviceID=''}
                }
            }
        }
        $gpuRows=@($video|Sort-Object Name -Unique)
        if($gpuRows.Count){[void]$sources.Add('Registry GPU fallback')}
    }catch{}
}
if($gpuRows.Count -eq 0){AddIssue $issues 'GPU identity unavailable'}

try{
    $br=Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -ErrorAction Stop
    if(-not $cs){$cs=[pscustomobject]@{Manufacturer=$br.SystemManufacturer;Model=$br.SystemProductName;PCSystemType=0;TotalPhysicalMemory=0}}
    if(-not $board){$board=[pscustomobject]@{Manufacturer=$br.BaseBoardManufacturer;Product=$br.BaseBoardProduct}}
    if(-not $bios){$bios=[pscustomobject]@{SMBIOSBIOSVersion=$br.BIOSVersion;Manufacturer=$br.BIOSVendor}}
}catch{}
try{
    if(-not $os){$wr=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop;$os=[pscustomobject]@{Caption=$wr.ProductName;Version=$wr.CurrentVersion;BuildNumber=$wr.CurrentBuildNumber}}
}catch{}

$gpuNames = @($gpuRows | ForEach-Object { Text $_.Name } | Where-Object { $_ } | Select-Object -Unique)
$gpuDrivers = @($gpuRows | ForEach-Object { Text $_.DriverVersion } | Where-Object { $_ } | Select-Object -Unique)
$gpuPnps = @($gpuRows | ForEach-Object { Text $_.PNPDeviceID } | Where-Object { $_ } | Select-Object -Unique)
$refreshRates = @($gpuRows | ForEach-Object { try{[int]$_.CurrentRefreshRate}catch{0} } | Where-Object { $_ -ge 23 -and $_ -lt 1000 })
$resolutions = @($gpuRows | ForEach-Object {
    try { $w=[int]$_.CurrentHorizontalResolution;$h=[int]$_.CurrentVerticalResolution;if($w -gt 0 -and $h -gt 0){"${w}x${h}"} } catch {}
} | Where-Object {$_} | Select-Object -Unique)

$ramBytes = 0L; $ramSpeeds=@(); $ramTypes=@()
if($ramRows.Count -eq 0 -and $cs -and $cs.TotalPhysicalMemory){try{$ramBytes=[int64]$cs.TotalPhysicalMemory}catch{}}
foreach($m in $ramRows){
    try { $ramBytes += [int64]$m.Capacity } catch {}
    $sp = 0
    try { $sp=[int]$(if($m.ConfiguredClockSpeed){$m.ConfiguredClockSpeed}else{$m.Speed}) } catch {}
    if($sp -gt 0){$ramSpeeds += $sp}
    $mt = MemoryTypeName $m.SMBIOSMemoryType
    if($mt -and $ramTypes -notcontains $mt){$ramTypes += $mt}
}
if($ramBytes -le 0){
    try{
        if(-not ('RenNev.NativeMemory' -as [type])){
            Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace RenNev { public static class NativeMemory { [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)] public class MEMORYSTATUSEX { public uint dwLength=(uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)); public uint dwMemoryLoad; public ulong ullTotalPhys; public ulong ullAvailPhys; public ulong ullTotalPageFile; public ulong ullAvailPageFile; public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual; } [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)] public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer); } }' -ErrorAction Stop
        }
        $ms=New-Object RenNev.NativeMemory+MEMORYSTATUSEX
        if([RenNev.NativeMemory]::GlobalMemoryStatusEx($ms)){$ramBytes=[int64]$ms.ullTotalPhys;[void]$sources.Add('Native memory fallback')}
    }catch{}
}
if($ramBytes -le 0){AddIssue $issues 'RAM capacity unavailable'}

# Storage. Get-PhysicalDisk provides MediaType/BusType on modern Windows; Win32_DiskDrive is the fallback.
$physical = @(); try { $physical = @(Get-PhysicalDisk -ErrorAction Stop) } catch {}
$hasSSD=$false; $hasHDD=$false; $hasNVMe=$false; $storageNames=@(); $storageBuses=@()
if($physical.Count -gt 0){
    [void]$sources.Add('Storage provider')
    foreach($d in $physical){
        $name = Text $d.FriendlyName; if($name){$storageNames += $name}
        $media = Text $d.MediaType; $bus=Text $d.BusType; if($bus){$storageBuses += $bus}
        if($media -match 'SSD' -or $bus -match 'NVMe'){ $hasSSD=$true }
        if($media -match 'HDD'){ $hasHDD=$true }
        if($bus -match 'NVMe'){ $hasNVMe=$true }
    }
}else{
    foreach($d in (SafeCim 'Win32_DiskDrive')){
        $name=Text $d.Model; if($name){$storageNames += $name}
        $blob=Text ($d.Model+' '+$d.MediaType+' '+$d.InterfaceType)
        if($blob -match '(?i)SSD|NVMe|solid state'){ $hasSSD=$true }
        if($blob -match '(?i)HDD|hard disk'){ $hasHDD=$true }
        if($blob -match '(?i)NVMe'){ $hasNVMe=$true }
        if($d.InterfaceType){$storageBuses += (Text $d.InterfaceType)}
    }
}
if($storageNames.Count -eq 0){AddIssue $issues 'Physical storage identity unavailable'}
$systemDriveFreeGB=0;$systemDriveFreePct=0
try{
    $ld=Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='"+$env:SystemDrive+"'") -ErrorAction Stop | Select-Object -First 1
    if($ld -and [double]$ld.Size -gt 0){$systemDriveFreeGB=[math]::Round(([double]$ld.FreeSpace/1GB),1);$systemDriveFreePct=[math]::Round(([double]$ld.FreeSpace/[double]$ld.Size)*100)}
}catch{}

# Active network adapter. Prefer the interface that actually owns the default route instead of
# guessing from link speed (VPN/virtual adapters can otherwise win the wrong way).
$netName='Unknown'; $netType='Unknown'; $netSpeed=''; $netDriver=''; $netDesc='';$wifiSignal='';$wifiRadio='';$wifiSsid='';$gateway='';$ifIndex=0;$routeMetric=''
try {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
      Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' } |
      Sort-Object @{Expression={ [int]$_.InterfaceMetric + [int]$_.RouteMetric }} |
      Select-Object -First 1
    if($route){
        $gateway=Text $route.NextHop;$ifIndex=[int]$route.ifIndex;$routeMetric=[int]$route.InterfaceMetric+[int]$route.RouteMetric
        $n=Get-NetAdapter -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue
        if($n){
            $netName=Text $n.Name;$netDesc=Text $n.InterfaceDescription;$netSpeed=Text $n.LinkSpeed;$netDriver=Text $n.DriverVersion
            $blob=($netName+' '+$netDesc).ToLowerInvariant()
            if($blob -match 'wi-?fi|wireless|802\.11'){$netType='Wi-Fi'}elseif($n.Virtual){$netType='Virtual / VPN'}else{$netType='Ethernet / wired'}
            [void]$sources.Add('Default-route network adapter')
        }
    }
}catch{}
if($netName -eq 'Unknown'){
    try{
        $adapters=@(Get-NetAdapter -Physical -ErrorAction Stop|Where-Object {$_.Status -eq 'Up'})
        $n=$adapters|Sort-Object -Property LinkSpeed -Descending|Select-Object -First 1
        if($n){$netName=Text $n.Name;$netDesc=Text $n.InterfaceDescription;$netSpeed=Text $n.LinkSpeed;$netDriver=Text $n.DriverVersion;$blob=($netName+' '+$netDesc).ToLowerInvariant();if($blob -match 'wi-?fi|wireless|802\.11'){$netType='Wi-Fi'}else{$netType='Ethernet / wired'}}
    }catch{}
}
if($netName -eq 'Unknown'){
    $n = SafeCim 'Win32_NetworkAdapter' | Where-Object {$_.NetEnabled -eq $true -and $_.PhysicalAdapter -eq $true} | Select-Object -First 1
    if($n){$netName=Text $(if($n.NetConnectionID){$n.NetConnectionID}else{$n.Name});$netDesc=Text $n.Name;if($n.Speed){try{$netSpeed=([math]::Round(([double]$n.Speed)/1MB)).ToString()+' Mbps'}catch{}};$blob=($netName+' '+$netDesc).ToLowerInvariant();if($blob -match 'wi-?fi|wireless|802\.11'){$netType='Wi-Fi'}else{$netType='Ethernet / wired'}}
}
if($netType -eq 'Wi-Fi'){
    try{
        $wl=(& netsh.exe wlan show interfaces 2>$null | Out-String)
        if($wl -match '(?im)^\s*SSID\s*:\s*([^\r\n]+)'){$wifiSsid=Text $matches[1]}
        if($wl -match '(?im)^\s*Signal\s*:\s*([^\r\n]+)'){$wifiSignal=Text $matches[1]}
        if($wl -match '(?im)^\s*Radio type\s*:\s*([^\r\n]+)'){$wifiRadio=Text $matches[1]}
    }catch{}
}
if($netName -eq 'Unknown'){AddIssue $issues 'Active network route/adapter unavailable'}

$powerPlan='Unknown'
try { $pcfg = (& powercfg.exe /getactivescheme 2>$null | Out-String); if($pcfg -match '\(([^\)]+)\)'){$powerPlan=Text $matches[1]} } catch {}
$modernStandby=$false
try { $avail=(& powercfg.exe /a 2>$null | Out-String); if($avail -match 'S0 Low Power Idle'){$modernStandby=$true} } catch {}

# Device type: prefer chassis/system-type signals. A generic Win32_Battery can also be a UPS,
# so only use it as a last-resort hint when stronger mobile indicators are unavailable.
$isLaptop = $false
if($portableBattery.Count -gt 0){ $isLaptop=$true }
if(-not $isLaptop -and $cs){
    try {
        # Win32_ComputerSystem.PCSystemType: 2=Mobile, 8=Slate.
        $pct=[int]$cs.PCSystemType
        if($pct -eq 2 -or $pct -eq 8){$isLaptop=$true}
    } catch {}
}
if(-not $isLaptop -and $chassis -and $chassis.ChassisTypes){
    $portable = @(8,9,10,11,12,14,18,21,30,31,32)
    foreach($ct in @($chassis.ChassisTypes)){ if($portable -contains [int]$ct){$isLaptop=$true;break} }
}
if(-not $isLaptop -and $battery.Count -gt 0 -and -not $chassis -and -not $cs){$isLaptop=$true}
$batteryPct=''
if($battery.Count){try{$bp=@($battery|Where-Object {$null -ne $_.EstimatedChargeRemaining}|ForEach-Object {[int]$_.EstimatedChargeRemaining});if($bp.Count){$batteryPct=(($bp|Measure-Object -Average).Average).ToString('0')}}catch{}}

$cpuName=Text $cpu.Name; if(-not $cpuName){$cpuName='Unknown'}
$cpuVendor=Text $cpu.Manufacturer
$cpuArch='Unknown';try{$cpuArch=ArchitectureName $cpu.Architecture}catch{}
if($env:PROCESSOR_ARCHITECTURE -match 'ARM64'){$cpuArch='ARM64'}elseif($env:PROCESSOR_ARCHITECTURE -match 'AMD64'){$cpuArch='x64'}
$gpuName=if($gpuNames.Count){Text ($gpuNames -join ' + ')}else{'Unknown'}
$gpuLower=$gpuName.ToLowerInvariant(); $cpuLower=$cpuName.ToLowerInvariant()
$gpuVendor=if($gpuLower -match 'nvidia'){'NVIDIA'}elseif($gpuLower -match 'radeon|\bamd\b'){'AMD'}elseif($gpuLower -match 'intel'){'Intel'}elseif($gpuLower -match 'adreno|qualcomm'){'Qualcomm'}else{'Other'}
$cpuFamily=if($cpuLower -match 'ryzen'){'AMD Ryzen'}elseif($cpuLower -match 'intel'){'Intel'}elseif($cpuLower -match 'snapdragon|qualcomm'){'Qualcomm Snapdragon'}elseif($cpuVendor -match 'AMD'){'AMD'}else{'Other'}
$isIntelArc=$gpuLower -match 'intel.*arc|arc.*intel'
$isNvidiaRTX=$gpuLower -match 'nvidia.*rtx|geforce rtx'
$isAmdRadeon=$gpuLower -match 'radeon|\bamd\b'
$isAmdSamCandidate=($cpuFamily -eq 'AMD Ryzen' -and $gpuLower -match 'radeon.*rx\s*[5-9]\d{3}')
$isModernGpu=($isIntelArc -or $isNvidiaRTX -or $gpuLower -match 'radeon.*rx\s*[5-9]\d{3}')
$gpuVramParts=@();$gpuVramMaxGB=0
foreach($gn in $gpuNames){$vb=GetGpuVramBytes $gn;if($vb -gt 0){$gb=[math]::Round($vb/1GB,1);$gpuVramParts += ($gn+': '+$gb+' GB');if($gb -gt $gpuVramMaxGB){$gpuVramMaxGB=$gb}}}

$manufacturer=Text $cs.Manufacturer; $model=Text $cs.Model
$boardText = Text ((Text $board.Manufacturer)+' '+(Text $board.Product))
$biosText = Text ((Text $bios.SMBIOSBIOSVersion)+' | '+(Text $bios.Manufacturer))
$osText=Text $os.Caption; if(-not $osText){$osText='Unknown'}
$ramGB=if($ramBytes -gt 0){[math]::Round($ramBytes/1GB)}else{0}
$ramSpeed=if($ramSpeeds.Count){($ramSpeeds | Measure-Object -Maximum).Maximum}else{0}
$refresh=if($refreshRates.Count){(($refreshRates | Measure-Object -Maximum).Maximum).ToString()+' Hz'}else{'Unknown'}
$resolution=if($resolutions.Count){Text (($resolutions|Select-Object -Unique) -join ' / ')}else{'Unknown'}
$storageSummary=if($storageNames.Count){Text (($storageNames | Select-Object -Unique | Select-Object -First 3) -join ' + ')}else{'Unknown'}
$storageBus=if($storageBuses.Count){Text (($storageBuses | Select-Object -Unique) -join ' / ')}else{''}
$monitorCount=0;try{$monitorCount=@(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop|Where-Object {$_.Active}).Count}catch{}
if($monitorCount -le 0){try{$monitorCount=@(Get-PnpDevice -Class Monitor -Status OK -ErrorAction Stop).Count}catch{}}

$secureBoot='Unknown';try{$secureBoot=if(Confirm-SecureBootUEFI -ErrorAction Stop){'On'}else{'Off'}}catch{}
$vbs='Unknown';$hvci='Unknown';try{$dg=Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop;$vbs=if([int]$dg.VirtualizationBasedSecurityStatus -gt 0){'On'}else{'Off'};$hvci=if(@($dg.SecurityServicesRunning) -contains 2){'On'}else{'Off'}}catch{}

# Quality score is deliberately transparent; unknown hardware stays unknown instead of being guessed.
$quality=0
if($cpuName -and $cpuName -ne 'Unknown'){$quality+=25}
if($gpuName -and $gpuName -ne 'Unknown'){$quality+=25}
if($ramGB -gt 0){$quality+=15}
if($storageSummary -and $storageSummary -ne 'Unknown'){$quality+=12}
if($osText -and $osText -ne 'Unknown'){$quality+=10}
if($boardText){$quality+=5}
if($netName -and $netName -ne 'Unknown'){$quality+=5}
if($refresh -ne 'Unknown'){$quality+=3}
if($quality -gt 100){$quality=100}

$lines = @(
 'status=ok',
 ('source='+(Text (($sources|Select-Object -Unique) -join ' + '))),('qualityScore='+$quality),('issues='+(Text ($issues -join '; '))),
 ('manufacturer='+$manufacturer),('model='+$model),('architecture='+$cpuArch),
 ('cpuName='+$cpuName),('cpuVendor='+$cpuVendor),
 ('cores='+$(if($cpu){[int]$cpu.NumberOfCores}else{0})),('threads='+$(if($cpu){[int]$cpu.NumberOfLogicalProcessors}else{0})),('cpuMaxMHz='+$(if($cpu){[int]$cpu.MaxClockSpeed}else{0})),
 ('gpuName='+$gpuName),('gpuCount='+$gpuNames.Count),('gpuDriver='+(Text ($gpuDrivers -join ' + '))),('gpuPnp='+(Text ($gpuPnps -join ' + '))),('gpuVramGB='+$gpuVramMaxGB),('gpuVramSummary='+(Text ($gpuVramParts -join ' + '))),
 ('ramGB='+$ramGB),('ramModules='+$ramRows.Count),('ramSpeed='+$ramSpeed),('ramType='+(Text ($ramTypes -join '/'))),
 ('os='+$osText),('osVersion='+(Text $os.Version)),('osBuild='+(Text $os.BuildNumber)),
 ('board='+$boardText),('bios='+$biosText),('deviceType='+$(if($isLaptop){'Laptop / mobile'}else{'Desktop'})),('isLaptop='+(BoolText $isLaptop)),('batteryPct='+$batteryPct),
 ('powerPlan='+$powerPlan),('modernStandby='+(BoolText $modernStandby)),
 ('hasSSD='+(BoolText $hasSSD)),('hasHDD='+(BoolText $hasHDD)),('hasNVMe='+(BoolText $hasNVMe)),('storageSummary='+$storageSummary),('storageBus='+$storageBus),('systemDriveFreeGB='+$systemDriveFreeGB),('systemDriveFreePct='+$systemDriveFreePct),
 ('networkType='+$netType),('networkName='+$netName),('networkSpeed='+$netSpeed),('networkDriver='+$netDriver),('gateway='+$gateway),('interfaceIndex='+$ifIndex),('routeMetric='+$routeMetric),('wifiSsid='+$wifiSsid),('wifiSignal='+$wifiSignal),('wifiRadio='+$wifiRadio),
 ('refresh='+$refresh),('resolution='+$resolution),('monitorCount='+$monitorCount),('gpuVendor='+$gpuVendor),('cpuFamily='+$cpuFamily),
 ('isIntelArc='+(BoolText $isIntelArc)),('isNvidiaRTX='+(BoolText $isNvidiaRTX)),('isAmdRadeon='+(BoolText $isAmdRadeon)),('isAmdSamCandidate='+(BoolText $isAmdSamCandidate)),('isModernGpu='+(BoolText $isModernGpu)),('secureBoot='+$secureBoot),('vbs='+$vbs),('hvci='+$hvci),
 ('timestamp='+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
)
[IO.File]::WriteAllLines($OutFile,$lines,[Text.Encoding]::ASCII)
