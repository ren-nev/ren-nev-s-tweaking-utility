param([switch]$Stage2)
$ErrorActionPreference = 'SilentlyContinue'
$InstallRoot = Join-Path $env:LOCALAPPDATA "Programs\Ren Nev's Tweaking Utility"
$StartMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Ren Nev'
$DesktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) "Ren Nev's Tweaking Utility.lnk"
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RenNevTweakingUtility'

if (-not $Stage2) {
    $tmp = Join-Path $env:TEMP ('RenNev-Uninstall-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    Copy-Item -LiteralPath $PSCommandPath -Destination $tmp -Force
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $ps -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -File "' + $tmp + '" -Stage2')
    exit
}

try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" | Where-Object {
        $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf((Join-Path $InstallRoot 'RenNev.ps1'), [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch { }
Start-Sleep -Milliseconds 500
Remove-Item -LiteralPath $DesktopShortcut -Force
Remove-Item -LiteralPath $StartMenuDir -Recurse -Force
Remove-Item -LiteralPath $UninstallKey -Recurse -Force
Remove-Item -LiteralPath $InstallRoot -Recurse -Force
Remove-Item -LiteralPath $PSCommandPath -Force
