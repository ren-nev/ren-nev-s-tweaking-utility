# Ren Nev's Tweaking Utility v26

This repository is ready for the one-command PowerShell install method.

## Install

For this repository, use:

```powershell
irm "https://raw.githubusercontent.com/ren-nev/ren-nev-tweaking-utility/main/install.ps1" | iex
```

That one command contains the complete Ren Nev payload. It does **not** need a GitHub Release, a separate ZIP download, Visual Studio, `csc.exe`, `System.Management.Automation.dll`, or a local C# compiler.

The installer places the app under your local Programs folder, creates Ren Nev shortcuts on the Desktop and Start Menu, adds an uninstall entry to Windows Installed Apps, and launches Ren Nev.

Ren Nev itself is hosted by Windows PowerShell 5.1 and displayed in an Edge/Chrome/Brave app window. The host uses a random-token loopback API bound to `127.0.0.1`; it does not use `mshta.exe` or `ExecutionPolicy Bypass`. The shortcut launches the local, unblocked app with a process-only `RemoteSigned` policy so default Windows PowerShell execution-policy settings do not instantly close the app.



## v26 browser/startup fix

v26 fixes the case where the installer succeeded but the Chromium app window opened a local **Not found** page while the hidden Ren Nev host stayed alive. The local server now normalizes absolute-form browser requests, opens the explicit `/Launcher.html` route, only marks the UI as connected after a real launcher/API request, and releases the background host about 10 seconds after the UI stops sending heartbeats. If Ren Nev is launched twice while the host is still alive, it attempts to reopen the existing local app window instead of only saying that Ren Nev is already open.

## v25 startup fix

The v24 shortcut could install correctly and then close immediately on PCs where Windows PowerShell's effective script policy would not allow a local `.ps1` launched with `-File`. v25 repairs the shortcut, carries the same process-only `RemoteSigned` policy through the administrator relaunch and uninstaller, uses a session-local single-instance mutex, improves Chromium app-window launch arguments, and writes visible startup diagnostics to `%LOCALAPPDATA%\RenNevTweakingUtility\host.log`.

If an older build is already installed, simply run the install command again after replacing `install.ps1` on GitHub. It upgrades the files and rewrites the broken shortcut.

## Updating the GitHub installer

The editable app is in `app/`. After changing anything there, run:

```powershell
.\tools\Build-InstallScript.ps1
```

That rebuilds the self-contained `install.ps1` with a fresh SHA-256-protected embedded app payload. Commit/push the new `install.ps1` and the updated source files.

## Files that matter

- `install.ps1` — what users run through `irm ... | iex`.
- `app/` — the actual Ren Nev app source and assets.
- `app/RenNev.ps1` — local app host/server.
- `app/Launcher.html` — Ren Nev interface.
- `tools/Build-InstallScript.ps1` — regenerates `install.ps1` after updates.

## Antivirus note

A system-tweaking tool that changes Windows settings and runs with administrator rights can still receive extra scrutiny when it is unsigned. This build removes the old HTA/MSHTA launch path, local C# compilation, and `ExecutionPolicy Bypass`, but a future public release should still be code-signed if Ren Nev becomes widely distributed.

See `app/THIRD_PARTY_NOTICES.md` for third-party notices.
