param(
    [string]$OutDir = "C:\Users\maxhu\Documents\Codex\2026-06-05\ei-codex-meu-disco-c-ta\outputs"
)

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$report = Join-Path $OutDir "reset-bcd-input-timers-$stamp.txt"
$backup = Join-Path $OutDir "BCD-backup-before-input-timer-reset-$stamp.bcd"

function Write-Log {
    param([string]$Text = "")
    Add-Content -LiteralPath $report -Value $Text -Encoding UTF8
}

function Add-Block {
    param(
        [string]$Title,
        [scriptblock]$Body
    )
    Write-Log ""
    Write-Log "## $Title"
    Write-Log ""
    try {
        $output = & $Body 2>&1 | Out-String -Width 240
        Write-Log $output.TrimEnd()
    } catch {
        Write-Log ("ERROR: " + $_.Exception.Message)
    }
}

Write-Log "Reset BCD input/timer tweaks"
Write-Log ("Date: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Log ("User: " + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
Write-Log ("BCD backup: " + $backup)

Add-Block "Export BCD Backup" {
    bcdedit /export "$backup"
    "exit=$LASTEXITCODE"
}

Add-Block "BCD Before" {
    bcdedit /enum ACTIVE
}

Add-Block "Delete Timer Overrides" {
    foreach ($value in @("useplatformtick", "disabledynamictick", "tscsyncpolicy")) {
        "Deleting $value"
        & bcdedit /deletevalue "{current}" $value
        "exit=$LASTEXITCODE"
    }
}

Add-Block "BCD After" {
    bcdedit /enum ACTIVE
}

Write-Log ""
Write-Log "Reboot required for BCD changes to take effect."
Write-Log ("Report: " + $report)
Write-Output $report
