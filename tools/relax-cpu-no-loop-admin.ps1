param(
    [string]$TaskName = "Hold Timer Resolution 0.5ms"
)

$ErrorActionPreference = "Continue"

$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot "outputs"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportDir = Join-Path $outDir "relax-cpu-no-loop-$stamp"
$report = Join-Path $reportDir "report.txt"
New-Item -ItemType Directory -Force -Path $reportDir | Out-Null

function Log {
    param([string]$Text = "")
    Add-Content -LiteralPath $report -Value $Text -Encoding UTF8
    Write-Output $Text
}

function Get-ActiveSchemeGuid {
    $line = powercfg /GETACTIVESCHEME
    if ($line -match "([0-9a-fA-F-]{36})") {
        return $Matches[1]
    }
    return $null
}

function Use-HighPerformanceScheme {
    $scheme = Get-ActiveSchemeGuid
    $active = powercfg /GETACTIVESCHEME
    if ($active -match "Equilibrado|Balanced") {
        $schemes = powercfg /LIST
        $match = $schemes |
            Where-Object { $_ -match "Desempenho M|Ultimate|Alto desempenho|High performance" } |
            Select-Object -First 1
        if ($match -and $match -match "([0-9a-fA-F-]{36})") {
            $scheme = $Matches[1]
            powercfg /SETACTIVE $scheme | Out-Null
            Log ("Activated high performance scheme: " + $scheme)
        }
    } else {
        Log ("Keeping active scheme: " + $active)
    }
    return (Get-ActiveSchemeGuid)
}

function Set-ProcessorSetting {
    param(
        [string]$Scheme,
        [string]$Setting,
        [int]$Value,
        [string]$Name
    )

    $sub = "54533251-82be-4824-96c1-47b60b740d00"
    powercfg /SETACVALUEINDEX $Scheme $sub $Setting $Value | Out-Null
    $acExit = $LASTEXITCODE
    powercfg /SETDCVALUEINDEX $Scheme $sub $Setting $Value | Out-Null
    $dcExit = $LASTEXITCODE
    Log ("{0}={1} ac_exit={2} dc_exit={3}" -f $Name, $Value, $acExit, $dcExit)
}

function Remove-HoldTimerTask {
    param([string]$Name)

    $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if (-not $task) {
        Log ("Scheduled task not found: " + $Name)
        return
    }

    try {
        $safeTaskName = ($Name -replace '[\\/:*?"<>|]', '_') + ".xml"
        Export-ScheduledTask -TaskName $Name |
            Set-Content -LiteralPath (Join-Path $reportDir $safeTaskName) -Encoding UTF8
    } catch {
        Log ("Could not export scheduled task {0}: {1}" -f $Name, $_.Exception.Message)
    }

    try {
        Stop-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    } catch {
        Log ("Could not stop scheduled task {0}: {1}" -f $Name, $_.Exception.Message)
    }

    try {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
        Log ("Removed scheduled task: " + $Name)
    } catch {
        Log ("Could not remove scheduled task {0}: {1}" -f $Name, $_.Exception.Message)
    }
}

function Stop-HoldTimerProcesses {
    $matches = Get-CimInstance Win32_Process |
        Where-Object {
            $_.CommandLine -match "hold_timer_resolution_0_5ms\.ps1|Timer Resolution 0\.5ms"
        }

    foreach ($proc in $matches) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            Log ("Stopped loop process pid={0} name={1}" -f $proc.ProcessId, $proc.Name)
        } catch {
            Log ("Could not stop loop process pid={0}: {1}" -f $proc.ProcessId, $_.Exception.Message)
        }
    }

    if (-not $matches) {
        Log "No hold-timer loop process found."
    }
}

Log "Relax CPU profile and remove loop scripts"
Log ("Date: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Log ("User: " + [Security.Principal.WindowsIdentity]::GetCurrent().Name)

Use-HighPerformanceScheme | Out-Null
$scheme = Get-ActiveSchemeGuid
if ($scheme) {
    Set-ProcessorSetting -Scheme $scheme -Setting "893dee8e-2bef-41e0-89c6-b55d0929964c" -Value 5 -Name "processor_min_state"
    Set-ProcessorSetting -Scheme $scheme -Setting "bc5038f7-23e0-4960-96da-33abaf5935ec" -Value 100 -Name "processor_max_state"
    Set-ProcessorSetting -Scheme $scheme -Setting "0cc5b647-c1df-4637-891a-dec35c318583" -Value 10 -Name "core_parking_min_cores"
    Set-ProcessorSetting -Scheme $scheme -Setting "ea062031-0e34-4ff1-9b6d-eb1059334028" -Value 100 -Name "core_parking_max_cores"
    powercfg /SETACTIVE $scheme | Out-Null
} else {
    Log "Could not detect active power scheme."
}

Remove-HoldTimerTask -Name $TaskName
Stop-HoldTimerProcesses

Log ""
Log "Active scheme:"
powercfg /GETACTIVESCHEME | ForEach-Object { Log $_ }

Log ""
Log "Relevant processor settings:"
powercfg /Q SCHEME_CURRENT SUB_PROCESSOR |
    Select-String -Pattern "Estado de desempenho m|Estado de desempenho max|Estacionamento|Núcleos|Correntes Alternadas Atuais|Correntes Contínuas Atuais|0x00000005|0x0000000a|0x00000064" |
    ForEach-Object { Log $_.Line }

Log ""
Log ("Report: " + $report)
