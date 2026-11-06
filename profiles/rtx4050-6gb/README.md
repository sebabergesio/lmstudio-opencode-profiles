# Perfil: RTX 4050 Laptop 6 GB (CUDA)

Configuración de **Qwen 3.5 4B** pensada para una notebook con:

- **GPU**: NVIDIA RTX 4050 Laptop, **6 GB GDDR6** (96 bits, ~192 GB/s)
- **CPU**: AMD Ryzen 7 7735HS (8 núcleos / 16 hilos, Zen3+)
- **RAM**: 16 GB DDR5 (un solo módulo → **canal simple**, ~38 GB/s)
- **Pantalla**: 15.6" QHD 2560×1440 165 Hz
- **SO**: FreeDOS de fábrica

> Los valores de VRAM y velocidad de este documento son **cálculos/estimaciones**, no
> mediciones: este perfil no se ha probado en ese equipo. El perfil de 8 GB sí está medido.

## Diferencias con el perfil RX 6600 8 GB

| Ajuste | RX 6600 8 GB (medido) | Este perfil (estimado) | Motivo |
|---|---|---|---|
| Runtime | Vulkan | **CUDA** | En NVIDIA, CUDA rinde más y consume menos VRAM que Vulkan |
| Contexto | 20 480 | **16 384** | 6 GB no dan para 20k con visión activa |
| Flash Attention | off | **on** | Con 6 GB hay que ahorrar VRAM; FA on permite KV q8 |
| KV cache | f16 | **q8_0** | Ahorra ~50 % de KV; con FA on no pierde velocidad |
| Batch eval / físico | 1024 / 1024 | **512 / 512** | Menos buffers de cómputo reservados |
| Mantener en RAM | sí | **no** | Libera VRAM al cerrar el modelo |
| Sesiones paralelas | 1 | 1 | Con 6 GB no hay margen para más |

**Por qué no copiar el perfil de 8 GB tal cual**: en la RX 6600, FA off + KV f16 da el
mejor prefill (890 vs 627 tok/s), pero cuesta 1,3 GB más de VRAM. En 6 GB ese margen no
existe, así que se prioriza que quepa: FA on + q8 y batch 512.

Si en tu unidad sobra VRAM (por ejemplo, sin visión y con 12k de contexto), prueba
FA off + f16 y mide: en la RX 6600 ganó 42 % de prefill. No lo des por hecho en otra GPU.

## Presupuesto de VRAM estimado

| Componente | VRAM |
|---|---|
| Pesos Q4_K_M | 2,52 GB |
| `mmproj` visión BF16 | 0,63 GB |
| KV cache 16k q8_0 (K+V) | ~0,9–1,1 GB |
| Buffers de cómputo (batch 512) | ~0,3–0,5 GB |
| **Total del modelo** | **~4,4–4,8 GB** |
| Escritorio de Windows en la dGPU | ~0,5–0,8 GB |
| **Total en uso** | **~4,9–5,6 de 6 GB** |

Va **justo**: si algo más consume GPU (navegador con aceleración por hardware, Teams,
OBS), el driver empieza a paginar a RAM y la velocidad se desploma.

## Instalación en la notebook

1. Instala Windows 11 y los drivers (NVIDIA + chipset AMD). FreeDOS no trae nada.
2. Instala LM Studio y descarga el modelo:

```powershell
lms get "qwen/qwen3.5-4b@q4_k_m"
```

3. En LM Studio, selecciona el runtime **CUDA** (`llama.cpp-win-x86_64-nvidia-cuda`), no Vulkan.
4. Instala el perfil desde el repo:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Profile rtx4050-6gb
```

   O copia los archivos a mano:

```powershell
$repo = "C:\ruta\al\repo"
$lm   = "$env:USERPROFILE\.lmstudio"
$oc   = "$env:USERPROFILE\.config\opencode"

New-Item -ItemType Directory -Force "$lm\apps\bionic\.internal\user-concrete-model-default-config\qwen" | Out-Null
Copy-Item "$repo\profiles\rtx4050-6gb\lmstudio\models\qwen3.5-4b.json" `
          "$lm\apps\bionic\.internal\user-concrete-model-default-config\qwen\qwen3.5-4b.json" -Force

New-Item -ItemType Directory -Force "$lm\config-presets" | Out-Null
Copy-Item "$repo\profiles\rtx4050-6gb\lmstudio\presets\*.preset.json" "$lm\config-presets\" -Force

New-Item -ItemType Directory -Force "$oc\instructions" | Out-Null
Copy-Item "$repo\opencode\instructions\local-models.md" "$oc\instructions\local-models.md" -Force
$content = (Get-Content "$repo\profiles\rtx4050-6gb\opencode\opencode.json" -Raw).
    Replace("__OPENCODE_DIR__", ($oc -replace '\\','/'))
[IO.File]::WriteAllText("$oc\opencode.json", $content, (New-Object Text.UTF8Encoding($false)))
```

5. Abre LM Studio, carga el modelo y confirma con `lms ps` que el contexto es **16384** y
   `parallel` es **1**. Si ves 81 664 y 4 sesiones, la config no se aplicó (BOM o auto-fit).

Los JSON deben guardarse **UTF-8 sin BOM**: con BOM, LM Studio ignora la config y hace auto-fit.

## Ajustes del sistema que sí importan en esta notebook

- **Modo MUX / dGPU**: en Armoury Crate pon la pantalla en modo **dGPU dedicada** (o "Ultimate"). En modo Optimus la pantalla la mueve la iGPU y hay copia extra por PCIe; para LLM conviene la dGPU directa.
- **Perfil de energía**: Armoury Crate en **Turbo** y el equipo **enchufado**. Con batería, la RTX 4050 baja a ~35–45 W y pierdes buena parte del rendimiento.
- **Panel NVIDIA**: "Modo de administración de energía" → *Prefer maximum performance* para `llama-server.exe` y LM Studio.
- **Resolución mientras usas el modelo**: bajar a 1920×1080 (o 120 Hz) libera unos cientos de MB de VRAM del framebuffer. Con QHD 165 Hz el escritorio consume más.
- **Aceleración por hardware del navegador**: desactívala si vas a tener el navegador abierto mientras generas texto.
- **RAM en canal simple**: tienes 1×16 GB y el slot 2 libre. Añadir otro módulo de 16 GB (mismo modelo, para dual channel) duplica el ancho de banda de la RAM. No mejora la velocidad cuando todo está en GPU, pero evita que la carga se arrastre si algo cae a CPU.

## Si no cabe en 6 GB

En este orden, de menos a más pérdida:

1. **Contexto 16 384 → 12 288** (edita `llm.load.contextLength`). Libera ~0,3 GB.
2. **Batch 512 → 256** (`evalBatchSize` y `physicalBatchSize`). Libera buffers; el prefill baja algo.
3. **Quitar visión**: no cargues el `mmproj` (o usa el modelo sin imagen). Libera **0,63 GB** y permite volver a 20k de contexto.
4. Cerrar apps que usen GPU y repetir.

Si LM Studio falla al cargar con "out of device memory", casi siempre es el punto 1 o el 3.

## Rendimiento esperado (estimación, sin medir)

La RTX 4050 Laptop tiene ~192 GB/s de ancho de banda. El modelo Q4_K_M ocupa ~2,5 GB:

- **Generación**: límite teórico ~76 tok/s; realista en portátil y con térmicas normales **~35–50 tok/s**.
- **Prefill**: varios cientos de tok/s con batch 512 (menos que el perfil de 8 GB, que usa 1024).
- **Referencia medida en la RX 6600** (224 GB/s): 51,8 tok/s de generación y 890 tok/s de prefill a 20k.

Para obtener cifras reales en esa notebook:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\benchmark.ps1 -Model "qwen/qwen3.5-4b"
powershell -ExecutionPolicy Bypass -File .\scripts\tool-test.ps1 -Model "qwen/qwen3.5-4b"
```

Si sale muy por debajo de 30 tok/s, revisa en este orden: runtime CUDA activo, 100 % de
capas en GPU, perfil Turbo enchufado y VRAM libre antes de cargar.

## Cuantización

Mantén **Q4_K_M**. En 6 GB, Q6_K (3,46 GB) obliga a bajar el contexto a ~8k y no compensa
en un modelo de 4B.

## Un solo modelo

Este perfil usa **solo Qwen 3.5 4B**, igual que el de 8 GB. Los agentes `general`, `coder`
y `title` apuntan al mismo modelo: no hay cambios de modelo ni recargas de 4–8 s.

## Archivos de este perfil

```text
lmstudio/models/qwen3.5-4b.json                       Config de carga + inferencia (16k, FA on, q8)
lmstudio/presets/qwen35-4b-general.preset.json        General (temp 0.3, top_p 0.9)
lmstudio/presets/qwen35-4b-codigo.preset.json         Código (temp 0.2, top_p 0.95)
opencode/opencode.json                                OpenCode con contexto 16k
```
