<#
.SYNOPSIS
    Converts (retargets) a legacy .NET Framework solution/project to a best-supported
    modern .NET version, keeping the existing UI stack (WinForms/console/library) as-is.

.DESCRIPTION
    Thin, repeatable wrapper around Microsoft's .NET Upgrade Assistant. It:
      1. Ensures the 'upgrade-assistant' global tool is installed (installs if missing).
      2. Opts out of first-run telemetry so it can run non-interactively.
      3. Runs an analysis pass (blocker report) and, unless -AnalyzeOnly, the upgrade.
      4. Optionally builds the result to confirm it compiles.

    The Upgrade Assistant performs the mechanical work: SDK-style .csproj conversion,
    target-framework retarget, and package/reference fix-ups. Blockers that require code
    changes (custom cultures, removed BCL APIs, COM interop, etc.) are listed in
    DotNet-Retarget-Guide.md and must be handled per the checklist there.

.PARAMETER Path
    Path to a .sln/.slnx/.csproj or a folder containing one.

.PARAMETER TargetFramework
    Target framework moniker or keyword. Default 'LTS' = the latest Long-Term-Support
    release (the "best supported" version). You may also pass e.g. net10.0-windows.

.PARAMETER Operation
    'Inplace' (default) rewrites the projects; 'SideBySide' creates a new copy.

.PARAMETER AnalyzeOnly
    Only produce the blocker analysis; do not modify anything.

.PARAMETER Build
    After upgrading, run 'dotnet build' to validate.

.EXAMPLE
    .\Convert-DotNetApp.ps1 -Path .\MyApp.sln
.EXAMPLE
    .\Convert-DotNetApp.ps1 -Path .\MyApp.sln -TargetFramework net10.0-windows -Build
.EXAMPLE
    .\Convert-DotNetApp.ps1 -Path .\MyApp.sln -AnalyzeOnly
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Path,
    [string] $TargetFramework = 'LTS',
    [ValidateSet('Inplace', 'SideBySide')] [string] $Operation = 'Inplace',
    [switch] $AnalyzeOnly,
    [switch] $Build
)

$ErrorActionPreference = 'Stop'
$env:DOTNET_UPGRADEASSISTANT_TELEMETRY_OPTOUT = '1'

function Test-Tool {
    (dotnet tool list -g 2>&1 | Select-String -Quiet 'upgrade-assistant')
}

Write-Host "== .NET App Modernizer ==" -ForegroundColor Cyan
Write-Host "Installed SDKs:" -ForegroundColor DarkCyan
dotnet --list-sdks

if (-not (Test-Tool)) {
    Write-Host "Installing .NET Upgrade Assistant global tool..." -ForegroundColor Yellow
    dotnet tool install -g upgrade-assistant | Out-Host
}
else {
    dotnet tool update -g upgrade-assistant 2>&1 | Out-Null
}

if (-not (Test-Path $Path)) { throw "Path not found: $Path" }
$full = (Resolve-Path $Path).Path

Write-Host "`nAnalyzing '$full' (target: $TargetFramework)..." -ForegroundColor Green
upgrade-assistant analyze $full --targetFramework $TargetFramework --non-interactive | Out-Host

if ($AnalyzeOnly) {
    Write-Host "`nAnalyze-only complete. Review the report above and DotNet-Retarget-Guide.md." -ForegroundColor Cyan
    return
}

Write-Host "`nUpgrading ($Operation) to $TargetFramework..." -ForegroundColor Green
upgrade-assistant upgrade $full --operation $Operation --targetFramework $TargetFramework --non-interactive | Out-Host

if ($Build) {
    Write-Host "`nBuilding..." -ForegroundColor Green
    dotnet build $full | Out-Host
}

Write-Host "`nDone. Handle any remaining blockers using DotNet-Retarget-Guide.md." -ForegroundColor Cyan
