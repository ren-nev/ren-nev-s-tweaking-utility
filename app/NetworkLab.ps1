param([Parameter(Mandatory=$true)][string]$OutFile)
$ErrorActionPreference='SilentlyContinue'

# v21 network diagnostics. Ping/DNS methodology is adapted from unknowntweaks
# (MIT, copyright 2026 unknowntweaks contributors). See licenses notice.
function Clean($v){if($null -eq $v){return ''};return (([string]$v)-replace '[\r\n\t=]',' ' -replace '\s+',' ').Trim()}
function Median([double[]]$v){if(-not $v -or $v.Count -eq 0){return $null};$s=@($v|Sort-Object);return [double]$s[[int][math]::Floor($s.Count/2)]}
function PingStats([string]$host,[int]$n=6,[int]$timeout=900){
  $vals=New-Object System.Collections.Generic.List[double];$sent=0
  try{$p=New-Object System.Net.NetworkInformation.Ping;for($i=0;$i -lt $n;$i++){$sent++;try{$r=$p.Send($host,$timeout);if($r.Status -eq 'Success'){$vals.Add([double]$r.RoundtripTime)}}catch{};if($i -lt $n-1){Start-Sleep -Milliseconds 120}};$p.Dispose()}catch{}
  $avg=$null;$min=$null;$max=$null;$jit=$null;if($vals.Count){$m=$vals|Measure-Object -Average -Minimum -Maximum;$avg=[math]::Round([double]$m.Average,1);$min=[math]::Round([double]$m.Minimum,1);$max=[math]::Round([double]$m.Maximum,1);$jit=0.0;if($vals.Count -gt 1){$d=0.0;for($i=1;$i -lt $vals.Count;$i++){$d += [math]::Abs($vals[$i]-$vals[$i-1])};$jit=[math]::Round($d/($vals.Count-1),1)}}
  $loss=if($sent){[math]::Round(100.0*($sent-$vals.Count)/$sent,1)}else{100}
  return [pscustomobject]@{Avg=$avg;Min=$min;Max=$max;Jitter=$jit;Loss=$loss;Replies=$vals.Count;Sent=$sent}
}
function Test-RawDns([string]$server,[string]$name='www.epicgames.com',[int]$samples=5,[int]$timeout=1200){
  $addr=$null;if(-not [System.Net.IPAddress]::TryParse($server,[ref]$addr)){return @()};$out=@()
  for($i=0;$i -lt $samples;$i++){
    $qname=('p{0}.{1}' -f (Get-Random -Minimum 1000 -Maximum 999999),$name);$id=Get-Random -Minimum 1 -Maximum 65535;$buf=New-Object System.Collections.Generic.List[byte]
    $buf.AddRange([byte[]]@((($id -shr 8)-band 255),($id-band 255),1,0,0,1,0,0,0,0,0,0));foreach($label in $qname.TrimEnd('.').Split('.')){$lb=[Text.Encoding]::ASCII.GetBytes($label);$buf.Add([byte]$lb.Length);$buf.AddRange($lb)};$buf.AddRange([byte[]]@(0,0,1,0,1));$pkt=$buf.ToArray()
    $udp=New-Object System.Net.Sockets.UdpClient -ArgumentList $addr.AddressFamily;$udp.Client.ReceiveTimeout=$timeout;$ep=New-Object System.Net.IPEndPoint -ArgumentList $addr,53;$sw=[Diagnostics.Stopwatch]::StartNew();$ok=$false;$ms=$null
    try{[void]$udp.Send($pkt,$pkt.Length,$ep);$from=if($addr.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6){New-Object System.Net.IPEndPoint -ArgumentList ([System.Net.IPAddress]::IPv6Any),0}else{New-Object System.Net.IPEndPoint -ArgumentList ([System.Net.IPAddress]::Any),0};$resp=$udp.Receive([ref]$from);$sw.Stop();$ok=($resp.Length -ge 2 -and $resp[0] -eq $pkt[0] -and $resp[1] -eq $pkt[1]);if($ok){$ms=[math]::Round($sw.Elapsed.TotalMilliseconds,1)}}catch{$sw.Stop()}finally{$udp.Close()};$out += [pscustomobject]@{Ok=$ok;Ms=$ms}
  }
  return $out
}
function DnsStats([string]$server){$rows=@(Test-RawDns $server);$vals=@($rows|Where-Object {$_.Ok -and $null -ne $_.Ms}|ForEach-Object {[double]$_.Ms});return [pscustomobject]@{Median=$(Median $vals);Best=$(if($vals.Count){[double](($vals|Measure-Object -Minimum).Minimum)}else{$null});Replies=$vals.Count;Sent=$rows.Count}}

$adapter='Unknown';$desc='';$type='Unknown';$speed='';$gateway='';$ifIndex=0;$ssid='';$signal='';$routeMetric=''
try{
  $route=Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop|Where-Object {$_.NextHop -and $_.NextHop -ne '0.0.0.0'}|Sort-Object @{Expression={[int]$_.InterfaceMetric+[int]$_.RouteMetric}}|Select-Object -First 1
  if($route){$gateway=[string]$route.NextHop;$ifIndex=[int]$route.ifIndex;$routeMetric=([int]$route.InterfaceMetric+[int]$route.RouteMetric);$nic=Get-NetAdapter -InterfaceIndex $ifIndex -ErrorAction SilentlyContinue;if($nic){$adapter=[string]$nic.Name;$desc=[string]$nic.InterfaceDescription;$speed=[string]$nic.LinkSpeed;if($nic.PhysicalMediaType -eq 'Native 802.11' -or [int]$nic.NdisPhysicalMedium -eq 9){$type='Wi-Fi'}elseif($nic.PhysicalMediaType -eq '802.3'){$type='Ethernet / wired'}elseif($nic.Virtual){$type='Virtual / VPN'}else{$blob=$adapter+' '+$desc;if($blob -match 'Wi-?Fi|Wireless|802\.11'){$type='Wi-Fi'}else{$type='Ethernet / wired'}}}}
}catch{}
if($type -eq 'Wi-Fi'){
  try{$raw=& netsh.exe wlan show interfaces 2>$null;$m=($raw|Select-String '^\s*SSID\s*:\s*(.+)$'|Select-Object -First 1);if($m){$ssid=$m.Matches[0].Groups[1].Value.Trim()};$m=($raw|Select-String '^\s*Signal\s*:\s*(\d+)%'|Select-Object -First 1);if($m){$signal=$m.Matches[0].Groups[1].Value+'%'}}catch{}
}

$gw=if($gateway){PingStats $gateway 6 700}else{[pscustomobject]@{Avg=$null;Min=$null;Max=$null;Jitter=$null;Loss=100;Replies=0;Sent=0}}
$cf=PingStats '1.1.1.1' 6 900;$gg=PingStats '8.8.8.8' 6 900;$dcf=DnsStats '1.1.1.1';$dgg=DnsStats '8.8.8.8'
$auto='';$rss='';try{$tcp=& netsh.exe int tcp show global 2>$null;$auto=(($tcp|Select-String 'Receive Window Auto-Tuning Level'|Select-Object -First 1).Line -replace '^.*:\s*','').Trim();$rss=(($tcp|Select-String 'Receive-Side Scaling State'|Select-Object -First 1).Line -replace '^.*:\s*','').Trim()}catch{}

$lines=@(
 'status=ok',('adapter='+(Clean $adapter)),('description='+(Clean $desc)),('type='+(Clean $type)),('speed='+(Clean $speed)),('gateway='+(Clean $gateway)),('ifIndex='+$ifIndex),('routeMetric='+(Clean $routeMetric)),('ssid='+(Clean $ssid)),('signal='+(Clean $signal)),
 ('gatewayMs='+$(if($null -eq $gw.Avg){''}else{$gw.Avg})),('gatewayMin='+$(if($null -eq $gw.Min){''}else{$gw.Min})),('gatewayMax='+$(if($null -eq $gw.Max){''}else{$gw.Max})),('gatewayJitter='+$(if($null -eq $gw.Jitter){''}else{$gw.Jitter})),('gatewayLoss='+$gw.Loss),
 ('cloudflareMs='+$(if($null -eq $cf.Avg){''}else{$cf.Avg})),('cloudflareJitter='+$(if($null -eq $cf.Jitter){''}else{$cf.Jitter})),('cloudflareLoss='+$cf.Loss),
 ('googleMs='+$(if($null -eq $gg.Avg){''}else{$gg.Avg})),('googleJitter='+$(if($null -eq $gg.Jitter){''}else{$gg.Jitter})),('googleLoss='+$gg.Loss),
 ('dnsCloudflareMs='+$(if($null -eq $dcf.Median){''}else{[math]::Round([double]$dcf.Median,1)})),('dnsCloudflareBest='+$(if($null -eq $dcf.Best){''}else{[math]::Round([double]$dcf.Best,1)})),('dnsCloudflareOk='+$dcf.Replies+'/'+$dcf.Sent),
 ('dnsGoogleMs='+$(if($null -eq $dgg.Median){''}else{[math]::Round([double]$dgg.Median,1)})),('dnsGoogleBest='+$(if($null -eq $dgg.Best){''}else{[math]::Round([double]$dgg.Best,1)})),('dnsGoogleOk='+$dgg.Replies+'/'+$dgg.Sent),
 ('autotuning='+(Clean $auto)),('rss='+(Clean $rss)),('timestamp='+(Get-Date -Format 'HH:mm:ss'))
)
[IO.File]::WriteAllLines($OutFile,$lines,[Text.Encoding]::ASCII)
