# Technical Notes

## CPU Target

The tested host CPU was an Intel Xeon E5-2650 v2. It is an Ivy Bridge CPU with SSE4.1, SSE4.2, SSSE3, POPCNT, and AVX support, but no AVX2.

For this emulator workload, the tested profile uses:

- 6 vCPU when Hyper-Threading is off and Windows exposes 8 logical processors.
- 8 vCPU when Hyper-Threading is on and Windows exposes 16 logical processors.

Going beyond 8 vCPU was intentionally avoided because the Windows scheduler, GPU driver, audio, input, native bridge, and Android services still need host CPU time.

## Native Bridge

The observed Android properties showed:

```text
ro.dalvik.vm.native.bridge=libnb.so
ro.dalvik.vm.isa.arm64=x86_64
```

The practical result is that ARM64 app code is translated/executed through the emulator native bridge on an x86_64 Android userspace.

## App ABI Verification

The example package observed during testing reported:

```text
primaryCpuAbi=arm64-v8a
secondaryCpuAbi=null
splits=[base, asset_pack_install_time, config.arm64_v8a]
```

Unity also reported:

```text
CPU 'arm64-v8a'
```

That means the app was ARM64/v8a, not armeabi-v7a.

## ART / Dexopt

The optimizer applies runtime properties:

```text
dalvik.vm.isa.x86.variant=default
dalvik.vm.isa.x86.features=ssse3,sse4.1,sse4.2,-avx,-avx2,popcnt
dalvik.vm.isa.x86_64.variant=default
dalvik.vm.isa.x86_64.features=ssse3,sse4.1,sse4.2,-avx,-avx2,popcnt
```

It then runs:

```text
cmd package compile -m speed -f --check-prof false <package>
```

The verified target state was:

```text
x86_64: [status=speed]
```

## BlueStacks Config

The main config values staged by the script are:

```text
bst.fresh_cpu_core=8
bst.fresh_cpu_ram=8192
bst.mem_opt_mode=0
bst.instance.Pie64.cpus=8
bst.instance.Pie64.ram=8192
bst.instance.Pie64.enable_high_fps=1
bst.instance.Pie64.enable_vsync=0
bst.instance.Pie64.max_fps=60
bst.instance.Pie64.graphics_engine=aga
bst.instance.Pie64.graphics_renderer=vlcn
bst.instance.Pie64.astc_decoding_mode=hardware
```

When the VM is powered off, the script also attempts:

```text
BstkVMMgr.exe modifyvm Pie64 --cpus 8 --memory 8192 --vm-process-priority high --large-pages on
```

## Admin Persistence Check

The elevated persistence check writes a timestamped report under `outputs/` and backs up the touched BlueStacks files under `work/`.

In the verified session, the elevated check reported:

```text
IsAdmin: True
NumberOfCores: 8
NumberOfLogicalProcessors: 16
bst.instance.Pie64.cpus="8"
bst.instance.Pie64.ram="8192"
bst.mem_opt_mode="0"
modifyvm_exit=0
memory=8192
cpus=8
largepages="on"
vmprocpriority="high"
Power plan: Desempenho Maximo
```

This confirms persistence at the Windows power-plan, BlueStacks config-file, and powered-off VM-profile layers. ART `setprop` values remain Android runtime state and should be reapplied after a full emulator restart.

## Renderer A/B Testing

For Free Fire normal (`com.dts.freefireth`), the goal is not to move ARM64 translation to the GPU. The native bridge remains CPU-bound. The useful renderer test is lower host overhead and better frame pacing.

The reversible A/B helper stages:

```text
SetVulkan -> graphics_engine=aga, graphics_renderer=vlcn
SetOpenGL -> graphics_engine=aga, graphics_renderer=gl
```

Both profiles keep dedicated GPU preference, high FPS mode, vsync off, and hardware ASTC. The helper writes a BlueStacks config backup before changing renderer state.

Use `-TargetFps 240` or another explicit high value when comparing input feel. Keeping the same FPS target across profiles matters more than comparing renderer names in isolation.

In the tested Free Fire normal session, OpenGL AGA reached game startup but crashed shortly after with GL/EGL errors followed by a native `SIGSEGV` in `libhoudini.so`. The profile was reverted to Vulkan AGA with `TargetFps=240`.

## Known Residual Warning

Some BlueStacks builds keep this stock value in `/system/build.prop`:

```text
dalvik.vm.isa.x86_64.variant=x86_64
```

This can produce a launch warning like:

```text
Unexpected CPU variant for X86 using defaults: x86_64
```

The tuning session intentionally did not edit `/system/build.prop`, because changing the system image is higher risk and was not necessary for the final verified runtime state.
