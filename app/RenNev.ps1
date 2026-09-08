# Ren Nev's Tweaking Utility v26
# PowerShell host + local loopback API + Chromium app window.
# No mshta.exe. No local C# compiler. No ExecutionPolicy Bypass.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$AppVersion = '26.0.0'
$AppRoot = Split-Path -Parent $PSCommandPath
$StateRoot = Join-Path $env:LOCALAPPDATA 'RenNevTweakingUtility'
$HostLog = Join-Path $StateRoot 'host.log'
New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
try { Add-Content -LiteralPath $HostLog -Value ((Get-Date -Format 's') + '  ----- Ren Nev startup -----') -Encoding UTF8 } catch { }

function Write-HostLog([string]$Text) {
    try { Add-Content -LiteralPath $HostLog -Value ((Get-Date -Format 's') + '  ' + $Text) -Encoding UTF8 } catch { }
}

function Test-Administrator {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-WindowsPowerShellExe {
    $p = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $p) { return $p }
    $c = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    throw 'Windows PowerShell 5.1 was not found.'
}

# Always run the actual app in Windows PowerShell 5.1. This also makes the
# behavior predictable if somebody launches the file from PowerShell 7.
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    $ps = Get-WindowsPowerShellExe
    Start-Process -FilePath $ps -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "' + $PSCommandPath + '"')
    exit
}

# Tweaks need administrator rights. The installer itself does not.
if (-not (Test-Administrator)) {
    try {
        $ps = Get-WindowsPowerShellExe
        $args = '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Hidden -File "' + $PSCommandPath + '"'
        Start-Process -FilePath $ps -Verb RunAs -ArgumentList $args | Out-Null
    } catch {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show("Ren Nev needs administrator access to change Windows settings.`r`n`r`n$($_.Exception.Message)", 'Ren Nev', 'OK', 'Warning') | Out-Null
    }
    exit
}

function Get-ChromiumBrowser {
    $candidates = @()
    foreach ($reg in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\brave.exe'
    )) {
        try {
            $rk = Get-Item -LiteralPath $reg -ErrorAction Stop
            $v = $rk.GetValue('')
            if ($v) { $candidates += [string]$v }
        } catch { }
    }
    foreach ($p in @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe",
        "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe"
    )) { if ($p) { $candidates += $p } }

    foreach ($p in $candidates) {
        try { if ($p -and (Test-Path -LiteralPath $p)) { return $p } } catch { }
    }
    return $null
}

# Single-instance handling. If Ren Nev is already running, reopen its existing UI
# instead of leaving the user with only an "already open" message.
$SessionFile = Join-Path $StateRoot 'host-session.txt'
$createdNew = $false
$mutex = [Threading.Mutex]::new($true, 'Local\RenNevTweakingUtility_v26', [ref]$createdNew)
if (-not $createdNew) {
    try {
        if (Test-Path -LiteralPath $SessionFile -PathType Leaf) {
            $existingUrl = ([IO.File]::ReadAllText($SessionFile)).Trim()
            if ($existingUrl -match '^http://127\.0\.0\.1:\d+/Launcher\.html$') {
                $existingBrowser = Get-ChromiumBrowser
                if ($existingBrowser) {
                    Start-Process -FilePath $existingBrowser -ArgumentList @("--app=$existingUrl", '--no-first-run', '--disable-session-crashed-bubble') | Out-Null
                    exit
                }
            }
        }
    } catch { Write-HostLog ('Could not reopen existing window: ' + $_.Exception.Message) }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show("Ren Nev is already running in the background, but its window could not be reopened. Wait about 10 seconds and try again.\r\n\r\nLog: $HostLog", 'Ren Nev', 'OK', 'Information') | Out-Null
    } catch { }
    exit
}

function ConvertTo-RnJson($Value) {
    return (@{ ok = $true; value = $Value } | ConvertTo-Json -Compress -Depth 10)
}
function ConvertTo-RnError([string]$Message) {
    return (@{ ok = $false; error = $Message } | ConvertTo-Json -Compress -Depth 6)
}

function Invoke-RnProcess([string]$Command, [bool]$Capture, [bool]$Wait) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    $psi.Arguments = '/d /c ' + $Command
    $psi.WorkingDirectory = $AppRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    if ($Capture) {
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        try { $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8 } catch { }
    }
    $p = New-Object Diagnostics.Process
    $p.StartInfo = $psi
    if (-not $p.Start()) { throw 'The process could not be started.' }
    if (-not $Wait -and -not $Capture) { return @{ ExitCode = 0; StdOut = ''; StdErr = '' } }
    if ($Capture) {
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        return @{ ExitCode = [int]$p.ExitCode; StdOut = [string]$outTask.Result; StdErr = [string]$errTask.Result }
    }
    $p.WaitForExit()
    return @{ ExitCode = [int]$p.ExitCode; StdOut = ''; StdErr = '' }
}

function Read-RnRegistryValue([string]$FullPath) {
    if ([string]::IsNullOrWhiteSpace($FullPath)) { return $null }
    $path = $FullPath.Replace('/', '\')
    $root = $null; $rest = $null
    if ($path -match '^(HKCU|HKEY_CURRENT_USER)\\(.+)$') { $root = 'HKCU:'; $rest = $Matches[2] }
    elseif ($path -match '^(HKLM|HKEY_LOCAL_MACHINE)\\(.+)$') { $root = 'HKLM:'; $rest = $Matches[2] }
    elseif ($path -match '^(HKCR|HKEY_CLASSES_ROOT)\\(.+)$') { $root = 'Registry::HKEY_CLASSES_ROOT'; $rest = $Matches[2] }
    elseif ($path -match '^(HKU|HKEY_USERS)\\(.+)$') { $root = 'Registry::HKEY_USERS'; $rest = $Matches[2] }
    else { return $null }
    $slash = $rest.LastIndexOf('\')
    if ($slash -lt 0) { return $null }
    $keyPart = $rest.Substring(0, $slash)
    $name = $rest.Substring($slash + 1)
    $keyPath = if ($root.EndsWith(':')) { $root + '\' + $keyPart } else { $root + '\' + $keyPart }
    try {
        $p = Get-ItemProperty -LiteralPath $keyPath -ErrorAction Stop
        $prop = $p.PSObject.Properties[$name]
        if ($prop) { return $prop.Value }
    } catch { }
    return $null
}

function Invoke-RnApi($Request) {
    $action = [string]$Request.action
    $a = $Request.args
    switch ($action) {
        'Ping' { return $true }
        'HostVersion' { return $AppVersion }
        'BaseDirectory' { return $AppRoot }
        'IsAdministrator' { return (Test-Administrator) }
        'RestartAsAdmin' { return $true }
        'ExpandEnvironmentStrings' { return [Environment]::ExpandEnvironmentVariables([string]$a.value) }
        'GetSpecialFolder' {
            $name = [string]$a.name
            switch -Regex ($name) {
                '^Desktop$' { return [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory) }
                '^Startup$' { return [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup) }
                '^Programs$' { return [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs) }
                '^AppData$' { return [Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData) }
                default { return [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory) }
            }
        }
        'RegRead' { return (Read-RnRegistryValue ([string]$a.path)) }
        'Run' {
            $r = Invoke-RnProcess -Command ([string]$a.command) -Capture:$false -Wait:([bool]$a.wait)
            return [int]$r.ExitCode
        }
        'ExecJson' {
            $r = Invoke-RnProcess -Command ([string]$a.command) -Capture:$true -Wait:$true
            return @{ exitCode = [int]$r.ExitCode; stdout = [string]$r.StdOut; stderr = [string]$r.StdErr }
        }
        'ReadAllText' {
            $p = [string]$a.path
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return '' }
            try { return [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8) } catch { return [IO.File]::ReadAllText($p) }
        }
        'WriteAllText' {
            $p = [string]$a.path; $text = [string]$a.text; $append = [bool]$a.append
            $dir = Split-Path -Parent $p
            if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $enc = New-Object Text.UTF8Encoding($false)
            if ($append) { [IO.File]::AppendAllText($p, $text, $enc) } else { [IO.File]::WriteAllText($p, $text, $enc) }
            return $true
        }
        'CombinePath' { return [IO.Path]::Combine([string]$a.a, [string]$a.b) }
        'ParentPath' { try { return [IO.Directory]::GetParent([string]$a.path).FullName } catch { return '' } }
        'FileExists' { return [IO.File]::Exists([string]$a.path) }
        'DirectoryExists' { return [IO.Directory]::Exists([string]$a.path) }
        'CreateDirectory' { [IO.Directory]::CreateDirectory([string]$a.path) | Out-Null; return $true }
        'DeleteFile' { try { if ([IO.File]::Exists([string]$a.path)) { [IO.File]::Delete([string]$a.path) }; return $true } catch { return $false } }
        'LastWriteUtcTicks' { try { return [IO.File]::GetLastWriteTimeUtc([string]$a.path).Ticks.ToString() } catch { return '0' } }
        'ShellExecute' {
            $file = [string]$a.file
            if ([IO.Path]::GetFileName($file) -ieq 'mshta.exe') { return 1 }
            $psi = New-Object Diagnostics.ProcessStartInfo
            $psi.FileName = $file
            $psi.Arguments = [string]$a.args
            $psi.WorkingDirectory = if ([string]::IsNullOrWhiteSpace([string]$a.directory)) { $AppRoot } else { [string]$a.directory }
            $psi.UseShellExecute = $true
            if (-not [string]::IsNullOrWhiteSpace([string]$a.verb)) { $psi.Verb = [string]$a.verb }
            [Diagnostics.Process]::Start($psi) | Out-Null
            return 0
        }
        default { throw "Unknown Ren Nev API action: $action" }
    }
}

function Get-ContentType([string]$Path) {
    switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.html' { 'text/html; charset=utf-8' }
        '.js' { 'application/javascript; charset=utf-8' }
        '.css' { 'text/css; charset=utf-8' }
        '.png' { 'image/png' }
        '.jpg' { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.ico' { 'image/x-icon' }
        '.wav' { 'audio/wav' }
        '.json' { 'application/json; charset=utf-8' }
        default { 'application/octet-stream' }
    }
}

function Write-HttpResponse($Stream, [int]$Status, [string]$ContentType, [byte[]]$Body) {
    $reason = if ($Status -eq 200) { 'OK' } elseif ($Status -eq 404) { 'Not Found' } elseif ($Status -eq 403) { 'Forbidden' } else { 'Error' }
    if ($null -eq $Body) { $Body = New-Object byte[] 0 }
    $head = "HTTP/1.1 $Status $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`nConnection: close`r`n`r`n"
    $hb = [Text.Encoding]::ASCII.GetBytes($head)
    $Stream.Write($hb, 0, $hb.Length)
    if ($Body.Length -gt 0) { $Stream.Write($Body, 0, $Body.Length) }
    $Stream.Flush()
}

function Read-HttpRequest($Client) {
    $stream = $Client.GetStream()
    $stream.ReadTimeout = 10000
    $ms = New-Object IO.MemoryStream
    $buf = New-Object byte[] 4096
    $headerEnd = -1
    while ($headerEnd -lt 0) {
        $n = $stream.Read($buf, 0, $buf.Length)
        if ($n -le 0) { break }
        $ms.Write($buf, 0, $n)
        if ($ms.Length -gt 131072) { throw 'HTTP header too large.' }
        $arr = $ms.ToArray()
        $start = [Math]::Max(0, $arr.Length - $n - 4)
        for ($i = $start; $i -le $arr.Length - 4; $i++) {
            if ($arr[$i] -eq 13 -and $arr[$i+1] -eq 10 -and $arr[$i+2] -eq 13 -and $arr[$i+3] -eq 10) { $headerEnd = $i; break }
        }
    }
    if ($headerEnd -lt 0) { throw 'Incomplete HTTP request.' }
    $all = $ms.ToArray()
    $header = [Text.Encoding]::ASCII.GetString($all, 0, $headerEnd)
    $lines = $header -split "`r`n"
    $first = $lines[0] -split ' '
    $method = $first[0]
    $target = $first[1]
    $length = 0
    foreach ($line in $lines | Select-Object -Skip 1) {
        if ($line -match '^Content-Length:\s*(\d+)') { $length = [int]$Matches[1] }
    }
    if ($length -gt 4MB) { throw 'HTTP request body too large.' }
    $body = New-Object byte[] $length
    $already = $all.Length - ($headerEnd + 4)
    if ($already -gt 0 -and $length -gt 0) {
        $copy = [Math]::Min($already, $length)
        [Array]::Copy($all, $headerEnd + 4, $body, 0, $copy)
        $offset = $copy
    } else { $offset = 0 }
    while ($offset -lt $length) {
        $n = $stream.Read($body, $offset, $length - $offset)
        if ($n -le 0) { break }
        $offset += $n
    }
    return @{ Stream = $stream; Method = $method; Target = $target; Body = $body }
}

$tokenBytes = New-Object byte[] 32
(New-Object Security.Cryptography.RNGCryptoServiceProvider).GetBytes($tokenBytes)
$Token = ([BitConverter]::ToString($tokenBytes)).Replace('-', '').ToLowerInvariant()
$lastHeartbeat = Get-Date
$listener = $null
$clientSeen = $false
$browserStartedAt = $null

try {
    $browserExe = Get-ChromiumBrowser
    if (-not $browserExe) {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show('Ren Nev needs Microsoft Edge, Google Chrome, or Brave to display its app window. Install one of those browsers and launch Ren Nev again.', 'Ren Nev', 'OK', 'Error') | Out-Null
        exit
    }

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $url = "http://127.0.0.1:$port/Launcher.html"
    Write-HostLog "Host started on loopback port $port with $([IO.Path]::GetFileName($browserExe))"

    $browserArgs = @("--app=$url", '--no-first-run', '--disable-session-crashed-bubble')
    try { [IO.File]::WriteAllText($SessionFile, $url, (New-Object Text.UTF8Encoding($false))) } catch { }
    $browserStartedAt = Get-Date
    Start-Process -FilePath $browserExe -ArgumentList $browserArgs | Out-Null

    while ($true) {
        if (-not $clientSeen -and $browserStartedAt -and ((Get-Date) - $browserStartedAt).TotalSeconds -gt 25) {
            Write-HostLog 'Browser did not connect to the Ren Nev host within 25 seconds.'
            try {
                Add-Type -AssemblyName System.Windows.Forms
                [Windows.Forms.MessageBox]::Show("Ren Nev started its background host, but the app window could not connect.\r\n\r\nTry launching Ren Nev again. If it still fails, check:\r\n$HostLog", 'Ren Nev', 'OK', 'Error') | Out-Null
            } catch { }
            break
        }
        if ($clientSeen -and ((Get-Date) - $lastHeartbeat).TotalSeconds -gt 10) { break }
        if (-not $listener.Pending()) { Start-Sleep -Milliseconds 25; continue }
        $client = $listener.AcceptTcpClient()
        try {
            $req = Read-HttpRequest $client
            $target = [string]$req.Target
            $pathPart = ($target -split '\?', 2)[0]
            # HTTP proxies and some Chromium setups can send an absolute request target
            # (for example http://127.0.0.1:12345/Launcher.html). Normalize that
            # back to only the local path before routing.
            if ($pathPart -match '^https?://') {
                try { $pathPart = ([Uri]$target).AbsolutePath } catch { }
            }

            if ($req.Method -eq 'POST' -and $pathPart -eq '/api') {
                $clientSeen = $true
                $lastHeartbeat = Get-Date
                try {
                    $bodyText = [Text.Encoding]::UTF8.GetString($req.Body)
                    $requestObj = $bodyText | ConvertFrom-Json
                    if ([string]$requestObj.token -ne $Token) {
                        $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-RnError 'Invalid local API token.'))
                        Write-HttpResponse $req.Stream 403 'application/json; charset=utf-8' $bytes
                    } else {
                        $value = Invoke-RnApi $requestObj
                        $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-RnJson $value))
                        Write-HttpResponse $req.Stream 200 'application/json; charset=utf-8' $bytes
                    }
                } catch {
                    $bytes = [Text.Encoding]::UTF8.GetBytes((ConvertTo-RnError $_.Exception.Message))
                    Write-HttpResponse $req.Stream 500 'application/json; charset=utf-8' $bytes
                }
                continue
            }

            if ($req.Method -ne 'GET') {
                Write-HttpResponse $req.Stream 404 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('Not found'))
                continue
            }

            $rel = [Uri]::UnescapeDataString($pathPart.TrimStart('/'))
            if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'Launcher.html' }
            if ($rel.Contains('..') -or $rel.Contains(':')) {
                Write-HttpResponse $req.Stream 403 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('Forbidden'))
                continue
            }
            $file = Join-Path $AppRoot ($rel -replace '/', '\\')
            $fullRoot = [IO.Path]::GetFullPath($AppRoot).TrimEnd('\\') + '\\'
            $fullFile = [IO.Path]::GetFullPath($file)
            if (-not $fullFile.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $fullFile -PathType Leaf)) {
                Write-HttpResponse $req.Stream 404 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('Not found'))
                continue
            }
            if ([IO.Path]::GetFileName($fullFile) -ieq 'Launcher.html') {
                $clientSeen = $true
                $lastHeartbeat = Get-Date
                $html = [IO.File]::ReadAllText($fullFile, [Text.Encoding]::UTF8)
                $inject = '<script>window.__RENNEV_TOKEN="' + $Token + '";</script><link rel="icon" href="/assets/rennev-logo.png">'
                $idx = $html.IndexOf('</head>', [System.StringComparison]::OrdinalIgnoreCase)
                if ($idx -ge 0) { $html = $html.Insert($idx, $inject) }
                $bytes = [Text.Encoding]::UTF8.GetBytes($html)
            } else { $bytes = [IO.File]::ReadAllBytes($fullFile) }
            Write-HttpResponse $req.Stream 200 (Get-ContentType $fullFile) $bytes
        } catch {
            Write-HostLog ('Request error: ' + $_.Exception.Message)
            try { Write-HttpResponse ($client.GetStream()) 500 'text/plain; charset=utf-8' ([Text.Encoding]::UTF8.GetBytes('Ren Nev host error')) } catch { }
        } finally {
            $lastHeartbeat = Get-Date
            try { $client.Close() } catch { }
        }
    }
} catch {
    Write-HostLog ('Fatal host error: ' + $_.Exception.ToString())
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show("Ren Nev could not start.`r`n`r`n$($_.Exception.Message)`r`n`r`nA log was written to:`r`n$HostLog", 'Ren Nev', 'OK', 'Error') | Out-Null
    } catch { }
} finally {
    try { if ($listener) { $listener.Stop() } } catch { }
    try { if ($SessionFile -and (Test-Path -LiteralPath $SessionFile)) { Remove-Item -LiteralPath $SessionFile -Force -ErrorAction SilentlyContinue } } catch { }
    try { if ($mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() } } catch { }
    Write-HostLog 'Host stopped.'
}
