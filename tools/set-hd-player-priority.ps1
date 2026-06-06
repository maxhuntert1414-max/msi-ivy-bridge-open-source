param(
    [string]$OutFile = ""
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $outDir = Join-Path $repoRoot "outputs"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $OutFile = Join-Path $outDir "hd-player-priority-check.txt"
}

$lines = New-Object System.Collections.Generic.List[string]
$players = @(Get-Process -Name "HD-Player" -ErrorAction SilentlyContinue)

if ($players.Count -eq 0) {
    $lines.Add("missing_hd_player=true") | Out-Null
} else {
    foreach ($player in $players) {
        try {
            $player.PriorityClass = "High"
            $lines.Add(("set=ok pid={0}" -f $player.Id)) | Out-Null
        } catch {
            $lines.Add(("set=error pid={0} message={1}" -f $player.Id, $_.Exception.Message)) | Out-Null
        }

        try {
            $fresh = Get-Process -Id $player.Id -ErrorAction Stop
            $lines.Add(("pid={0} priority={1} base_priority={2}" -f $fresh.Id, $fresh.PriorityClass, $fresh.BasePriority)) | Out-Null
        } catch {
            $lines.Add(("read=error pid={0} message={1}" -f $player.Id, $_.Exception.Message)) | Out-Null
        }
    }
}

$lines | Set-Content -LiteralPath $OutFile -Encoding ASCII
$lines
