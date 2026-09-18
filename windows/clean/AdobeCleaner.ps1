#Requires -Version 5.1
<#
.SYNOPSIS
  Adobe cleanup helper: stop processes/services; optional full folder cleanup.
.PARAMETER Mode
  KillOnly | Full | DryRunFull
#>
param(
    [ValidateSet('KillOnly', 'Full', 'DryRunFull')]
    [string] $Mode = 'KillOnly'
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ManifestPath = Join-Path $Root '..\\..\\shared\\cleaner-manifest.json'
if (-not (Test-Path -LiteralPath $ManifestPath)) {
    Write-Error "Cleaner manifest not found: $ManifestPath"
    exit 1
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$logDir = Join-Path $env:USERPROFILE 'AppData\Local\AdobeEnvironmentToolkit'
$logFile = Join-Path $logDir 'cleaner.log'
function Write-Log([string] $Message) {
    try {
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    } catch { }
}

function Stop-AdobeProcesses {
    foreach ($name in $manifest.windows.processes) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "Stopping process: $($_.ProcessName)"
            Write-Log "taskkill process: $($_.ProcessName)"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

function Stop-AdobeServices {
    foreach ($svc in $manifest.windows.services) {
        Write-Host "Stopping service: $svc"
        Write-Log "sc stop $svc"
        & sc.exe stop $svc 2>$null | Out-Null
    }
}

function Expand-WindowsPaths {
    foreach ($p in $manifest.windows.paths_remove) {
        $expanded = [Environment]::ExpandEnvironmentVariables($p)
        if ($expanded -and $expanded -notmatch '%') {
            $expanded
        }
    }
}

function Remove-AdobePaths([bool] $DryRun) {
    foreach ($path in Expand-WindowsPaths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        if ($DryRun) {
            Write-Host "[dry-run] Remove-Item -Recurse -Force $(($path))"
            Write-Log "dry-run remove: $path"
            continue
        }
        Write-Host "Removing: $path"
        Write-Log "remove: $path"
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Log "=== start Mode=$Mode ==="
Write-Host "--- Adobe Environment Toolkit: Cleaner (Windows) Mode=$Mode ---"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Run as Administrator for services stop and Program Files cleanup."
}

if ($Mode -eq 'Full' -and -not $isAdmin) {
    Write-Error "Full mode requires Administrator."
    exit 1
}

Stop-AdobeProcesses
Stop-AdobeServices

if ($Mode -eq 'KillOnly') {
    Write-Log "=== end KillOnly ==="
    Write-Host "--- Done (processes/services). ---"
    exit 0
}

if ($Mode -eq 'DryRunFull') {
    Remove-AdobePaths -DryRun $true
    Write-Log "=== end DryRunFull ==="
    Write-Host "--- Dry run finished. ---"
    exit 0
}

if ($Mode -eq 'Full') {
    Write-Host "Type exactly: YES DELETE ADOBE"
    $line = Read-Host
    if ($line -ne 'YES DELETE ADOBE') {
        Write-Host "Cancelled."
        Write-Log "aborted: confirmation failed"
        exit 1
    }
    Remove-AdobePaths -DryRun $false
    Write-Log "=== end Full ==="
    Write-Host "--- Full cleanup pass finished. Reboot recommended. ---"
}
