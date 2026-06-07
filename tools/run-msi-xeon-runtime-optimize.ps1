param(
    [int]$AdbPort = 5555,
    [string]$Package = "com.dts.freefireth",
    [switch]$LaunchApp,
    [switch]$TuneConfig,
    [switch]$SkipPower
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$optimizer = Join-Path $PSScriptRoot "msi-xeon-optimize.ps1"

if (-not (Test-Path -LiteralPath $optimizer)) {
    throw "Missing optimizer script: $optimizer"
}

$argsList = @(
    "-AdbPort", $AdbPort,
    "-Package", $Package
)

if ($TuneConfig) {
    $argsList += "-TuneConfig"
}

if (-not $SkipPower) {
    $argsList += "-SetUltimatePower"
}

if ($LaunchApp) {
    $argsList += "-LaunchApp"
}

Write-Output "Running MSI Xeon runtime optimizer from $root"
Write-Output ("ADB port: {0}" -f $AdbPort)
Write-Output ("Package: {0}" -f $Package)
Write-Output ("TuneConfig: {0}" -f [bool]$TuneConfig)
Write-Output ("SetUltimatePower: {0}" -f (-not $SkipPower))
Write-Output ("LaunchApp: {0}" -f [bool]$LaunchApp)

& $optimizer @argsList
exit $LASTEXITCODE
