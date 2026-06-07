param(
    [int]$AdbPort = 5555,
    [string]$Package = "com.dts.freefireth",
    [int]$WaitSeconds = 90,
    [switch]$LaunchApp,
    [switch]$SetUltimatePower,
    [switch]$TuneConfig,
    [switch]$SkipAdb,
    [switch]$AssumeHyperThreading,
    [ValidateSet("software", "hardware")]
    [string]$AstcMode = "hardware",
    [string]$FeatureString = "ssse3,sse4.1,sse4.2,popcnt,avx,f16c"
)

$ErrorActionPreference = "Continue"

$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot "outputs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir "msi-xeon-optimizer.log"

function Log($msg) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Add-Content -LiteralPath $logPath -Value $line -Encoding ASCII
    Write-Output $line
}

function Run-Adb([string[]]$ArgsList) {
    $adb = "C:\Program Files\BlueStacks_msi5\HD-Adb.exe"
    if (-not (Test-Path -LiteralPath $adb)) {
        throw "HD-Adb.exe not found at $adb"
    }
    & $adb @ArgsList 2>&1
}

function Get-TargetDevice {
    param([int]$Port, [string]$Pkg, [int]$DeadlineSeconds)

    $deadline = (Get-Date).AddSeconds($DeadlineSeconds)
    $preferred = "127.0.0.1:$Port"

    while ((Get-Date) -lt $deadline) {
        Run-Adb @("connect", $preferred) | Out-Null
        $devices = Run-Adb @("devices")
        if ($devices -match [regex]::Escape($preferred) + "\s+device") {
            return $preferred
        }

        if ($devices -match "emulator-5554\s+device") {
            $pm = Run-Adb @("-s", "emulator-5554", "shell", "pm", "path", $Pkg)
            if ($pm -match [regex]::Escape($Pkg)) {
                return "emulator-5554"
            }
        }

        Start-Sleep -Seconds 3
    }

    return $null
}

function Optimize-HostProcess {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $logical = [int]$cpu.NumberOfLogicalProcessors
    if ($logical -lt 2) {
        Log "Skipping affinity: only $logical logical CPU reported."
        return
    }

    # Keep CPU0 mostly free for Windows/DWM/input; give BlueStacks the remaining logical CPUs.
    $mask = ([int64]1 -shl $logical) - 2

    $players = Get-Process -Name "HD-Player" -ErrorAction SilentlyContinue
    foreach ($p in $players) {
        try {
            $p.PriorityClass = "High"
            $p.ProcessorAffinity = [IntPtr]$mask
            Log ("HD-Player pid={0} priority=High affinity=0x{1:X}" -f $p.Id, $mask)
        } catch {
            Log ("Could not tune HD-Player pid={0}: {1}" -f $p.Id, $_.Exception.Message)
        }
    }
}

function Set-ConfValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Value
    )

    $escaped = [regex]::Escape($Key)
    $lines = Get-Content -LiteralPath $Path
    $found = $false
    $updated = foreach ($line in $lines) {
        if ($line -match "^$escaped=") {
            $found = $true
            "$Key=`"$Value`""
        } else {
            $line
        }
    }
    if (-not $found) {
        $updated += "$Key=`"$Value`""
    }
    Set-Content -LiteralPath $Path -Value $updated -Encoding ASCII
}

function Get-HostLogicalCpu {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $logical = [int]$cpu.NumberOfLogicalProcessors
    if ($AssumeHyperThreading) {
        $logical = 16
    }
    return $logical
}

function Get-TargetVcpu {
    param([int]$LogicalCpu)

    # Xeon E5-2650 v2: 6 vCPU while HT is off (8 logical), 8 vCPU after HT is on (16 logical).
    if ($LogicalCpu -ge 16) {
        return 8
    }
    return 6
}

function Tune-BlueStacksConfig {
    $conf = "C:\ProgramData\BlueStacks_msi5\bluestacks.conf"
    if (-not (Test-Path -LiteralPath $conf)) {
        Log "BlueStacks conf not found: $conf"
        return
    }

    $backupDir = Join-Path $repoRoot ("work\msi-xeon-optimize-conf-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Copy-Item -LiteralPath $conf -Destination (Join-Path $backupDir "bluestacks.conf") -Force
    Get-FileHash -LiteralPath (Join-Path $backupDir "bluestacks.conf") -Algorithm SHA256 |
        ForEach-Object { "{0}  {1}" -f $_.Hash, $_.Path } |
        Set-Content -LiteralPath (Join-Path $backupDir "SHA256SUMS.txt") -Encoding ASCII
    Log "Config backup written: $backupDir"

    $logical = Get-HostLogicalCpu
    $targetCpu = Get-TargetVcpu -LogicalCpu $logical

    Set-ConfValue -Path $conf -Key "bst.fresh_cpu_core" -Value ([string]$targetCpu)
    Set-ConfValue -Path $conf -Key "bst.fresh_cpu_ram" -Value "8192"
    Set-ConfValue -Path $conf -Key "bst.mem_opt_mode" -Value "0"
    Set-ConfValue -Path $conf -Key "bst.instance.Pie64.cpus" -Value ([string]$targetCpu)
    Set-ConfValue -Path $conf -Key "bst.instance.Pie64.ram" -Value "8192"
    Set-ConfValue -Path $conf -Key "bst.instance.Pie64.enable_high_fps" -Value "1"
    Set-ConfValue -Path $conf -Key "bst.instance.Pie64.enable_vsync" -Value "0"
    Set-ConfValue -Path $conf -Key "bst.instance.Pie64.max_fps" -Value "240"
    Set-ConfValue -Path $conf -Key "bst.instance.Pie64.graphics_engine" -Value "aga"
    Set-ConfValue -Path $conf -Key "bst.instance.Pie64.graphics_renderer" -Value "vlcn"
    Set-ConfValue -Path $conf -Key "bst.instance.Pie64.astc_decoding_mode" -Value $AstcMode
    Set-ConfValue -Path $conf -Key "bst.enable_native_gamepad" -Value "0"
    Set-ConfValue -Path $conf -Key "bst.enable_gamepad_detection" -Value "0"
    Set-ConfValue -Path $conf -Key "bst.enable_gamepad_vibration" -Value "0"

    Log "BlueStacks Pie64 config tuned for logical_cpu=$logical target_vcpu=$targetCpu astc=$AstcMode"
}

function Set-PersistentBlueStacksVmProfile {
    $mgr = "C:\Program Files\BlueStacks_msi5\BstkVMMgr.exe"
    if (-not (Test-Path -LiteralPath $mgr)) {
        Log "BstkVMMgr.exe not found: $mgr"
        return
    }

    $logical = Get-HostLogicalCpu
    $targetCpu = Get-TargetVcpu -LogicalCpu $logical

    $modify = & $mgr modifyvm Pie64 --cpus $targetCpu --memory 8192 --vm-process-priority high --large-pages on 2>&1
    $modify | ForEach-Object { Log "BstkVMMgr modifyvm: $_" }

    if ($LASTEXITCODE -eq 0) {
        Log "Persistent VM profile set: Pie64 cpus=$targetCpu memory=8192 vmprocpriority=high largepages=on"
    } else {
        Log "Persistent VM profile could not be set; VM may be running or locked. exit=$LASTEXITCODE"
    }

    $info = & $mgr showvminfo Pie64 --machinereadable 2>&1
    $info | Select-String -Pattern "memory=|cpus=|largepages|vmprocpriority|VMState=" |
        ForEach-Object { Log ("BstkVMMgr showvminfo: " + $_.Line.Trim()) }
}

function Set-UltimatePowerPlan {
    $schemes = powercfg /LIST
    $ultimate = ($schemes | Where-Object { $_ -match "Desempenho|Ultimate" } | Select-Object -First 1)
    if ($ultimate -and $ultimate.Line -match "([0-9a-fA-F-]{36})") {
        $guid = $Matches[1]
        powercfg /SETACTIVE $guid | Out-Null
        Log "Power plan set active: $guid"
    } elseif ($ultimate -and $ultimate -match "([0-9a-fA-F-]{36})") {
        $guid = $Matches[1]
        powercfg /SETACTIVE $guid | Out-Null
        Log "Power plan set active: $guid"
    } else {
        Log "Ultimate/Desempenho Maximo plan not found; keeping current plan."
    }
}

function Set-ProcessorLatencyProfile {
    $schemeLine = powercfg /GETACTIVESCHEME
    if ($schemeLine -notmatch "([0-9a-fA-F-]{36})") {
        Log "Could not detect active power scheme for processor latency profile."
        return
    }

    $scheme = $Matches[1]
    $processorSubgroup = "54533251-82be-4824-96c1-47b60b740d00"
    $settings = @(
        @("893dee8e-2bef-41e0-89c6-b55d0929964c", 5, "processor min state"),
        @("bc5038f7-23e0-4960-96da-33abaf5935ec", 100, "processor max state"),
        @("0cc5b647-c1df-4637-891a-dec35c318583", 10, "core parking min cores"),
        @("ea062031-0e34-4ff1-9b6d-eb1059334028", 100, "core parking max cores")
    )

    foreach ($setting in $settings) {
        powercfg /SETACVALUEINDEX $scheme $processorSubgroup $setting[0] $setting[1] | Out-Null
        powercfg /SETDCVALUEINDEX $scheme $processorSubgroup $setting[0] $setting[1] | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Log ("Power AC/DC {0}={1}" -f $setting[2], $setting[1])
        } else {
            Log ("Could not set power AC/DC {0}; exit={1}" -f $setting[2], $LASTEXITCODE)
        }
    }

    powercfg /SETACTIVE $scheme | Out-Null
}

Log "=== MSI Xeon optimizer start ==="

if ($TuneConfig) {
    Tune-BlueStacksConfig
    Set-PersistentBlueStacksVmProfile
}

if ($SetUltimatePower) {
    Set-UltimatePowerPlan
    Set-ProcessorLatencyProfile
}

Optimize-HostProcess

if ($SkipAdb) {
    Log "SkipAdb requested; leaving after host/config tuning."
    Log "=== MSI Xeon optimizer complete ==="
    exit 0
}

$device = Get-TargetDevice -Port $AdbPort -Pkg $Package -DeadlineSeconds $WaitSeconds
if (-not $device) {
    Log "No target ADB device found for port $AdbPort and package $Package."
    exit 2
}

Log "ADB target: $device"

$propCmd = @(
    "setprop dalvik.vm.isa.x86.variant default",
    "setprop dalvik.vm.isa.x86.features $FeatureString",
    "setprop dalvik.vm.isa.x86_64.variant default",
    "setprop dalvik.vm.isa.x86_64.features $FeatureString",
    "setprop dalvik.vm.heapsize 512m",
    "setprop dalvik.vm.heapmaxfree 8m",
    "setprop dalvik.vm.heaptargetutilization 0.75",
    "settings put global window_animation_scale 0.0",
    "settings put global transition_animation_scale 0.0",
    "settings put global animator_duration_scale 0.0",
    "for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do if [ -e `"`$g`" ] && [ -w `"`$g`" ]; then echo performance > `"`$g`" 2>/dev/null; fi; done"
) -join "; "

Run-Adb @("-s", $device, "shell", $propCmd) | ForEach-Object { Log "setprop: $_" }

$verifyProps = Run-Adb @(
    "-s", $device, "shell",
    "getprop dalvik.vm.isa.x86.variant; getprop dalvik.vm.isa.x86.features; getprop dalvik.vm.isa.x86_64.variant; getprop dalvik.vm.isa.x86_64.features"
)
$verifyProps | ForEach-Object { Log "prop: $_" }

$pkgPath = Run-Adb @("-s", $device, "shell", "pm", "path", $Package)
if ($pkgPath -notmatch [regex]::Escape($Package)) {
    Log "Package $Package not installed on $device."
    exit 3
}

Run-Adb @("-s", $device, "logcat", "-c") | Out-Null
$compile = Run-Adb @("-s", $device, "shell", "cmd package compile -m speed-profile -f --check-prof false $Package 2>&1")
$compile | ForEach-Object { Log "compile: $_" }

$dexopt = Run-Adb @("-s", $device, "shell", "dumpsys package dexopt 2>/dev/null")
$dexBlock = $dexopt | Select-String -Pattern "\[$Package\]" -Context 0,10
$dexBlock | ForEach-Object { Log ("dexopt: " + $_.Line.Trim()) }

$warnings = Run-Adb @("-s", $device, "logcat", "-d")
$warningHits = $warnings | Select-String -Pattern "Unexpected CPU variant|Mismatch between dex2oat instruction set features|Feature string"
if ($warningHits) {
    $warningHits | ForEach-Object { Log ("warning: " + $_.Line.Trim()) }
} else {
    Log "dex2oat CPU variant/features warnings: none after optimization."
}

if ($LaunchApp) {
    Run-Adb @("-s", $device, "shell", "am force-stop $Package") | Out-Null
    Run-Adb @("-s", $device, "shell", "monkey -p $Package -c android.intent.category.LAUNCHER 1") | ForEach-Object { Log "launch: $_" }
}

Optimize-HostProcess
Log "=== MSI Xeon optimizer complete ==="
