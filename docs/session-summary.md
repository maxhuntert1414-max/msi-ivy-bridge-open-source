# Session Summary

This repository came from a hands-on tuning session for MSI BlueStacks on an Ivy Bridge Xeon.

## Verified Final Runtime

- Host CPU: Intel Xeon E5-2650 v2
- Hyper-Threading: enabled
- Windows topology: 8 cores / 16 logical processors
- BlueStacks instance: Pie64
- Guest runtime: 8 processors / 8 CPU cores
- RAM: about 8 GB exposed to Android
- Renderer: Vulkan/AGA path
- ASTC: hardware mode staged and visually confirmed by the user
- Native bridge: `libnb.so`
- ARM64 mapping: `arm64 -> x86_64`
- Example app ABI: `arm64-v8a`
- Dexopt: `x86_64 [status=speed-profile]`
- Elevated persistence check: admin run confirmed config, VM profile, and power plan persistence

## Changes Made

1. Enabled and accounted for Hyper-Threading.
2. Raised Pie64 from 4/6 vCPU to 8 vCPU after HT was enabled.
3. Preserved high-performance mode after finding that earlier config edits could make the emulator fall back to a low-memory preset.
4. Set BlueStacks RAM to 8192 MB in both fresh and instance-specific config keys.
5. Kept high FPS enabled and vsync disabled.
6. Set ASTC mode to hardware after confirming GPU support and visual correctness.
7. Applied Ivy Bridge-specific ART feature props including AVX, while leaving AVX2 out.
8. Recompiled the target package with dexopt speed-profile mode.
9. Avoided APK/system mutation that would increase account or anti-cheat risk.
10. Added an elevated persistence check for the BlueStacks config, `BstkVMMgr` VM profile, and Windows power plan.
11. Disabled Android animations and staged Dalvik heap runtime props for future app launches.

## Commands Used Most Often

Apply config and runtime tuning:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\msi-xeon-optimize.ps1" -AdbPort 5555 -TuneConfig -SetUltimatePower -LaunchApp
```

Verify current runtime:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\msi-xeon-verify.ps1" -AdbPort 5555
```

Verify persistent host/VM settings:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\msi-xeon-admin-persistence-check.ps1"
```

## What Was Left Alone

- Game APK contents and signatures.
- `/system/build.prop`.
- Anti-cheat internals.
- Emulator identity masking.

The final result was a usable emulator profile tuned for the tested Xeon/Ivy Bridge host, while keeping the game package untouched.
