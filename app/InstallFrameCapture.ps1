param(
  [Parameter(Mandatory=$true)][string]$ToolsDir,
  [Parameter(Mandatory=$true)][string]$StatusPath
)
$ErrorActionPreference='Stop'
$Url='https://github.com/GameTechDev/PresentMon/releases/download/v2.5.1/PresentMon-2.5.1-x64.exe'
$Expected='9BEC3083069F58F911E6A512F4806DB51A27BD096103087BC1D05EF54C80A191'
function S([string]$state,[string]$msg){ @("state=$state","message=$msg") | Set-Content -LiteralPath $StatusPath -Encoding ASCII }
try{
  New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
  $dest=Join-Path $ToolsDir 'PresentMon-2.5.1-x64.exe'
  if(Test-Path -LiteralPath $dest){
    $h=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToUpperInvariant()
    if($h -eq $Expected){ S 'complete' 'Intel PresentMon Console 2.5.1 is ready.'; exit 0 }
    Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
  }
  S 'downloading' 'Downloading Intel PresentMon Console 2.5.1 from the official GitHub release...'
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $tmp=$dest+'.download'
  Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
  $hash=(Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToUpperInvariant()
  if($hash -ne $Expected){ Remove-Item $tmp -Force -ErrorAction SilentlyContinue; throw "SHA-256 verification failed. Expected $Expected but received $hash." }
  Move-Item -LiteralPath $tmp -Destination $dest -Force
  S 'complete' 'Intel PresentMon Console 2.5.1 is ready and its SHA-256 matched the pinned Microsoft WinGet manifest.'
}catch{
  S 'failed' (($_.Exception.Message -replace '[\r\n=]+',' '))
  exit 2
}
