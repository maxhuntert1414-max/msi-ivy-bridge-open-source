param(
    [ValidateSet("software", "hardware")]
    [string]$AstcMode = "hardware"
)

$ErrorActionPreference = "Continue"

$repoRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repoRoot "outputs"
$workDir = Join-Path $repoRoot "work"
New-Item -ItemType Directory -Force -Path $outDir, $workDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $outDir "admin-persistence-check-$stamp.md"

function Write-Report {
    param([string]$Text = "")
    Add-Content -LiteralPath $reportPath -Value $Text -Encoding UTF8
    Write-Output $Text
}

function Add-CommandBlock {
    param(
        [string]$Title,
        [scriptblock]$Command
    )

    Write-Report ""
    Write-Report "## $Title"
    Write-Report ""
    Write-Report '```text'
    try {
        $output = & $Command 2>&1 | Out-String -Width 240
        if (-not [string]::IsNullOrWhiteSpace($output)) {
            Write-Report $output.TrimEnd()
        }
    } catch {
        Write-Report ("ERROR: " + $_.Exception.Message)
    }
    Write-Report '```'
}

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

function Get-TargetVcpu {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    if ([int]$cpu.NumberOfLogicalProcessors -ge 16) {
        return 8
    }
    return 6
}

Write-Report "# MSI Ivy Bridge Admin Persistence Check"
Write-Report ""
Write-Report ("Date: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Report ("User: " + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
Write-Report ("IsAdmin: " + (Test-IsAdmin))

if (-not (Test-IsAdmin)) {
    Write-Report ""
    Write-Report "Result: FAILED - this script was not elevated."
    exit 10
}

$targetCpu = Get-TargetVcpu
$conf = "C:\ProgramData\BlueStacks_msi5\bluestacks.conf"
$vmFile = "C:\ProgramData\BlueStacks_msi5\Engine\Pie64\Pie64.bstk"
$mgr = "C:\Program Files\BlueStacks_msi5\BstkVMMgr.exe"

Add-CommandBlock "Host CPU" {
    Get-CimInstance Win32_Processor |
        Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed |
        Format-List
}

Add-CommandBlock "BlueStacks Processes Before Changes" {
    Get-Process |
        Where-Object { $_.ProcessName -match 'HD-|Bstk|BlueStacks|VBox' } |
        Select-Object ProcessName, Id, CPU, StartTime, PriorityClass, Path |
        Format-Table -AutoSize
}

if (Test-Path -LiteralPath $conf) {
    $backupDir = Join-Path $workDir "admin-persistence-backup-$stamp"
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    Copy-Item -LiteralPath $conf -Destination (Join-Path $backupDir "bluestacks.conf") -Force
    if (Test-Path -LiteralPath $vmFile) {
        Copy-Item -LiteralPath $vmFile -Destination (Join-Path $backupDir "Pie64.bstk") -Force
    }
    Get-ChildItem -LiteralPath $backupDir -File |
        Get-FileHash -Algorithm SHA256 |
        ForEach-Object { "{0}  {1}" -f $_.Hash, $_.Path } |
        Set-Content -LiteralPath (Join-Path $backupDir "SHA256SUMS.txt") -Encoding ASCII
    Write-Report ""
    Write-Report ("Backup: " + $backupDir)

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
} else {
    Write-Report ""
    Write-Report ("WARNING: BlueStacks config not found: " + $conf)
}

Add-CommandBlock "Persistent BlueStacks Config" {
    Select-String -Path $conf -Pattern 'fresh_cpu_core|fresh_cpu_ram|mem_opt_mode|Pie64\.cpus|Pie64\.ram|Pie64\.enable_high_fps|Pie64\.astc_decoding_mode|Pie64\.graphics_engine|Pie64\.graphics_renderer|Pie64\.max_fps|Pie64\.enable_vsync' |
        ForEach-Object { $_.Line } |
        Sort-Object
}

Add-CommandBlock "BstkVMMgr Persistent VM Profile" {
    if (-not (Test-Path -LiteralPath $mgr)) {
        "Missing BstkVMMgr: $mgr"
        return
    }

    & $mgr modifyvm Pie64 --cpus $targetCpu --memory 8192 --vm-process-priority high --large-pages on
    "modifyvm_exit=$LASTEXITCODE"
    & $mgr showvminfo Pie64 --machinereadable |
        Select-String -Pattern 'name=|memory=|cpus=|largepages|vmprocpriority|VMState=|paravirt'
}

Add-CommandBlock "Power Plan Persistence" {
    $schemes = powercfg /LIST
    $ultimate = ($schemes | Where-Object { $_ -match "Desempenho|Ultimate" } | Select-Object -First 1)
    if ($ultimate -and $ultimate -match "([0-9a-fA-F-]{36})") {
        $scheme = $Matches[1]
        powercfg /SETACTIVE $scheme | Out-Null
    } else {
        $schemeLine = powercfg /GETACTIVESCHEME
        if ($schemeLine -match "([0-9a-fA-F-]{36})") {
            $scheme = $Matches[1]
        }
    }

    $sub = "54533251-82be-4824-96c1-47b60b740d00"
    $settings = @(
        "893dee8e-2bef-41e0-89c6-b55d0929964c",
        "bc5038f7-23e0-4960-96da-33abaf5935ec",
        "0cc5b647-c1df-4637-891a-dec35c318583",
        "ea062031-0e34-4ff1-9b6d-eb1059334028"
    )
    foreach ($setting in $settings) {
        powercfg /SETACVALUEINDEX $scheme $sub $setting 100 | Out-Null
    }
    powercfg /SETACTIVE $scheme | Out-Null
    powercfg /GETACTIVESCHEME
    powercfg /Q SCHEME_CURRENT SUB_PROCESSOR |
        Select-String -Pattern 'Estado de desempenho minimo|Estado de desempenho m.nimo|Estado de desempenho máximo|Estado de desempenho maximo|Correntes Alternadas Atuais|0x00000064'
}

Add-CommandBlock "Execution Policy" {
    Get-ExecutionPolicy -List | Format-Table -AutoSize
}

Add-CommandBlock "Final BlueStacks Processes" {
    Get-Process |
        Where-Object { $_.ProcessName -match 'HD-|Bstk|BlueStacks|VBox' } |
        Select-Object ProcessName, Id, CPU, StartTime, PriorityClass, Path |
        Format-Table -AutoSize
}

Write-Report ""
Write-Report "Result: COMPLETED"
Write-Report ("TargetVcpu: " + $targetCpu)
Write-Report ("ReportPath: " + $reportPath)
