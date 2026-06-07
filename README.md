# MSI Ivy Bridge Open Source

Optimization notes and PowerShell helpers for running MSI BlueStacks / MSI App Player on older Intel Ivy Bridge Xeon CPUs, especially the Xeon E5-2650 v2.

This project documents a real tuning session focused on ARM64 Android games running through BlueStacks' native bridge on x86_64 Windows. The goal was to improve emulator performance without modifying, resigning, or repacking the game APK.

## Tested Setup

- Host CPU: Intel Xeon E5-2650 v2, Ivy Bridge
- Host topology after BIOS change: 8 cores / 16 logical processors
- Emulator: MSI BlueStacks / MSI App Player, Pie64 instance
- ADB target: `127.0.0.1:5555`
- Native bridge observed: `libnb.so`
- ARM64 ISA mapping observed: `arm64 -> x86_64`
- Example app ABI observed: `arm64-v8a`
- Target game during the final tuning pass: Free Fire normal, not Free Fire MAX

## What This Does

The optimizer script:

- Stages the Pie64 instance for 8 vCPU when Hyper-Threading exposes 16 logical CPUs.
- Uses 6 vCPU when the host exposes only 8 logical CPUs.
- Keeps RAM at 8192 MB.
- Persists the powered-off VM profile with `BstkVMMgr.exe` when available.
- Preserves high-performance BlueStacks mode with `mem_opt_mode=0` and `enable_high_fps=1`.
- Keeps the BlueStacks FPS target at `240` for input fluidity.
- Enables Vulkan/AGA renderer settings already known to work on the tested machine.
- Sets ASTC decoding mode to `hardware` by default.
- Sets Windows AC power behavior to reduce latency without forcing the CPU minimum state to 100%.
- Applies runtime ART/dex2oat props suitable for Ivy Bridge:
  - `ssse3`
  - `sse4.1`
  - `sse4.2`
  - `popcnt`
  - `avx`
  - `f16c`
  - does not include `avx2`
- Sets Android animation scales to `0.0`.
- Stages Dalvik heap props for future app launches.
- Recompiles the selected Android package with `cmd package compile -m speed-profile`.
- Verifies CPU count, ABI, native bridge, and dexopt status.

## What This Does Not Do

- It does not modify game APKs.
- It does not resign packages.
- It does not patch anti-cheat code.
- It does not edit `/system/build.prop`.
- It does not hide emulator identity.
- It does not provide cheats, bypasses, or competitive advantages beyond local emulator performance tuning.
- It does not run a permanent timer-resolution loop.
- It does not require CPU minimum state at 100%.

## Usage

Open PowerShell and run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\run-msi-xeon-runtime-optimize.ps1" -AdbPort 5555 -LaunchApp
```

For a first setup, or after reinstalling MSI BlueStacks, also stage the MSI config:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\run-msi-xeon-runtime-optimize.ps1" -AdbPort 5555 -TuneConfig -LaunchApp
```

After every full Android/emulator restart, reapply the runtime ART props and dexopt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\run-msi-xeon-runtime-optimize.ps1" -AdbPort 5555
```

Verify the current state:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\msi-xeon-verify.ps1" -AdbPort 5555
```

Switch renderer profiles for an A/B test:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\msi-renderer-abtest.ps1" -Mode SetOpenGL -TargetFps 240
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\msi-renderer-abtest.ps1" -Mode SetVulkan -TargetFps 240
```

On the tested Free Fire normal setup, OpenGL AGA crashed during launch. Vulkan AGA is the recommended fallback profile.

Collect CPU/GPU metrics while the emulator is running:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\msi-renderer-abtest.ps1" -Mode Collect -Seconds 90
```

Run the elevated persistence check after closing the emulator VM:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\msi-xeon-admin-persistence-check.ps1"
```

If ASTC hardware causes visual artifacts on your GPU, revert it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\msi-xeon-optimize.ps1" -AdbPort 5555 -TuneConfig -AstcMode software -SetUltimatePower
```

## Important Notes

The ART `setprop` values from the public optimizer script are runtime state. They can reset after a full Android/emulator reboot, so rerun the optimizer after restarting MSI BlueStacks.

An offline `Data.vhdx` prop patch was tested during the original lab session, then abandoned as the recommended route. The final public workflow is runtime/startup based because it is easier to audit, easier to undo, and much less likely to corrupt a machine-specific virtual disk.

If the emulator is closed, the script can also try to persist the VirtualBox/BlueStacks VM profile through `BstkVMMgr.exe`. If the VM is running or locked, this step may fail harmlessly; the BlueStacks config file still remains staged.

If old timer or CPU experiments are still present on a machine, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\relax-cpu-no-loop-admin.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\reset-bcd-input-timers-admin.ps1"
```

## Files

- `tools/run-msi-xeon-runtime-optimize.ps1`: small wrapper for the recommended runtime/startup flow.
- `tools/msi-xeon-optimize.ps1`: main tuning script.
- `tools/msi-xeon-verify.ps1`: verification script.
- `tools/msi-xeon-admin-persistence-check.ps1`: elevated host/VM persistence check.
- `tools/msi-renderer-abtest.ps1`: reversible renderer profile and metrics helper.
- `tools/set-hd-player-priority.ps1`: elevated helper for setting `HD-Player.exe` to High priority.
- `tools/relax-cpu-no-loop-admin.ps1`: removes the old timer loop and keeps a non-100% CPU minimum.
- `tools/reset-bcd-input-timers-admin.ps1`: removes BCD timer overrides and backs up BCD first.
- `docs/technical-notes.md`: explanation of the technical findings.
- `docs/session-summary.md`: what was changed during the original tuning session.

## Disclaimer

This is an unofficial community project. It is not affiliated with MSI, BlueStacks, Garena, or Intel. Use at your own risk. Emulator and game updates can change behavior.
