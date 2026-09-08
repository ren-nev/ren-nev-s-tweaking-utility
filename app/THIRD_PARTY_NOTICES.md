# Third-party component notice

## Intel PresentMon Console

Ren Nev's Tweaking Utility does **not** bundle PresentMon in this ZIP. The optional in-game benchmark can download a pinned portable PresentMon Console binary only after the user confirms the install inside the app.

- Project: Intel / GameTechDev PresentMon
- Project page: https://github.com/GameTechDev/PresentMon
- License: MIT
- Pinned benchmark engine: PresentMon Console 2.5.1 x64
- Download source used by the installer: https://github.com/GameTechDev/PresentMon/releases/download/v2.5.1/PresentMon-2.5.1-x64.exe
- Expected SHA-256: `9BEC3083069F58F911E6A512F4806DB51A27BD096103087BC1D05EF54C80A191`

The installer refuses to use the downloaded binary if its SHA-256 does not match the pinned value.


## Optional LibreHardwareMonitor sensor provider

Ren Nev can optionally install/start LibreHardwareMonitor through Windows Package Manager when the user explicitly presses **Enable Advanced Sensors**. After that opt-in, Ren Nev may automatically restart the already-installed local sensor worker on later launches; it does not silently download/install the sensor package without the original opt-in. LibreHardwareMonitor is an independent open-source project licensed under MPL-2.0 and is not bundled into this archive. It is used only as an optional local hardware sensor source for CPU/GPU temperatures when Windows/vendor APIs do not expose those readings directly.

If Windows Package Manager is unavailable, the Advanced Sensors setup has a fallback for the official v0.9.6 portable asset from the project's GitHub release page. The fallback is pinned to `LibreHardwareMonitor.zip` and verifies SHA-256 `086D9F1B5A99E643EDC2CFAAAC16051685B551E4C5AC0B32A57C58C0E529C001` before extraction. A hash mismatch causes setup to stop.

- Project/source: https://github.com/LibreHardwareMonitor/LibreHardwareMonitor
- Release: v0.9.6
- License: MPL-2.0 (see the upstream project for full license/source)


## unknowntweaks reliability / monitoring research

Ren Nev v21 incorporates and independently adapts selected reliability, monitoring, startup-management, and network-measurement ideas/code from the MIT-licensed **unknowntweaks** project supplied for this development pass. The useful patterns include snapshot-before-change behavior, language-neutral Windows performance counters, physical-adapter filtering, and non-destructive startup state management. Ren Nev does not include the project's private-beta gate or copy its branding.

- Project: unknowntweaks
- Copyright: Copyright (c) 2026 unknowntweaks contributors
- License: MIT
- Full license text bundled at: `licenses/unknowntweaks-MIT.txt`

The upstream license also notes architectural inspiration from Chris Titus Tech's WinUtil under MIT.
