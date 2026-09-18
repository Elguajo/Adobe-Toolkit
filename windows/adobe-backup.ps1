param(
  [ValidateSet('backup','restore')]$mode = 'backup',
  [string]$dest = "$PSScriptRoot\Backups",
  [switch]$dryRun,
  # Dangerous for restore: mirrors and may delete files in destination.
  [switch]$mirrorRestore
)

$ErrorActionPreference = "Stop"

function Invoke-Robocopy {
  param(
    [Parameter(Mandatory=$true)][string[]]$args,
    [string]$logFile = $null
  )

  if ($logFile) {
    $logDir = Split-Path -Parent $logFile
    if ($logDir) { New-Item -Force -ItemType Directory -Path $logDir | Out-Null }
    $args += "/LOG+:$logFile"
  }

  & robocopy @args
  # Robocopy uses bitmask exit codes; >=8 indicates failure.
  $rc = $LASTEXITCODE
  if ($rc -ge 8) {
    throw "Robocopy failed with exit code $rc. See log: $logFile"
  }
  return $rc
}

function Copy-Safe {
  param(
    [Parameter(Mandatory=$true)][string]$src,
    [Parameter(Mandatory=$true)][string]$dst,
    [string[]]$excludeDirs = @(),
    [string[]]$excludeFiles = @(),
    [switch]$mirror,
    [switch]$listOnly,
    [string]$logFile = $null
  )

  if (-not (Test-Path -LiteralPath $src)) { return }
  New-Item -Force -ItemType Directory -Path $dst | Out-Null

  # For restore we default to non-destructive copy: /E (include subdirs, including empty).
  # Mirror mode is for backup (safe into new folder) or explicit restore when user accepts deletions.
  $copyMode = if ($mirror) { "/MIR" } else { "/E" }

  $args = @(
    $src, $dst,
    $copyMode, "/R:1", "/W:1",
    "/NFL", "/NDL", "/NJH", "/NJS", "/NP",
    "/XJ"
  )

  if ($listOnly) { $args += "/L" }
  if ($excludeDirs.Count -gt 0)  { $args += "/XD"; $args += $excludeDirs }
  if ($excludeFiles.Count -gt 0) { $args += "/XF"; $args += $excludeFiles }

  [void](Invoke-Robocopy -args $args -logFile $logFile)
}

$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"

if ($mode -eq 'backup') {
  New-Item -Force -ItemType Directory -Path $dest | Out-Null
  $backupRoot = Join-Path $dest ("Adobe_Backup_" + $stamp)
  New-Item -Force -ItemType Directory -Path $backupRoot | Out-Null
} else {
  $backupRoot = $dest
}

# Logs
$logPath = Join-Path $backupRoot (Join-Path "logs" ("robocopy_" + $mode + "_" + $stamp + ".log"))

# "Smart exclusions" (similar spirit to macOS script)
$junkDirExcludes = @(
  "*Cache*", "*Caches*", "*Log*", "*Logs*", "*Temp*", "*tmp*",
  "*Media Cache*", "*Media Cache Files*"
)
$junkFileExcludes = @(
  "*.tmp", "*.lock", "*.log", "*.bak", "*.ds_store", "Thumbs.db", "desktop.ini"
)

# Standard Adobe plugin folders to ignore (custom-only backup)
$standardPluginDirExcludes = @(
  "(AdobePSL)",
  "Cineware by Maxon",
  "Effects",
  "Extensions",
  "File Formats",
  "Format",
  "Keyframe"
)

# Optional: add your own excludes here (customize without editing logic below)
$userPluginDirExcludes = @(
  # "YourVendorPluginFolderName"
)

function Expand-Patterns {
  param([string[]]$patterns)
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($p in $patterns) {
    $items = Get-ChildItem -Path $p -ErrorAction SilentlyContinue
    foreach ($it in $items) { $out.Add($it.FullName) }
  }
  return $out
}

function Backup-AbsolutePath {
  param(
    [Parameter(Mandatory=$true)][string]$app,
    [Parameter(Mandatory=$true)][string]$path,
    [string[]]$excludeDirs = @(),
    [string[]]$excludeFiles = @()
  )

  if (-not (Test-Path -LiteralPath $path)) { return 0 }

  $drive = ""
  $tail  = ""
  if ($path -match "^([A-Za-z]):\\(.*)$") {
    $drive = $Matches[1].ToUpperInvariant()
    $tail = $Matches[2]
  } else {
    # Fallback: store under Drive_Unknown
    $drive = "Unknown"
    $tail = ($path -replace "^[\\\\]+", "")
  }

  $dst = Join-Path $backupRoot (Join-Path $app (Join-Path ("Drive_" + $drive) $tail))
  Copy-Safe -src $path -dst $dst -excludeDirs $excludeDirs -excludeFiles $excludeFiles -mirror -listOnly:$dryRun -logFile $logPath
  return 1
}

function Restore-FromBackupRoot {
  param([Parameter(Mandatory=$true)][string]$appRoot)

  if (-not (Test-Path -LiteralPath $appRoot)) { return 0 }

  $copied = 0
  Get-ChildItem -LiteralPath $appRoot -Directory | ForEach-Object {
    $driveFolder = $_.Name
    if ($driveFolder -notlike "Drive_*") { return }

    $drive = $driveFolder.Substring(6)
    $driveBase = $_.FullName

    if ($drive -eq "Unknown") { return }
    $targetBase = ($drive + ":\")

    # Mirror each top-level folder under Drive_X back to X:\
    Get-ChildItem -LiteralPath $driveBase -Directory | ForEach-Object {
      $name = $_.Name
      $src  = $_.FullName
      $dst  = Join-Path $targetBase $name
      Copy-Safe -src $src -dst $dst -mirror:$mirrorRestore -listOnly:$dryRun -logFile $logPath
      $copied++
    }
  }

  return $copied
}

# -------- Selection (Windows) --------
$Selections = @{
  "AfterEffects" = @(
    "$env:APPDATA\Adobe\After Effects\*",
    "$env:USERPROFILE\Documents\Adobe\After Effects\*",
    "$env:ProgramFiles\Adobe\Adobe After Effects *\Support Files\Plug-ins",
    "$env:ProgramFiles\Adobe\Adobe After Effects *\Support Files\Scripts\ScriptUI Panels",
    "$env:ProgramFiles\Adobe\Common\Plug-ins\*\MediaCore"
  );
  "Photoshop" = @(
    "$env:APPDATA\Adobe\Adobe Photoshop *\Adobe Photoshop * Settings",
    "$env:APPDATA\Adobe\Adobe Photoshop *\Presets\Keyboard Shortcuts"
  );
  "Illustrator" = @(
    "$env:APPDATA\Adobe\Adobe Illustrator * Settings",
    "$env:APPDATA\Adobe\Adobe Illustrator *",
    "$env:ProgramFiles\Adobe\Adobe Illustrator *\Plug-ins",
    "$env:ProgramFiles\Adobe\Adobe Illustrator *\Presets\*\Scripts",
    "$env:ProgramFiles\Adobe\Adobe Illustrator *\Presets\*"
  );
  "PremierePro" = @(
    "$env:USERPROFILE\Documents\Adobe\Premiere Pro\*\Profile-*\Layouts",
    "$env:USERPROFILE\Documents\Adobe\Premiere Pro\*\Profile-*\Win",
    "$env:USERPROFILE\Documents\Adobe\Premiere Pro\*\Profile-*\Mac"
  );
  "CEP" = @(
    "$env:APPDATA\Adobe\CEP",
    "$env:ProgramFiles\Common Files\Adobe\CEP\extensions",
    "${env:ProgramFiles(x86)}\Common Files\Adobe\CEP\extensions"
  )
}

if ($mode -eq 'backup') {
  $copied = 0

  foreach ($app in $Selections.Keys) {
    $patterns = $Selections[$app]
    $matches = Expand-Patterns -patterns $patterns

    foreach ($p in $matches) {
      $excludeDirs = $junkDirExcludes
      $excludeFiles = $junkFileExcludes

      if ($app -eq "AfterEffects" -and $p -like "*\Plug-ins") {
        $excludeDirs = @($excludeDirs + $standardPluginDirExcludes + $userPluginDirExcludes)
      }
      if ($app -eq "Illustrator" -and $p -like "*\Plug-ins") {
        $excludeDirs = @($excludeDirs + $standardPluginDirExcludes + $userPluginDirExcludes)
      }

      $copied += (Backup-AbsolutePath -app $app -path $p -excludeDirs $excludeDirs -excludeFiles $excludeFiles)
    }
  }

  $meta = @{
    created = (Get-Date).ToString("o")
    host    = $env:COMPUTERNAME
    note    = "Adobe Environment Toolkit Windows backup (custom plugins, ScriptUI Panels, CEP; smart excludes)."
    itemsCopied = $copied
    apps    = $Selections.Keys
    dryRun  = [bool]$dryRun
    log     = (Split-Path -Leaf $logPath)
  }
  $metaPath = Join-Path $backupRoot "meta.json"
  $meta | ConvertTo-Json -Depth 6 | Out-File -Encoding UTF8 $metaPath

  Write-Host "Backup complete: $backupRoot  (items: $copied)"
  Write-Host "Robocopy log: $logPath"
} else {
  if (-not (Test-Path -LiteralPath $backupRoot)) {
    Write-Error "Backup folder not found: $backupRoot"
    exit 1
  }

  $total = 0
  Get-ChildItem -LiteralPath $backupRoot -Directory | ForEach-Object {
    $total += (Restore-FromBackupRoot -appRoot $_.FullName)
  }

  Write-Host "Restore complete (top-level roots: $total). Note: writing to Program Files may require running PowerShell as Administrator."
  Write-Host "Robocopy log: $logPath"
  if (-not $mirrorRestore) {
    Write-Host "Restore mode: safe copy (no deletions). Use -mirrorRestore to mirror (dangerous)."
  }
}
