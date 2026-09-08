param([Parameter(Mandatory=$true)][string]$OutFile,[string]$Root='')
$ErrorActionPreference='SilentlyContinue'
if(-not $Root){$Root=$PSScriptRoot}
$pass=0;$fail=0;$warn=0;$details=New-Object System.Collections.Generic.List[string]
function AddResult([string]$name,[string]$state,[string]$detail){$script:details.Add(($state+'|'+$name+'|'+$detail));if($state -eq 'PASS'){$script:pass++}elseif($state -eq 'FAIL'){$script:fail++}else{$script:warn++}}
function Clean([string]$s){if($null -eq $s){return ''};return (($s-replace '[\r\n\t=]',' ')-replace '\s+',' ').Trim()}

# Parse every PowerShell backend with the same parser Windows PowerShell uses.
$psFiles=@(Get-ChildItem -LiteralPath $Root -Filter *.ps1 -File -ErrorAction SilentlyContinue)
$parseErrors=0;$parseNames=@();$nonAscii=@()
foreach($f in $psFiles){
  $tokens=$null;$errors=$null
  try{$null=[System.Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors);if($errors -and $errors.Count){$parseErrors += $errors.Count;$parseNames += ($f.Name+': '+$errors[0].Message)}}catch{$parseErrors++;$parseNames += ($f.Name+': '+$_.Exception.Message)}
  # Windows PowerShell 5.1 treats UTF-8-without-BOM as the current ANSI code page. Keep backend scripts ASCII so text never changes meaning on another locale.
  try{$bytes=[IO.File]::ReadAllBytes($f.FullName);if(@($bytes|Where-Object {$_ -gt 127}).Count){$nonAscii += $f.Name}}catch{}
}
if($parseErrors){AddResult 'PowerShell syntax' 'FAIL' (($parseErrors.ToString())+' parse error(s): '+($parseNames -join '; '))}else{AddResult 'PowerShell syntax' 'PASS' (($psFiles.Count.ToString())+' backend scripts parsed without syntax errors.')}
if($nonAscii.Count){AddResult 'PowerShell 5.1 encoding' 'FAIL' ('Non-ASCII source in: '+($nonAscii -join ', '))}else{AddResult 'PowerShell 5.1 encoding' 'PASS' 'Backend scripts are ASCII-safe for Windows PowerShell 5.1 on non-English systems.'}

# Conservative text-level Windows PowerShell 5.1 compatibility guard, inspired by the supplied MIT source tests.
$ps51Bad=@();$ps51Checks=@(
  @{P='ForEach-Object\s+-Parallel';M='ForEach-Object -Parallel'},
  @{P='ConvertFrom-Json[^\r\n]*-AsHashtable';M='ConvertFrom-Json -AsHashtable'},
  @{P='\bJoin-String\b';M='Join-String'},
  @{P='\bGet-Error\b';M='Get-Error'},
  @{P='\bTest-Json\b';M='Test-Json'},
  @{P='-SkipCertificateCheck';M='-SkipCertificateCheck'},
  @{P='\bTest-Connection\b[^\r\n]*-TimeoutSeconds';M='Test-Connection -TimeoutSeconds'},
  @{P='Split-Path[^\r\n]*-LeafBase';M='Split-Path -LeafBase'}
)
foreach($f in $psFiles){if($f.Name -eq 'DeveloperSelfTest.ps1'){continue};$src=[IO.File]::ReadAllText($f.FullName);foreach($c in $ps51Checks){if($src -match $c.P){$ps51Bad += ($f.Name+': '+$c.M)}}}
if($ps51Bad.Count){AddResult 'PowerShell 5.1 compatibility' 'FAIL' ('Newer-only syntax/cmdlet use: '+($ps51Bad -join '; '))}else{AddResult 'PowerShell 5.1 compatibility' 'PASS' 'No known PowerShell 6/7-only constructs were found in runtime backends.'}

$hta=Join-Path $Root 'Launcher.html'
if(-not (Test-Path -LiteralPath $hta)){AddResult 'Launcher source' 'FAIL' 'Launcher.html is missing.'}
else{
  $text=Get-Content -LiteralPath $hta -Raw
  # Static HTML id uniqueness catches the kind of overlap/control bug that slipped through earlier builds.
  # Strip script/style text first so dynamic templates such as id="card-"+id are not mistaken for real duplicate DOM controls.
  $static=[regex]::Replace($text,'(?is)<script\b[^>]*>.*?</script>','')
  $static=[regex]::Replace($static,'(?is)<style\b[^>]*>.*?</style>','')
  $ids=@([regex]::Matches($static,'\bid="([^"]+)"')|ForEach-Object {$_.Groups[1].Value});$dups=@($ids|Group-Object|Where-Object {$_.Count -gt 1})
  if($dups.Count){AddResult 'HTML control IDs' 'FAIL' ('Duplicate id(s): '+(($dups|ForEach-Object {$_.Name}) -join ', '))}else{AddResult 'HTML control IDs' 'PASS' (($ids.Count.ToString())+' static IDs are unique.')}

  $nav=@([regex]::Matches($text,'\bid="nav-([A-Za-z0-9_-]+)"')|ForEach-Object {$_.Groups[1].Value}|Sort-Object -Unique)
  $pages=@([regex]::Matches($text,'\bid="page-([A-Za-z0-9_-]+)"')|ForEach-Object {$_.Groups[1].Value}|Sort-Object -Unique)
  $missingPages=@($nav|Where-Object {$pages -notcontains $_});$missingNav=@($pages|Where-Object {$nav -notcontains $_})
  if($missingPages.Count -or $missingNav.Count){AddResult 'Navigation mapping' 'FAIL' ('nav without page: '+($missingPages -join ', ')+'; page without nav: '+($missingNav -join ', '))}else{AddResult 'Navigation mapping' 'PASS' (($nav.Count.ToString())+' navigation items map to pages.')}

  # The tweak catalogue is JSON embedded directly in JavaScript.
  $m=[regex]::Match($text,'(?s)var\s+tweaks\s*=\s*(\[.*?\]);\s*var\s+excludedItems\s*=')
  if(-not $m.Success){AddResult 'Tweak catalogue' 'FAIL' 'Could not locate the embedded tweak array.'}
  else{
    try{$tw=@($m.Groups[1].Value|ConvertFrom-Json);$dupT=@($tw|Group-Object id|Where-Object {$_.Count -gt 1});$missing=0;foreach($t in $tw){foreach($p in @('id','cat','name','desc','apply','undo','risk')){if(-not $t.PSObject.Properties[$p] -or [string]::IsNullOrWhiteSpace([string]$t.$p)){$missing++}}};if($dupT.Count -or $missing){AddResult 'Tweak catalogue' 'FAIL' (($tw.Count.ToString())+' tweaks; duplicate IDs='+$dupT.Count+'; missing required fields='+$missing)}else{AddResult 'Tweak catalogue' 'PASS' (($tw.Count.ToString())+' unique tweaks with apply/undo/description metadata.')}
      $active=($tw|ForEach-Object {[string]$_.apply+' '+[string]$_.undo}) -join "`n";$bad=@();foreach($rx in @('(?i)\bbcdedit\b','(?i)Set-ProcessMitigation[^\r\n]*-Disable','(?i)disableelamdrivers','(?i)integrityservices\s+disable','(?i)tpmbootentropy','(?i)\bnx\s+optout\b','(?i)\bnetcfg\s+-d\b','(?i)Disable-NetAdapterBinding','(?i)Image File Execution Options[^\r\n]*(Remove-Item|reg delete)')){if($active -match $rx){$bad += $rx}};if($bad.Count){AddResult 'Dangerous-command guard' 'FAIL' ('Blocked pattern(s) found in active tweak commands: '+($bad -join ', '))}else{AddResult 'Dangerous-command guard' 'PASS' 'No blocked boot/security/network-destructive patterns were found in one-click tweak commands.'}
    }catch{AddResult 'Tweak catalogue' 'FAIL' ('Embedded tweak JSON did not parse: '+$_.Exception.Message)}
  }

  if($text -match 'TWEAKING UTILITY // v22\.1' -and $text -match 'NATIVE APP'){AddResult 'Version markers' 'PASS' 'v22.1 native branding markers are present.'}else{AddResult 'Version markers' 'WARN' 'One or more v22.1 UI markers were not found.'}
}

$required=@('HardwareScan.ps1','LiveMonitorWorker.ps1','NetworkLab.ps1','StartupManager.ps1','GameDetect.ps1','InGameBenchmark.ps1','SensorSnapshot.ps1','assets\rennev-logo.png','assets\rennev.ico','assets\games\fortnite.png','assets\games\roblox.png')
$missing=@();foreach($r in $required){if(-not (Test-Path -LiteralPath (Join-Path $Root $r))){$missing += $r}}
if($missing.Count){AddResult 'Required runtime files' 'FAIL' ('Missing: '+($missing -join ', '))}else{AddResult 'Required runtime files' 'PASS' 'Core backends and visual assets are present.'}

$status=if($fail){'failed'}else{'ok'}
$lines=New-Object System.Collections.Generic.List[string];$lines.Add('status='+$status);$lines.Add('pass='+$pass);$lines.Add('warn='+$warn);$lines.Add('fail='+$fail);$lines.Add('summary='+(Clean ("$pass pass, $warn warning, $fail fail")));$i=0;foreach($d in $details){$lines.Add(('detail'+$i+'='+[uri]::EscapeDataString($d)));$i++}
[IO.File]::WriteAllLines($OutFile,$lines,[Text.Encoding]::ASCII)
if($fail){exit 2}else{exit 0}
