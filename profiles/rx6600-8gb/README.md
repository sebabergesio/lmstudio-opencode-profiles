# Perfil: AMD RX 6600 8 GB (Vulkan)

Configuración de **Qwen 3.5 4B** medida en este equipo:

- **GPU**: AMD Radeon RX 6600, **8 GB GDDR6** (128 bits, 224 GB/s)
- **CPU**: AMD Ryzen 5 PRO 4650G (6 núcleos / 12 hilos)
- **RAM**: 32 GB
- **SO**: Windows 11
- **Runtime**: `llama.cpp-win-x86_64-vulkan-avx2@2.70.0`

> Todo lo que aparece aquí está **medido** en esta máquina el 2026-11-06, no estimado.

## Rendimiento medido

| Contexto | Carga | Generación | Prefill (~2,4k) | VRAM | Tools |
|---|---|---|---|---|---|
| 20 480 | FA off, KV f16, offload 100 % | 51,8 tok/s | **890 tok/s** | 6,42 GB | 4/4 |

La generación varía ±10 % entre pasadas; el prefill es estable (±1 %). El techo teórico
de generación es `224 GB/s ÷ 2,52 GB ≈ 89 tok/s`, así que el 58 % de eficiencia es lo
normal en Vulkan. No hay margen real de velocidad: el cuello es el ancho de banda.

## Por qué esta configuración

| Ajuste | Valor | Motivo |
|---|---|---|
| `offloadRatio` | **1,0** | Con 0,8 la generación cae a 26 tok/s (la mitad). Es el ajuste que más importa |
| Contexto | **20 480** | 16k y 20k generan igual; solo cambia la VRAM. 24k sube a ~7,2 GB y deja muy poco margen |
| Flash Attention | **off** | Sube el prefill de 627 a 890 tok/s (+42 %) sin tocar la generación |
| KV cache | **f16** | Con FA off hay que declararlo explícito. Cuesta 1,3 GB más que q8, asumible con un solo modelo |
| Batch eval/físico | **1024** | 2048 no mejora el prefill; 1024 es el óptimo |
| Sesiones paralelas | **1** | Con 8 GB no hay VRAM para dos sesiones |
| KV en GPU | **sí** | Evita re-subir el KV entre peticiones |
| Thinking | **off** | El modelo no soporta razonamiento nativo; activarlo solo gasta tokens |
| Overflow | `truncateMiddle` | Conserva el principio y el final del contexto |

## Presupuesto de VRAM medido

| Componente | VRAM |
|---|---|
| Pesos Q4_K_M (2,52 GB) + `mmproj` BF16 (0,63 GB) | 3,38 GB |
| KV cache 20k f16 + buffers de cómputo | ~3,04 GB |
| **Total del modelo** | **6,42 GB** |
| Margen libre | **~1,5 GB** |

Con 1,5 GB libres el escritorio va bien. Si abres un navegador con aceleración por
hardware o un juego, el driver puede empezar a paginar a RAM.

## Ajustes del sistema

- **Runtime Vulkan**, no CPU: `lms runtime ls` debe mostrar `vulkan-avx2` como `SELECTED`.
  ROCm no soporta oficialmente `gfx1032` (RX 6600), así que Vulkan es la vía real en Windows.
- **Plan de energía** de alto rendimiento (`install.ps1` lo activa).
- **Preferencia de GPU** para `llama-server.exe` y `Bionic.exe` (`install.ps1` la escribe en el registro).
- **Un solo modelo**: LM Studio descarga el anterior al cambiar; con 8 GB no conviven dos.
- **SAM / Resize BAR** (BIOS): con offload al 100 % apenas influye; no lo persigas.

## Si no cabe o va lento

En este orden:

1. **Contexto 20 480 → 16 384**. Baja a ~5,2 GB sin perder tok/s (el contexto no afecta a la velocidad).
2. **Quitar visión**: no cargues el `mmproj`. Libera 0,63 GB.
3. Cierra apps que usen GPU y repite.
4. Comprueba que el offload sigue en 1,0: si LM Studio hizo auto-fit, verás 81 664 de contexto y 4 sesiones.

## Instalación

```powershell
$repo = "C:\ruta\al\repo"
$lm   = "$env:USERPROFILE\.lmstudio"
$oc   = "$env:USERPROFILE\.config\opencode"

lms get "qwen/qwen3.5-4b@q4_k_m"

New-Item -ItemType Directory -Force "$lm\apps\bionic\.internal\user-concrete-model-default-config\qwen" | Out-Null
Copy-Item "$repo\profiles\rx6600-8gb\lmstudio\models\qwen3.5-4b.json" `
          "$lm\apps\bionic\.internal\user-concrete-model-default-config\qwen\qwen3.5-4b.json" -Force

New-Item -ItemType Directory -Force "$lm\config-presets" | Out-Null
Copy-Item "$repo\profiles\rx6600-8gb\lmstudio\presets\*.preset.json" "$lm\config-presets\" -Force

New-Item -ItemType Directory -Force "$oc\instructions" | Out-Null
Copy-Item "$repo\opencode\instructions\local-models.md" "$oc\instructions\local-models.md" -Force
$content = (Get-Content "$repo\profiles\rx6600-8gb\opencode\opencode.json" -Raw).
    Replace("__OPENCODE_DIR__", ($oc -replace '\\','/'))
[IO.File]::WriteAllText("$oc\opencode.json", $content, (New-Object Text.UTF8Encoding($false)))
```

O desde el repo completo: `powershell -ExecutionPolicy Bypass -File .\install.ps1 -Profile rx6600-8gb`.

Los JSON deben guardarse **UTF-8 sin BOM**: con BOM, LM Studio ignora la config y hace auto-fit.

## Verificar

```powershell
lms ps                                  # contexto 20480, parallel 1
powershell -ExecutionPolicy Bypass -File .\scripts\benchmark.ps1 -Model "qwen/qwen3.5-4b"
powershell -ExecutionPolicy Bypass -File .\scripts\tool-test.ps1 -Model "qwen/qwen3.5-4b"
```

Referencia: 51,8 tok/s de generación, 890 tok/s de prefill, 6,42 GB de VRAM y 4/4 en tool-calling.

## Archivos de este perfil

```text
lmstudio/models/qwen3.5-4b.json                       Config de carga + inferencia (20k, FA off, f16)
lmstudio/presets/qwen35-4b-general-rapido.preset.json General (temp 0.3, top_p 0.9)
lmstudio/presets/qwen35-4b-codigo.preset.json         Código (temp 0.2, top_p 0.95)
opencode/opencode.json                                OpenCode con contexto 20k y salida 8k
```

Son copias de la configuración raíz del repo. Si cambias una, cambia la otra (o ejecuta
`scripts/lmstudio-configs.ps1` para regenerarlas).
