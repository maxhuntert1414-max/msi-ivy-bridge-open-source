param(
    [int]$AdbPort = 5555,
    [string]$Package = "com.dts.freefireth"
)

$ErrorActionPreference = "Continue"
$adb = "C:\Program Files\BlueStacks_msi5\HD-Adb.exe"
$conf = "C:\ProgramData\BlueStacks_msi5\bluestacks.conf"
$device = "127.0.0.1:$AdbPort"

function Section($name) {
    ""
    "== $name =="
}

Section "Host"
Get-CimInstance Win32_Processor |
    Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed |
    Format-List

Section "BlueStacks config"
if (Test-Path -LiteralPath $conf) {
    Select-String -Path $conf -Pattern 'fresh_cpu_core|fresh_cpu_ram|mem_opt_mode|Pie64\.cpus|Pie64\.ram|Pie64\.enable_high_fps|Pie64\.astc_decoding_mode|Pie64\.graphics_engine|Pie64\.graphics_renderer|Pie64\.max_fps|Pie64\.enable_vsync' |
        ForEach-Object { $_.Line } |
        Sort-Object
} else {
    "Missing config: $conf"
}

Section "ADB"
& $adb connect $device | Out-Null
& $adb devices

Section "Guest CPU and bridge"
$cpuinfo = & $adb -s $device shell cat /proc/cpuinfo
$cpuinfo | Select-String -Pattern '^(processor|siblings|cpu cores)' | Select-Object -First 80
& $adb -s $device shell getprop ro.product.cpu.abilist
& $adb -s $device shell getprop ro.dalvik.vm.native.bridge
& $adb -s $device shell getprop ro.dalvik.vm.isa.arm64
& $adb -s $device shell getprop dalvik.vm.isa.x86_64.features

Section "Package ABI"
& $adb -s $device shell pm path $Package
$dump = & $adb -s $device shell dumpsys package $Package
$dump | Select-String -Pattern 'primaryCpuAbi|secondaryCpuAbi|legacyNativeLibraryDir|splits=|versionName=' | Select-Object -First 60

Section "Dexopt"
$dex = & $adb -s $device shell dumpsys package dexopt
$dex | Select-String -Pattern "\[$Package\]" -Context 0,5

Section "Focus"
& $adb -s $device shell dumpsys window windows |
    Select-String -Pattern 'mCurrentFocus|mFocusedApp'
