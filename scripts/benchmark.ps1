#Requires -Version 5.1
<#
    Mide generacion y prefill contra el servidor local de LM Studio.
    Uso: powershell -ExecutionPolicy Bypass -File .\scripts\benchmark.ps1
         powershell -ExecutionPolicy Bypass -File .\scripts\benchmark.ps1 -Model "qwen/qwen3.5-4b@q4_k_m"
#>
[CmdletBinding()]
param(
    [string]$Model = "qwen/qwen3.5-4b",
    [string]$BaseUrl = "http://127.0.0.1:1234",
    [int]$Runs = 3
)

$ErrorActionPreference = "Stop"
$endpoint = "$BaseUrl/v1/chat/completions"

try {
    $models = Invoke-RestMethod -Uri "$BaseUrl/v1/models" -TimeoutSec 10
}
catch {
    throw "No se puede conectar con LM Studio en $BaseUrl. Abre LM Studio y activa el servidor local."
}

$available = $models.data | ForEach-Object { $_.id }
if ($available -notcontains $Model) {
    Write-Host "Modelo '$Model' no encontrado. Disponibles:" -ForegroundColor Yellow
    $available | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

function Invoke-Chat {
    param([hashtable]$Body)
    $json = $Body | ConvertTo-Json -Depth 6
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Uri $endpoint -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 300
    $sw.Stop()
    return @{ Response = $response; Seconds = $sw.Elapsed.TotalSeconds }
}

Write-Host "Modelo: $Model" -ForegroundColor Cyan

# --- Generacion -------------------------------------------------------------
$rates = @()
for ($i = 1; $i -le $Runs; $i++) {
    $result = Invoke-Chat @{
        model       = $Model
        messages    = @(@{ role = "user"; content = "Escribe 3 frases sobre el ciclo del agua. Variante $i" })
        max_tokens  = 120
        temperature = 0.7
        stream      = $false
    }
    $tokens = $result.Response.usage.completion_tokens
    $rate = [math]::Round($tokens / $result.Seconds, 1)
    $rates += $rate
    Write-Host ("  Generacion {0}: {1} tok en {2:N2} s = {3} tok/s" -f $i, $tokens, $result.Seconds, $rate)
}
$avgGen = [math]::Round(($rates | Measure-Object -Average).Average, 1)

# --- Prefill ----------------------------------------------------------------
$filler = ("La fotosintesis convierte la luz solar en energia quimica almacenada en glucosa y libera oxigeno. " * 90)
$prompt = "Responde solo OK. Nonce: $([guid]::NewGuid()). Texto: $filler"
$result = Invoke-Chat @{
    model       = $Model
    messages    = @(@{ role = "user"; content = $prompt })
    max_tokens  = 1
    temperature = 0.1
    stream      = $false
}
$promptTokens = $result.Response.usage.prompt_tokens
$prefill = [math]::Round($promptTokens / $result.Seconds, 1)
Write-Host ("  Prefill: {0} tok en {1:N2} s = {2} tok/s" -f $promptTokens, $result.Seconds, $prefill)

# --- VRAM -------------------------------------------------------------------
try {
    $vram = (Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop).CounterSamples |
        Where-Object { $_.CookedValue -gt 100MB } |
        Sort-Object CookedValue -Descending |
        Select-Object -First 1
    if ($vram) { Write-Host ("  VRAM dedicada: {0:N2} GB" -f ($vram.CookedValue / 1GB)) }
}
catch {
    Write-Host "  VRAM: no disponible en este sistema"
}

Write-Host ""
Write-Host "Resumen -> generacion: $avgGen tok/s | prefill: $prefill tok/s" -ForegroundColor Green
