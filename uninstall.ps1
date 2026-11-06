#Requires -Version 5.1
<#
    Revierte la instalacion usando la copia de seguridad mas reciente.
    Uso: powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
#>
[CmdletBinding()]
param(
    [Alias("Home")][string]$UserHome = $env:USERPROFILE,
    [switch]$ResetPowerPlan,
    [switch]$ResetGpuPreference,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-Ok   { param($Message) Write-Host "   OK  $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "   !   $Message" -ForegroundColor Yellow }

$UserHome = (Resolve-Path $UserHome).Path

# Presets que instala este repo (se eliminan si no estaban antes)
$installedPresets = @(
    ".lmstudio\config-presets\qwen35-4b-general-rapido.preset.json",
    ".lmstudio\config-presets\qwen35-4b-codigo.preset.json"
)
$installedConfig = @(
    ".config\opencode\opencode.json",
    ".config\opencode\instructions\local-models.md",
    ".lmstudio\apps\bionic\.internal\user-concrete-model-default-config\qwen\qwen3.5-4b.json"
)

$backup = Get-ChildItem $UserHome -Directory -Filter "lmstudio-opencode-backup-*" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $backup) {
    Write-Warn "No hay copia de seguridad en $UserHome. Se eliminaran solo los presets instalados."
    $restore = $null
}
else {
    Write-Ok "Usando copia de seguridad: $($backup.FullName)"
    $restore = $backup.FullName
}

# Archivos que existian antes -> se restauran
$restoredRelative = @()
if ($restore) {
    Get-ChildItem $restore -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($restore.Length).TrimStart('\')
        $restoredRelative += $relative
        $dest = Join-Path $UserHome $relative
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
            Copy-Item $_.FullName $dest -Force
        }
        Write-Ok "Restaurado: $relative"
    }
}

# Archivos instalados sin copia previa -> se eliminan
foreach ($relative in ($installedPresets + $installedConfig)) {
    if ($restoredRelative -contains $relative) { continue }
    $path = Join-Path $UserHome $relative
    if (Test-Path $path) {
        if (-not $DryRun) { Remove-Item $path -Force }
        Write-Ok "Eliminado: $relative"
    }
}

if ($ResetPowerPlan) {
    $balanced = "381b4222-f694-41f0-9685-ff5bb260df2e"
    if (-not $DryRun) { powercfg /setactive $balanced | Out-Null }
    Write-Ok "Plan de energia: Equilibrado"
}

if ($ResetGpuPreference) {
    $key = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (Test-Path $key) {
        $props = (Get-ItemProperty $key).PSObject.Properties |
            Where-Object { $_.Name -like "*llama-server.exe" -or $_.Name -like "*\Bionic.exe" }
        foreach ($p in $props) {
            if (-not $DryRun) { Remove-ItemProperty -Path $key -Name $p.Name -ErrorAction SilentlyContinue }
            Write-Ok "Preferencia de GPU eliminada: $($p.Name)"
        }
    }
}

Write-Host ""
Write-Host "Desinstalacion completada." -ForegroundColor Green
Write-Host "Para revertir el plan de energia:  .\uninstall.ps1 -ResetPowerPlan"
Write-Host "Para revertir la GPU:              .\uninstall.ps1 -ResetGpuPreference"
