#Requires -Version 5.1
<#
    Prueba de humo de tool-calling contra el servidor local de LM Studio.
    Comprueba si el modelo devuelve tool_calls validas (nombre + argumentos JSON)
    y si evita llamar herramientas cuando no hace falta.

    Uso: powershell -ExecutionPolicy Bypass -File .\scripts\tool-test.ps1
         powershell -ExecutionPolicy Bypass -File .\scripts\tool-test.ps1 -Model "granite-4.1-3b"
#>
[CmdletBinding()]
param(
    [string]$Model = "qwen/qwen3.5-4b",
    [string]$BaseUrl = "http://127.0.0.1:1234"
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

$tools = @(
    @{
        type = "function"
        function = @{
            name        = "get_weather"
            description = "Devuelve el clima actual de una ciudad."
            parameters  = @{
                type       = "object"
                properties = @{
                    city = @{ type = "string"; description = "Nombre de la ciudad" }
                }
                required   = @("city")
            }
        }
    },
    @{
        type = "function"
        function = @{
            name        = "write_file"
            description = "Crea un archivo de texto con el contenido indicado."
            parameters  = @{
                type       = "object"
                properties = @{
                    name    = @{ type = "string"; description = "Nombre del archivo, con extension" }
                    content = @{ type = "string"; description = "Contenido a escribir" }
                }
                required   = @("name", "content")
            }
        }
    }
)

function Invoke-Test {
    param(
        [string]$Prompt,
        [string]$ExpectTool,
        [hashtable]$ExpectArgs,
        [switch]$ExpectNoTool
    )

    $body = @{
        model       = $Model
        messages    = @(@{ role = "user"; content = $Prompt })
        tools       = $tools
        tool_choice = "auto"
        temperature = 0.2
        max_tokens  = 300
        stream      = $false
    }

    $json = $body | ConvertTo-Json -Depth 10
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod -Uri $endpoint -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 300
    $sw.Stop()

    $msg = $response.choices[0].message
    $calls = @($msg.tool_calls)

    $result = [pscustomobject]@{
        Prompt    = $Prompt
        Seconds   = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        ToolCalls = $calls.Count
        Ok        = $false
        Detalle   = ""
    }

    if ($ExpectNoTool) {
        if ($calls.Count -eq 0) {
            $result.Ok = $true
            $result.Detalle = "no llamo herramientas (correcto)"
        }
        else {
            $result.Detalle = "llamo '$($calls[0].function.name)' sin necesidad"
        }
        return $result
    }

    if ($calls.Count -eq 0) {
        $texto = ($msg.content | Out-String).Trim()
        if ($texto.Length -gt 120) { $texto = $texto.Substring(0, 120) + "..." }
        $result.Detalle = "sin tool_calls; respondio texto: $texto"
        return $result
    }

    $call = $calls[0].function
    if ($call.name -ne $ExpectTool) {
        $result.Detalle = "herramienta incorrecta: $($call.name) (esperaba $ExpectTool)"
        return $result
    }

    try {
        $args = $call.arguments | ConvertFrom-Json
    }
    catch {
        $result.Detalle = "argumentos no son JSON valido: $($call.arguments)"
        return $result
    }

    $fallos = @()
    foreach ($kv in $ExpectArgs.GetEnumerator()) {
        $valor = $args.($kv.Key)
        if ($null -eq $valor) {
            $fallos += "falta '$($kv.Key)'"
            continue
        }
        if ($valor -notmatch $kv.Value) {
            $fallos += "'$($kv.Key)'=$valor no coincide con /$($kv.Value)/"
        }
    }

    if ($fallos.Count -eq 0) {
        $result.Ok = $true
        $result.Detalle = "$($call.name) $($call.arguments)"
    }
    else {
        $result.Detalle = ($fallos -join "; ") + " -> $($call.arguments)"
    }
    return $result
}

Write-Host "Modelo: $Model" -ForegroundColor Cyan
Write-Host ""

$casos = @(
    Invoke-Test -Prompt "Que tiempo hace en Santiago de Chile? Usa la herramienta del clima." `
        -ExpectTool "get_weather" -ExpectArgs @{ city = "(?i)santiago" }
    Invoke-Test -Prompt "Crea un archivo llamado notas.txt que contenga exactamente: hola mundo" `
        -ExpectTool "write_file" -ExpectArgs @{ name = "(?i)notas\.txt"; content = "(?i)hola mundo" }
    Invoke-Test -Prompt "Crea un archivo llamado config.json que contenga exactamente este JSON: {`"a`": 1, `"b`": true}" `
        -ExpectTool "write_file" -ExpectArgs @{ name = "(?i)config\.json"; content = "(?s).*a.*1.*" }
    Invoke-Test -Prompt "Responde solo con la palabra OK. No uses ninguna herramienta." `
        -ExpectNoTool
)

foreach ($c in $casos) {
    $estado = if ($c.Ok) { "PASS" } else { "FAIL" }
    $color = if ($c.Ok) { "Green" } else { "Red" }
    Write-Host ("  [{0}] {1:N2} s - {2}" -f $estado, $c.Seconds, $c.Detalle) -ForegroundColor $color
}

$total = $casos.Count
$ok = @($casos | Where-Object { $_.Ok }).Count
Write-Host ""
Write-Host "Resumen -> tool-calling: $ok/$total correctos" -ForegroundColor Cyan

if ($ok -lt $total) { exit 1 }
