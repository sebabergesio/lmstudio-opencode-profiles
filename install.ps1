#Requires -Version 5.1
<#
    Instala la configuracion optimizada de LM Studio + OpenCode.
    Uso: powershell -ExecutionPolicy Bypass -File .\install.ps1
         powershell -ExecutionPolicy Bypass -File .\install.ps1 -Profile rtx4050-6gb
#>
[CmdletBinding()]
param(
    [Alias("Home")][string]$UserHome = $env:USERPROFILE,
    [ValidateSet("rx6600-8gb", "rtx4050-6gb")]
    [string]$Profile = "rx6600-8gb",
    [switch]$SkipPowerPlan,
    [switch]$SkipGpuPreference,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Write-Step { param($Message) Write-Host "== $Message" -ForegroundColor Cyan }
function Write-Ok   { param($Message) Write-Host "   OK  $Message" -ForegroundColor Green }
function Write-Warn { param($Message) Write-Host "   !   $Message" -ForegroundColor Yellow }

if (-not (Test-Path $UserHome)) { throw "No existe la ruta de usuario: $UserHome" }
$UserHome = (Resolve-Path $UserHome).Path
$RepoRoot = $PSScriptRoot
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition }

$lmRoot     = Join-Path $UserHome ".lmstudio"
$modelRoot  = Join-Path $lmRoot "apps\bionic\.internal\user-concrete-model-default-config"
$presetRoot = Join-Path $lmRoot "config-presets"
$ocRoot     = Join-Path $UserHome ".config\opencode"

$stamp      = Get-Date -Format "yyyyMMdd-HHmmss"
$backupRoot = Join-Path $UserHome "lmstudio-opencode-backup-$stamp"

Write-Step "Origen: $RepoRoot"
Write-Step "Perfil: $Profile"
Write-Step "Destino: $UserHome"
if ($DryRun) { Write-Warn "Modo simulacion: no se escribe nada" }

# Los perfiles son autocontenidos; si un archivo no existe en el perfil, se usa el de la raiz.
$profileRoot = Join-Path $RepoRoot "profiles\$Profile"
function Resolve-Source {
    param([string]$Relative)
    if (Test-Path (Join-Path $profileRoot $Relative)) { return "profiles\$Profile\$Relative" }
    return $Relative
}

# --- Comprobaciones previas -------------------------------------------------
if (-not (Test-Path (Join-Path $lmRoot "apps\bionic"))) {
    Write-Warn "No se encontro LM Studio en '$lmRoot\apps\bionic'."
    Write-Warn "Se copiara igualmente; revisa la ruta si usas otra version."
}

$sourceFiles = @(
    @{ Source = (Resolve-Source "lmstudio\models\qwen3.5-4b.json"); Dest = (Join-Path $modelRoot "qwen\qwen3.5-4b.json") },
    @{ Source = (Resolve-Source "opencode\instructions\local-models.md"); Dest = (Join-Path $ocRoot "instructions\local-models.md") },
    @{ Source = (Resolve-Source "opencode\opencode.json"); Dest = (Join-Path $ocRoot "opencode.json"); Template = $true }
)

$presetSource = Join-Path $profileRoot "lmstudio\presets"
if (-not (Test-Path $presetSource)) { $presetSource = Join-Path $RepoRoot "lmstudio\presets" }
if (Test-Path $presetSource) {
    $presetRel = "profiles\$Profile\lmstudio\presets"
    if (-not (Test-Path (Join-Path $profileRoot "lmstudio\presets"))) { $presetRel = "lmstudio\presets" }
    Get-ChildItem $presetSource -Filter *.preset.json | ForEach-Object {
        $sourceFiles += @{ Source = "$presetRel\$($_.Name)"; Dest = (Join-Path $presetRoot $_.Name) }
    }
}

foreach ($item in $sourceFiles) {
    $full = Join-Path $RepoRoot $item.Source
    if (-not (Test-Path $full)) { throw "Falta el archivo de origen: $full" }
    if ($full -like "*.json") {
        try { Get-Content $full -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null }
        catch { throw "JSON invalido en $full : $($_.Exception.Message)" }
    }
}
Write-Ok "Archivos de origen validados ($($sourceFiles.Count))"

# --- Copia de seguridad -----------------------------------------------------
$backedUp = 0
foreach ($item in $sourceFiles) {
    if (Test-Path $item.Dest) {
        $relative = $item.Dest.Substring($UserHome.Length).TrimStart('\')
        $backupFile = Join-Path $backupRoot $relative
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path (Split-Path $backupFile) | Out-Null
            Copy-Item $item.Dest $backupFile -Force
        }
        $backedUp++
    }
}
if ($backedUp -gt 0) { Write-Ok "Copia de seguridad: $backupRoot ($backedUp archivos)" }
else { Write-Ok "No habia archivos previos que respaldar" }

# --- Instalacion ------------------------------------------------------------
foreach ($item in $sourceFiles) {
    $source = Join-Path $RepoRoot $item.Source
    if ($DryRun) {
        Write-Host "   -> $($item.Dest)"
        continue
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $item.Dest) | Out-Null

    if ($item.Template) {
        $content = Get-Content $source -Raw -Encoding UTF8
        $posix = $ocRoot -replace '\\', '/'
        $content = $content.Replace("__OPENCODE_DIR__", $posix)
        [IO.File]::WriteAllText($item.Dest, $content, (New-Object Text.UTF8Encoding($false)))
    }
    else {
        if ($item.Dest -like "*.json") {
            # LM Studio ignora el JSON si lleva BOM: escribir siempre UTF-8 sin BOM.
            $content = Get-Content $source -Raw -Encoding UTF8
            [IO.File]::WriteAllText($item.Dest, $content, (New-Object Text.UTF8Encoding($false)))
        }
        else {
            Copy-Item $source $item.Dest -Force
        }
    }
    Write-Ok $item.Dest
}

if (-not $DryRun) {
    $jsonFiles = $sourceFiles | Where-Object { $_.Dest -like "*.json" }
    foreach ($j in $jsonFiles) {
        try { Get-Content $j.Dest -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null }
        catch { throw "El archivo instalado no es JSON valido: $($j.Dest)" }
    }
    $ocContent = Get-Content (Join-Path $ocRoot "opencode.json") -Raw -Encoding UTF8
    if ($ocContent -like "*__OPENCODE_DIR__*") { Write-Warn "No se pudo resolver la ruta de instrucciones en opencode.json" }
    Write-Ok "Configuracion de OpenCode escrita y validada"
}

# --- Plan de energia --------------------------------------------------------
if (-not $SkipPowerPlan) {
    Write-Step "Plan de energia"
    $plans = (powercfg /list) -join "`n"
    $amdHigh = "9935e61f-1661-40c5-ae2f-8495027d5d5d"
    $high    = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

    if ($plans -match $amdHigh) {
        if (-not $DryRun) { powercfg /setactive $amdHigh | Out-Null }
        Write-Ok "Activado: AMD Ryzen High Performance"
    }
    elseif ($plans -match $high) {
        if (-not $DryRun) { powercfg /setactive $high | Out-Null }
        Write-Ok "Activado: Alto rendimiento"
    }
    else {
        Write-Warn "No hay plan de alto rendimiento disponible; se deja el actual"
    }
}

# --- Preferencia de GPU -----------------------------------------------------
if (-not $SkipGpuPreference) {
    Write-Step "Preferencia de GPU (alto rendimiento)"
    $exes = @()

    $backend = Get-ChildItem (Join-Path $lmRoot "extensions\backends") -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*vulkan*" } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($backend -and (Test-Path (Join-Path $backend.FullName "llama-server.exe"))) {
        $exes += (Join-Path $backend.FullName "llama-server.exe")
    }

    $bionic = Get-Process Bionic -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bionic -and $bionic.Path) { $exes += $bionic.Path }

    if ($exes.Count -eq 0) {
        Write-Warn "No se encontro llama-server.exe ni Bionic.exe; se omite"
    }
    else {
        $key = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
        foreach ($exe in $exes) {
            if (-not $DryRun) {
                if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
                New-ItemProperty -Path $key -Name $exe -Value "GpuPreference=2;" -PropertyType String -Force | Out-Null
            }
            Write-Ok $exe
        }
    }
}

Write-Host ""
Write-Host "Listo. Perfil aplicado: $Profile" -ForegroundColor Green
Write-Host "1. Abre LM Studio para que cargue las configs y los presets."
Write-Host "2. Comprueba los modelos:  lms ps"
Write-Host "3. En OpenCode:            opencode models | Select-String lmstudio"
Write-Host "4. Copia de seguridad:     $backupRoot"
if ($DryRun) { Write-Host "Modo simulacion: no se aplico ningun cambio." -ForegroundColor Yellow }
