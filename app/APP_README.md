# Ren Nev's Tweaking Utility v22.1

## v22.2 - simpler native installer flow

- The extracted folder now has one obvious `START HERE - BUILD AND INSTALL REN NEV.cmd` entry point.
- A successful build places `Ren Nev Setup.exe` at the top of the folder instead of making the user hunt through `dist`.
- Build errors are written to `BUILD LOG.txt` at the top level.
- The installed `RenNev.exe` requests administrator access directly because this utility already requires elevation to apply system tweaks.


v22.1 is the **native desktop app + installer** hotfix release. The normal app no longer launches through HTA/MSHTA. The existing dark-blue interface and tweak system are kept, but they now run inside a real Windows `RenNev.exe` host.


## v22.1 native build fix

- Removed the incorrect assumption that `System.Management.Automation.dll` lives beside `powershell.exe`.
- `RenNev.exe` now loads the Windows PowerShell automation engine at runtime through the GAC/Windows PowerShell installation.
- The C# build no longer references a hard-coded PowerShell DLL path, so the installer can be built on normal and many stripped/custom Windows installations.
- `START HERE - BUILD AND INSTALL REN NEV.cmd` now reports build failures clearly and opens the real installer after a successful build.

## What is new in v22

- **Real desktop app:** `RenNev.exe` opens as a normal Windows application with the R icon.
- **Real installer:** the release builder creates `RenNevSetup.exe`, which installs to Program Files, adds Start Menu/Desktop shortcuts, and registers an Uninstall entry in Windows Settings.
- **Cleaner security profile:** the native UI bridge removes ActiveX/HTA startup and the old `ExecutionPolicy Bypass` launch pattern. PowerShell backends are hosted in-process where possible.
- **Ask Ren Nev fixed:** clicking **ASK REN NEV** now takes you to the AI tab, automatically asks about the exact tweak you clicked, and immediately answers in simple language.
- **Better AI follow-ups:** Ren Nev can answer whether a tweak is on, whether it fits the detected PC, what performance difference is realistic, the downside, restart requirement, undo path, and technical Registry/command details when requested.
- **Installer/antivirus help:** Ren Nev can explain the native app, installer, signing, and why an unsigned optimizer may still get extra antivirus scrutiny.
- **v21 reliability stays:** exact restore-state logic, Startup Manager safety, Network Lab, Smart Scan measurement, and developer self-tests are kept.

## Build and install the native app

On Windows 10/11, double-click **`START HERE - BUILD AND INSTALL REN NEV.cmd`**. It uses the Windows .NET Framework C# compiler already checked by the script, creates `Ren Nev Setup.exe` at the top of the extracted folder, then opens that installer.

After installation, launch **Ren Nev's Tweaking Utility** from the desktop or Start Menu like a normal app. You no longer need to keep using a launcher script.

If you only want to create the installer without installing it, run **`Build Native Release.cmd`**.

## Important

This build environment cannot execute Windows-only WinForms, Registry, CIM/WMI, Task Scheduler, performance-counter, game-launch, or installer behavior. The source and UI are statically validated here, but the native EXE/installer must be compiled and runtime-tested on an actual Windows PC.

A native EXE removes several heuristic triggers from the old design, but an unsigned system optimizer can still show SmartScreen/antivirus warnings. Public distribution should use Authenticode code signing rather than telling users to disable antivirus.

---

## Previous release notes

# Ren Nev's Tweaking Utility v21

v21 is the **reliability + measurement** release. It keeps the simpler v20 layout, but strengthens what happens underneath so the utility is less likely to guess, mislabel a change, or report misleading hardware/network numbers.

## New in v21

- Live CPU/RAM/disk/network monitoring now prefers native Windows APIs and language-neutral PDH counters instead of relying on localized counter names. GPU load uses Windows GPU-engine counters with vendor fallbacks.
- Network Health Lab now measures **average ping, jitter, packet loss, and uncached DNS response time** on the adapter Windows is actually routing through.
- Registry, service, and supported scheduled-task tweaks now save the pre-change state before Ren Nev applies them. A snapshot failure causes the apply to be refused instead of leaving Undo uncertain.
- Active tweak labels distinguish **REN NEV** (this utility has a restore record) from **ALREADY SET** (Windows already had the setting active).
- Added a stronger developer self-test that parses the PowerShell backends and checks navigation, duplicate control IDs, the tweak catalogue, required files, and blocked dangerous command patterns.
- Ren Nev AI understands the new ownership labels, richer Network Lab results, and the stronger self-test.
- No new boot/security-disable or blanket network-offload tweaks were imported. The source material was used to improve engineering quality, not to bulk-add risky commands.
- Added the required MIT attribution for the open-source research used in this release.

## Run it

Extract the whole folder, then run `Start Launcher.cmd`. The first run rebuilds the v21 executable wrapper with the bundled R icon.

## Important

Windows-only sensor, Registry, service, Task Scheduler, game-launch and WMI/CIM behavior still has to be verified on a real Windows machine. Use **App Self-Test** after extracting a new build, and keep restore points/backups available before applying a large batch.

---

## Previous release notes

# Ren Nev's Tweaking Utility v20

v20 is the **simple feature-flow + AI polish** release. The tweak tabs stay grouped exactly like v19, while Smart Scan and Games now show the important action first and hide extra tools until you ask for them.

## New in v20

- Smart Scan now opens as a simple **Scan -> Recommendations -> Apply** flow. Hardware details, benchmarks and diagnostics are separate expandable panels instead of one huge page.
- The live hardware box starts with only CPU/GPU load and temperature; RAM/disk/network/sensor setup are behind **More Live Stats**.
- Games now puts the Fortnite/Roblox launch cards first and moves the five session-boost switches into one **Boost Settings** panel.
- Fortnite and Roblox use matching bundled game tiles so neither icon visually sticks out.
- Ren Nev AI is short-first, remembers tweak context, handles greetings/casual banter, knows more PC basics, understands scan-aware questions, and gives better answers for Game Boost, Debloat, Startup, benchmarks, networking and sensors.
- Added one-click **Benchmark** buttons to each game card that jump directly to the in-game benchmark panel.
- Existing tweak tabs, logo and dark-blue color identity were intentionally left alone.

## Run it

Extract the whole folder, then run `Start Launcher.cmd`. The first run rebuilds the v20 executable wrapper with the bundled R icon.

## Important

The local Ren Nev assistant is still a focused offline helper rather than a cloud LLM. Smart Scan, sensors, game detection and tweak execution must be tested on a real Windows PC because this build environment cannot run those Windows-only APIs.

---

## Previous release notes

# Ren Nev's Tweaking Utility v19

v19 is the **simpler UI + Ren Nev AI rebuild**. The dark-blue R identity stays the same, but the app is easier to navigate and explain to a beginner.

## New in v19

- Sidebar is sorted into **Start Here, Gaming, Cleanup, System, and Tools & Info** groups.
- Every tweak tab is split into simple sections such as **Background load, Windows feel, Core gaming, Bluetooth, Xbox features, Diagnostics & feedback**, and more.
- All 60 one-click tweak descriptions were rewritten in short plain English.
- Ren Nev AI now handles greetings/casual chat, PC basics, utility features, current tweak context, and short beginner-first tweak explanations.
- **Ask Ren Nev** on a tweak immediately gives a useful short explanation and keeps that tweak as the follow-up context.
- Smart Scan keeps the main scan/recommendation flow visible while self-test/synthetic tools are tucked behind **Show More Tools**.
- Glow/shadow effects were reduced; hover/page animations remain but are subtler.
- Home was simplified to the six most useful starting actions.

## Run it

Extract the entire folder, then run `Start Launcher.cmd`. The first run rebuilds `Ren Nev's Tweaking Utility.exe` for v19 using the bundled R icon.

## Important

Ren Nev AI is a local helper, not a full cloud language model. It is designed to explain this utility and common PC concepts quickly. Smart Scan and Windows-only sensors still need real-device testing on Windows.

---

## Previous release notes

# Ren Nev's Tweaking Utility v18

A Windows tuning/diagnostics utility built around **detected state, reversible changes, hardware-aware recommendations, and before/after measurement**.

## New in v18

- Startup Manager using Windows enable/disable state instead of deleting launch commands.
- Network Health Lab for route-aware gateway/internet/DNS/Wi-Fi diagnostics.
- Apps & Tools page for optional winget installs.
- Stronger Fortnite/Roblox install discovery.
- Expanded hardware scan (VRAM, active route, Wi-Fi, Secure Boot, VBS/HVCI).
- One persistent ~1-second live hardware monitor instead of spawning a new PowerShell process every refresh.
- Smarter Smart Scan recommendations using measured background/startup load.
- Updated Ren Nev AI knowledge for the new features.

## Run it

Extract the **entire folder**, then run `Start Launcher.cmd`. The first run attempts to build `Ren Nev's Tweaking Utility.exe` with the bundled icon and admin manifest. If the built-in .NET Framework compiler is unavailable, the launcher falls back to the HTA.

## Important

Ren Nev does not promise that every tweak increases FPS. Hardware, drivers, game settings, thermals, and the actual bottleneck matter more. Use Smart Scan and the Fortnite/Roblox BEFORE/AFTER benchmark, and restore changes that do not help.

---

## Existing feature notes

# Ren Nev's Tweaking Utility v17

A Windows tweaking/diagnostics launcher focused on **verified state, understandable descriptions, reversible changes, hardware-aware recommendations, and before/after testing**.

## What changed in v17

- **Smart Scan reliability:** the hardware probe now uses multiple Windows sources (CIM, WMI, PnP, Registry and native fallbacks) and reports a visible scan-confidence score instead of pretending unknown hardware was detected.
- **More hardware detail:** CPU architecture, multi-GPU identity, RAM type/speed, storage type/bus, system-drive free space, active adapter details, Wi-Fi signal when exposed, display resolution/refresh rate, monitor count, laptop/desktop status, battery state and power capabilities can feed the profile.
- **App Self-Test:** Smart Scan now has `RUN APP SELF-TEST` to check admin rights, PowerShell, the state folder, required files, the Windows hardware provider, sensor snapshot, optional frame engine and tweak-database integrity.
- **Exportable diagnostics:** `EXPORT SCAN REPORT` writes a plain-text report to the Desktop with detected hardware, scan confidence, current Smart Scan plan, applied tweaks and the last self-test result.
- **Temperature path fixed up:** NVIDIA temperature/load still uses the vendor tool when available. Optional LibreHardwareMonitor support now remembers the verified library path, restarts automatically on later utility launches, and the hidden worker stops after the utility stops refreshing its heartbeat. ACPI thermal zones are never labelled as CPU package temperature.
- **Safer Undo:** Registry and Windows-service tweaks that Ren Nev itself changes now save the exact pre-change value/start state. When you turn the tweak back off later, v17 prefers that exact backup over a guessed/default value and verifies the restore before deleting the backup.
- **Undo Last Change:** a new sidebar action can reverse the last verified toggle operation in the current session.
- **Ren Nev AI:** typo-tolerant tweak matching, better follow-up context, explanations of why Smart Scan did/did not recommend a setting, restore help, Smart Scan troubleshooting, self-test help and verified Debloat-result summaries.
- **UI guards:** Smart Scan has a timeout/watchdog so a failed probe cannot leave the whole scan UI permanently locked. Small success/warning/error toasts make state changes clearer without adding modal popups everywhere.

## Smart Scan philosophy

Smart Scan does not apply a generic preset. It tries to answer: *what hardware is here, what Windows setting is already active, what is currently consuming resources, and is there a real reason to recommend this change on this machine?*

A low-confidence hardware profile is shown as low confidence. Hardware-specific advice should not be trusted blindly until the missing provider/component is fixed or understood.

## Temperatures

Windows does not provide one universal CPU-package-temperature API across every desktop/laptop/CPU. Ren Nev therefore uses the best source it can verify:

1. an already-running LibreHardwareMonitor/OpenHardwareMonitor provider when exposed;
2. the optional Ren Nev LibreHardwareMonitor worker after the user explicitly enables Advanced Sensors;
3. NVIDIA's installed vendor utility for NVIDIA GPU temperature/load;
4. generic Windows counters for utilization only.

If a real CPU-package sensor cannot be found, the utility shows `--` rather than inventing a temperature.

## Benchmarks

The Fortnite/Roblox in-game BEFORE/AFTER test uses a frame-presentation capture engine when installed. Keep the same game settings, FPS cap, resolution, map/experience, route and test duration. Re-run small differences; a single small percentage change can be normal run-to-run noise.

## Scope / safety

- No anti-cheat bypasses, injection, client modification, undocumented boot/timer hacks, security-protection disables or blanket TCP/offload disabling.
- Game Boost changes Windows-side session settings only and restores its temporary changes after the game exits.
- Debloat targets selected optional user apps/startup entries, not core Windows/security/driver processes.
- Startup entries disabled by Ren Nev are backed up before removal.
- Create a Windows restore point before large batches of persistent changes.

## Run

1. Extract the **entire** folder.
2. Run `Start Launcher.cmd`.
3. On a Windows system with the built-in .NET Framework compiler available, the start script builds/uses `Ren Nev's Tweaking Utility.exe` with the custom R icon.
4. The first real in-game benchmark can offer the verified PresentMon frame-capture engine.
5. Advanced temperature support is optional; use **Enable Advanced Sensors** once if Windows/vendor APIs do not expose the CPU/GPU temperature you need.

See `FIX_NOTES_v17.md`, `RESEARCH_NOTES_v17.md`, and `THIRD_PARTY_NOTICES.md`.
