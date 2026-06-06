param(
    [ValidateSet("Status", "SetVulkan", "SetOpenGL", "SetDX11", "Collect")]
    [string]$Mode = "Status",
    [string]$Instance = "Pie64",
    [int]$Seconds = 90,
    [int]$SampleMs = 1000,
    [switch]$NoBackup
)

$ErrorActionPreference = "Continue"

$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot "outputs"
$workDir = Join-Path $repoRoot "work"
New-Item -ItemType Directory -Force -Path $outDir, $workDir | Out-Null

$conf = "C:\ProgramData\BlueStacks_msi5\bluestacks.conf"
$glCheck = "C:\Program Files\BlueStacks_msi5\HD-GLCheck.exe"
$player = "C:\Program Files\BlueStacks_msi5\HD-Player.exe"

function Log {
    param([string]$Message)
    "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
}

function Get-ConfValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    $line = Select-String -LiteralPath $Path -Pattern ("^" + [regex]::Escape($Key) + "=") | Select-Object -First 1
    if (-not $line) {
        return $null
    }
    return ($line.Line -replace ("^" + [regex]::Escape($Key) + "="), "").Trim('"')
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

function Backup-Config {
    if ($NoBackup) {
        return
    }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $workDir "renderer-abtest-backup-$stamp"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Copy-Item -LiteralPath $conf -Destination (Join-Path $backupDir "bluestacks.conf") -Force
    Get-FileHash -LiteralPath (Join-Path $backupDir "bluestacks.conf") -Algorithm SHA256 |
        ForEach-Object { "{0}  {1}" -f $_.Hash, $_.Path } |
        Set-Content -LiteralPath (Join-Path $backupDir "SHA256SUMS.txt") -Encoding ASCII
    Log "backup=$backupDir"
}

function Show-Status {
    Log "mode=Status"
    if (-not (Test-Path -LiteralPath $conf)) {
        Log "missing_config=$conf"
        return
    }

    $keys = @(
        "bst.prefer_dedicated_gpu",
        "bst.instance.$Instance.graphics_engine",
        "bst.instance.$Instance.graphics_renderer",
        "bst.instance.$Instance.vulkan_supported",
        "bst.instance.$Instance.astc_decoding_mode",
        "bst.instance.$Instance.enable_high_fps",
        "bst.instance.$Instance.enable_vsync",
        "bst.instance.$Instance.max_fps",
        "bst.instance.$Instance.dpi"
    )
    foreach ($key in $keys) {
        Log ("{0}={1}" -f $key, (Get-ConfValue -Path $conf -Key $key))
    }

    $gpuPrefKey = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (Test-Path $gpuPrefKey) {
        $gpuPref = (Get-ItemProperty -Path $gpuPrefKey).$player
        Log ("windows_gpu_preference={0}" -f $gpuPref)
    }

    Get-Process |
        Where-Object { $_.ProcessName -match 'HD-|Bstk|BlueStacks|VBox' } |
        Select-Object ProcessName, Id, CPU, WorkingSet64, Path |
        Format-Table -AutoSize
}

function Test-Renderer {
    param([ValidateSet("OpenGL", "DX11", "DX11Auto")] [string]$Renderer)

    if (-not (Test-Path -LiteralPath $glCheck)) {
        Log "missing_glcheck=$glCheck"
        return
    }

    $args = switch ($Renderer) {
        "OpenGL" { @("1", "2") }
        "DX11" { @("3", "2") }
        "DX11Auto" { @("4", "2") }
    }
    $out = & $glCheck @args 2>&1
    $important = $out | Select-String -Pattern "Checking for Renderer|PASS|FAIL|compatible|GL_VENDOR|GL_RENDERER|GL_VERSION|Vulkan device found|Considering Vulkan physical device"
    $important | ForEach-Object { Log ("glcheck: " + $_.Line.Trim()) }
    Log ("glcheck_exit={0}" -f $LASTEXITCODE)
}

function Set-RendererProfile {
    param([ValidateSet("Vulkan", "OpenGL", "DX11")] [string]$Profile)

    if (-not (Test-Path -LiteralPath $conf)) {
        throw "BlueStacks config not found: $conf"
    }

    $running = Get-Process -Name "HD-Player" -ErrorAction SilentlyContinue
    if ($running) {
        Log "warning=HD-Player is running; close/restart the emulator for renderer changes to take effect."
    }

    Backup-Config

    $rendererValue = switch ($Profile) {
        "Vulkan" { "vlcn" }
        "OpenGL" { "gl" }
        "DX11" { "dx" }
    }

    if ($Profile -eq "OpenGL") {
        Test-Renderer -Renderer OpenGL
    } elseif ($Profile -eq "DX11") {
        Test-Renderer -Renderer DX11
    }

    Set-ConfValue -Path $conf -Key "bst.prefer_dedicated_gpu" -Value "1"
    Set-ConfValue -Path $conf -Key "bst.instance.$Instance.graphics_engine" -Value "aga"
    Set-ConfValue -Path $conf -Key "bst.instance.$Instance.graphics_renderer" -Value $rendererValue
    Set-ConfValue -Path $conf -Key "bst.instance.$Instance.astc_decoding_mode" -Value "hardware"
    Set-ConfValue -Path $conf -Key "bst.instance.$Instance.enable_high_fps" -Value "1"
    Set-ConfValue -Path $conf -Key "bst.instance.$Instance.enable_vsync" -Value "0"

    Log ("profile={0}" -f $Profile)
    Log ("graphics_engine={0}" -f (Get-ConfValue -Path $conf -Key "bst.instance.$Instance.graphics_engine"))
    Log ("graphics_renderer={0}" -f (Get-ConfValue -Path $conf -Key "bst.instance.$Instance.graphics_renderer"))
    Log ("astc_decoding_mode={0}" -f (Get-ConfValue -Path $conf -Key "bst.instance.$Instance.astc_decoding_mode"))
    Log "restart_required=true"
}

function Get-GpuCountersForPid {
    param([int]$Pid)
    $set = Get-Counter -ListSet "GPU Engine" -ErrorAction SilentlyContinue
    if (-not $set) {
        return @()
    }
    return @($set.PathsWithInstances | Where-Object { $_ -like "*pid_$Pid_*" -and $_ -like "*Utilization Percentage" })
}

function Collect-Metrics {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $csvPath = Join-Path $outDir "renderer-metrics-$stamp.csv"
    $summaryPath = Join-Path $outDir "renderer-metrics-$stamp.md"
    $logical = [int](Get-CimInstance Win32_Processor | Select-Object -First 1).NumberOfLogicalProcessors
    $interval = [math]::Max(200, $SampleMs)
    $iterations = [math]::Max(1, [math]::Ceiling(($Seconds * 1000) / $interval))
    $prev = @{}
    $rows = New-Object System.Collections.Generic.List[object]

    Log ("collect_seconds={0}" -f $Seconds)
    Log ("collect_interval_ms={0}" -f $interval)
    Log ("csv={0}" -f $csvPath)

    for ($i = 0; $i -lt $iterations; $i++) {
        $now = Get-Date
        $players = @(Get-Process -Name "HD-Player" -ErrorAction SilentlyContinue)
        foreach ($p in $players) {
            $prevKey = [string]$p.Id
            $cpuTotalPct = 0.0
            $cpuNormalizedPct = 0.0
            if ($prev.ContainsKey($prevKey)) {
                $dt = ($now - $prev[$prevKey].Time).TotalSeconds
                $dcpu = [double]$p.CPU - [double]$prev[$prevKey].Cpu
                if ($dt -gt 0) {
                    $cpuTotalPct = ($dcpu / $dt) * 100.0
                    $cpuNormalizedPct = $cpuTotalPct / [math]::Max(1, $logical)
                }
            }
            $prev[$prevKey] = @{ Time = $now; Cpu = $p.CPU }

            $gpu3D = 0.0
            $gpuCompute = 0.0
            $gpuCopy = 0.0
            $gpuOther = 0.0
            $counters = Get-GpuCountersForPid -Pid $p.Id
            if ($counters.Count -gt 0) {
                $sample = Get-Counter -Counter $counters -ErrorAction SilentlyContinue
                foreach ($s in $sample.CounterSamples) {
                    $value = [double]$s.CookedValue
                    if ($s.Path -match "engtype_(High Priority 3D|3D)") {
                        $gpu3D += $value
                    } elseif ($s.Path -match "engtype_.*Compute") {
                        $gpuCompute += $value
                    } elseif ($s.Path -match "engtype_Copy") {
                        $gpuCopy += $value
                    } else {
                        $gpuOther += $value
                    }
                }
            }

            $rows.Add([pscustomobject]@{
                Timestamp = $now.ToString("o")
                Pid = $p.Id
                ProcessName = $p.ProcessName
                CpuTotalPct = [math]::Round($cpuTotalPct, 2)
                CpuNormalizedPct = [math]::Round($cpuNormalizedPct, 2)
                WorkingSetMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
                Gpu3DPct = [math]::Round($gpu3D, 2)
                GpuComputePct = [math]::Round($gpuCompute, 2)
                GpuCopyPct = [math]::Round($gpuCopy, 2)
                GpuOtherPct = [math]::Round($gpuOther, 2)
            }) | Out-Null
        }
        Start-Sleep -Milliseconds $interval
    }

    if ($rows.Count -eq 0) {
        Log "no_hd_player_samples=true"
        return
    }

    $rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $usable = $rows | Where-Object { $_.CpuTotalPct -gt 0 -or $_.Gpu3DPct -gt 0 -or $_.GpuComputePct -gt 0 -or $_.GpuCopyPct -gt 0 }
    if (-not $usable) {
        $usable = $rows
    }

    $currentRenderer = Get-ConfValue -Path $conf -Key "bst.instance.$Instance.graphics_renderer"
    $currentEngine = Get-ConfValue -Path $conf -Key "bst.instance.$Instance.graphics_engine"

    $summary = @(
        "# Renderer Metrics $stamp",
        "",
        "- Config renderer: $currentRenderer",
        "- Config engine: $currentEngine",
        "- Seconds: $Seconds",
        "- Samples: $($rows.Count)",
        "- CSV: $csvPath",
        "",
        '```text',
        ("CPU total avg: {0:n2}%" -f (($usable | Measure-Object CpuTotalPct -Average).Average)),
        ("CPU normalized avg: {0:n2}%" -f (($usable | Measure-Object CpuNormalizedPct -Average).Average)),
        ("GPU 3D avg: {0:n2}%" -f (($usable | Measure-Object Gpu3DPct -Average).Average)),
        ("GPU compute avg: {0:n2}%" -f (($usable | Measure-Object GpuComputePct -Average).Average)),
        ("GPU copy avg: {0:n2}%" -f (($usable | Measure-Object GpuCopyPct -Average).Average)),
        '```'
    )
    $summary | Set-Content -LiteralPath $summaryPath -Encoding UTF8
    Log ("summary={0}" -f $summaryPath)
    Get-Content -LiteralPath $summaryPath
}

switch ($Mode) {
    "Status" { Show-Status }
    "SetVulkan" { Set-RendererProfile -Profile Vulkan; Show-Status }
    "SetOpenGL" { Set-RendererProfile -Profile OpenGL; Show-Status }
    "SetDX11" { Set-RendererProfile -Profile DX11; Show-Status }
    "Collect" { Collect-Metrics }
}
