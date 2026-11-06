# LM Studio + OpenCode: setup local optimizado

Configuración reproducible de LM Studio y OpenCode para **un modelo local**, optimizada para **velocidad** y **calidad** en una GPU de 8 GB (probada en AMD RX 6600 + Vulkan).

- **Qwen 3.5 4B** (Q4_K_M): orquestador general, código con herramientas y visión.

> El 3B y el 7B se retiraron el 2026-11-06: no aportaban nada que el 4B no hiciera ya, y cada cambio de modelo costaba 4–8 s. Sus números siguen en el histórico de rendimiento.

## El modelo

| Rol | Modelo | Contexto | Carga | Por qué |
|---|---|---|---|---|
| Todo | Qwen 3.5 4B | 20 480 | FA off, KV f16, offload 100 % | Mejor prefill y tool-calling 4/4 |

Regla de uso: **un solo modelo, siempre cargado**. No hay cambios de modelo, así que
el primer token llega en ~2 s con un prompt de 2k tokens y el agente `title` usa el mismo 4B.

## Qué incluye

| Área | Contenido |
|---|---|
| LM Studio | 4B: 20k, FA off, KV f16, offload 100 %, batch 1024, thinking off, `truncateMiddle` |
| Presets | General rápido y Código preciso (4B) |
| System prompts | Incluidos en la config del modelo y en los presets |
| OpenCode | Provider `lmstudio`, 4B con 20k/visión/herramientas, títulos locales y compactación |
| Windows | Plan de energía alto rendimiento y preferencia de GPU para LM Studio |

## Requisitos

- **LM Studio** (Bionic) con el runtime **Vulkan** de llama.cpp (probado con `llama.cpp-win-x86_64-vulkan-avx2@2.70.0`).
- **OpenCode V2**.
- Modelos descargados:

```powershell
lms get "qwen/qwen3.5-4b@q4_k_m"
```

- El servidor local de LM Studio en el puerto **1234** (sin API key).

## Entorno verificado (2026-11-06)

| Componente | Valor |
|---|---|
| GPU | AMD Radeon RX 6600 8 GB (Vulkan) |
| CPU | AMD Ryzen 5 PRO 4650G (6C/12T) |
| RAM | 32 GB |
| Runtime | `llama.cpp-win-x86_64-vulkan-avx2@2.70.0` |
| Modelos | `qwen/qwen3.5-4b` (Q4_K_M + mmproj de visión) |
| LM Studio | Bionic instalado en `G:\LM Studio\Bionic`; configs en `%USERPROFILE%\.lmstudio` |
| OpenCode | V2, provider `lmstudio` → `http://127.0.0.1:1234/v1` |

Nota: LM Studio puede estar instalado fuera de `%USERPROFILE%`. El instalador funciona igual porque las configs viven en `%USERPROFILE%\.lmstudio` y `Bionic.exe` se detecta desde el proceso en ejecución (si está cerrado, omite la preferencia de GPU).

## Instalación

1. Cierra LM Studio por completo.
2. Clona el repo y ejecuta el instalador:

```powershell
git clone https://github.com/sebabergesio/lmstudio-opencode-profiles.git
cd lmstudio-opencode-profiles
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Para otra GPU, elige el perfil:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Profile rtx4050-6gb
```

3. Vuelve a abrir LM Studio.

El instalador:

- Hace copia de seguridad de lo que ya exista en `%USERPROFILE%\lmstudio-opencode-backup-<fecha>\`.
- Copia las configs por modelo a `%USERPROFILE%\.lmstudio\apps\bionic\.internal\user-concrete-model-default-config\`.
- Copia los presets a `%USERPROFILE%\.lmstudio\config-presets\`.
- Instala la config de OpenCode en `%USERPROFILE%\.config\opencode\`.
- Activa el plan de energía de alto rendimiento y la preferencia de GPU (opcional, ver flags).

### Flags

| Flag | Efecto |
|---|---|
| `-Profile rx6600-8gb` | Perfil por defecto: RX 6600 8 GB, Vulkan, 20k |
| `-Profile rtx4050-6gb` | Perfil RTX 4050 Laptop 6 GB, CUDA, 16k |
| `-DryRun` | Muestra lo que haría sin escribir nada |
| `-SkipPowerPlan` | No cambia el plan de energía |
| `-SkipGpuPreference` | No toca el registro de preferencia de GPU |
| `-Home <ruta>` | Instala en otra ruta de usuario (pruebas) |

## Uso en OpenCode

- `Shift+Tab` cambia de agente; `<leader>a` lista agentes; `<leader>m` lista modelos.
- Agentes incluidos: `general` (orquestador), `coder` (subagente con herramientas) y `title` (títulos).
- O directo desde la terminal:

```powershell
opencode run --agent general "explica este error"
opencode run --agent coder "refactoriza este modulo"
```

También puedes elegir `lmstudio/qwen/qwen3.5-4b` como modelo de cualquier agente.
No quedan más modelos locales: el 3B y el 7B se retiraron el 2026-11-06 y sus
mediciones se conservan como histórico.

## Rendimiento medido

RX 6600 8 GB, 1 sesión, batch 1024, runtime Vulkan 2.70.0 (medido el 2026-11-06):

| Modelo | Contexto | Carga | Generación | Prefill (~2,4k) | VRAM | Tools |
|---|---|---|---|---|---|---|
| Qwen 3.5 4B | 20 480 | FA off, KV f16, offload 100 % | 51,8 tok/s | **890 tok/s** | 6,42 GB | 4/4 |

La generación varía ±10 % entre pasadas y con la temperatura de la GPU; el prefill es estable (±1 %).

La regresión que se corrigió en el 4B:

| Configuración | Generación | Prefill | VRAM |
|---|---|---|---|
| offload 0,8 + 16k (antes) | 26,2 tok/s | 573 tok/s | 4,47 GB |
| **offload 1,0 + 20k (ahora)** | **51,5 tok/s** | **891 tok/s** | 6,41 GB |

Conclusiones:

- **El offload 0,8 era el problema principal**: 20 % de las capas en CPU hunden la generación a la mitad. Con 100 % en GPU el 4B pasa de 26 a 51,5 tok/s.
- **FA off + KV f16 es lo mejor para el 4B**: sube el prefill de 627 a 890 tok/s (+42 %) sin tocar la generación. El precio son 1,3 GB extra de VRAM (6,42 vs 5,14 GB), asumibles porque solo hay un modelo cargado.
- **El contexto no afecta la velocidad**: 16k y 20k dan la misma generación; solo cambia la VRAM.
- **Batch 2048 no mejora** el prefill; 1024 sigue siendo el óptimo.
- **MTP no está soportado** por estos GGUF (`--speculative-draft-mtp` falla al cargar).
- *Histórico:* el 7B no servía como agente (devolvía el JSON como texto, 1/4 en `tool-test.ps1`) y el 3B, aunque era el más rápido (81 tok/s), obligaba a cambiar de modelo. Ambos se retiraron.

### Matriz Flash Attention × KV (2026-11-06)

Se midieron los tres modelos antes de retirar el 3B y el 7B: mismo benchmark y misma sesión, 3 generaciones de 120 tokens y un prefill de ~2,4k tokens.

| Modelo | FA | KV | Generación | Prefill | VRAM |
|---|---|---|---|---|---|
| 4B 20k | off | f16 | 51,8 tok/s | **890 tok/s** | 6,42 GB |
| 4B 20k | on | q8 | 51,8 tok/s | 627 tok/s | 5,14 GB |
| 7B 16k | on | q8 | **42,8 tok/s** | **237 tok/s** | 6,17 GB |
| 7B 16k | off | f16 | 39,0 tok/s | 175 tok/s | 5,97 GB |
| 3B 8k | on | q8 | 81,3 tok/s | 378 tok/s | 3,15 GB |
| 3B 8k | off | f16 | 81,3 tok/s | **1248 tok/s** | 3,48 GB |

- **La generación no la mueve FA en ningún modelo**: está limitada por ancho de banda de memoria (224 GB/s en la RX 6600).
- **FA off mueve el prefill, y de forma dispar**: 1,4× en el 4B, 3,3× en el 3B y 0,74× en el 7B. No hay regla general; hay que medir por modelo. En el 4B compensa, en el 7B era contraproducente.
- **En el 3B el coste era 0,33 GB** de VRAM; a 16k serían 5,30 GB sin ganar prefill.
- **Con FA off, declara el KV como f16**: no hemos medido que q8_0 ahorre VRAM en ese modo, y el valor por defecto puede no aplicarse.
- Reproducible: el prefill del 3B dio 1248, 1250 y 1250 tok/s en tres pasadas.

### Histórico (2026-11-03)

| Configuración | Generación | Prefill (~2,5k tokens) | VRAM |
|---|---|---|---|
| 20k, Flash Attention **off** | 46–48 tok/s | ~916 tok/s | 6,78 GB |
| 32k, Flash Attention on, KV q8_0 | 47–49 tok/s | ~629 tok/s | 5,84 GB |
| 24k, Flash Attention off | 46–47 tok/s | ~900 tok/s | 7,14 GB |
| 32k, Flash Attention off | 47–49 tok/s | ~912 tok/s | 7,68 GB |

- Flash Attention off sube el prefill ~45 % sin tocar la generación.
- KV f16 vs q8_0 con FA on: misma velocidad, q8_0 ahorra VRAM.
- Speculative decoding con Qwen 0.8B: 3× más lento → descartado.
- Runtime 2.65.1 era 22 % más lento en prefill que 2.67.0; usa siempre el runtime más reciente.

### Advertencia: BOM en los JSON

LM Studio **ignora** `user-concrete-model-default-config` si el JSON lleva BOM.
En ese caso carga con auto-fit (por ejemplo 81 664 de contexto y 4 sesiones),
dispara la VRAM y pierde la config. Los scripts escriben UTF-8 **sin BOM**;
si editas un JSON a mano, guarda sin BOM.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\benchmark.ps1
```

### Alternativas no-Qwen medidas (2026-11-03)

Misma máquina, 1 sesión, `--parallel 1`, sin visión. El tool-calling se mide con `scripts/tool-test.ps1` (4 casos: elegir herramienta, crear archivo, JSON escapado, no llamar herramientas sin necesidad). Los dos Granite se probaron y se desinstalaron: el setup sigue usando solo Qwen.

| Modelo | Contexto | Generación | Prefill (~2,4k) | VRAM | Tool-calling |
|---|---|---|---|---|---|
| **Qwen 3.5 4B** Q4_K_M (actual) | 20k | 47,6 tok/s | **920 tok/s** | 6,65 GB | 4/4 |
| **Granite 4.1 3B** Q4_K_M | 48k | **78 tok/s** | 742 tok/s | 7,00 GB | 4/4 |
| **Granite 4.1 8B** Q4_K_M | 64k | 33,5 tok/s | 161 tok/s | 7,11 GB | 4/4 |

Lectura de los resultados:

- **Granite 4.1 es híbrido** (atención + estado recurrente): el KV casi no crece, así que 64k ocupa prácticamente lo mismo que 8k. Eso permite contexto largo en 8 GB, al contrario de lo que pasa con Qwen.
- **El precio es el prefill**: 161 tok/s frente a 920 de Qwen (5,7× más lento). En un agente con prompts de 2-4k tokens cada turno se nota mucho más que la generación.
- **Granite 4.1 3B es el más rápido** (78 tok/s) y el que deja más margen: 32k ocupa 5,73 GB y 48k 7,00 GB.
- Los tres pasan el test de herramientas. El 3B responde en ~0,5 s y el 8B en ~1,3 s por el prefill.

Los modelos importados desde Hugging Face **no toman la config por modelo** de `user-concrete-model-default-config`; hay que pasar el contexto y las sesiones al cargar:

```powershell
lms load "granite-4.1-8b" --gpu max -c 65536 --parallel 1 -y
```

## Cuantizaciones (Q4_K_M vs Q6_K vs Q8_0)

El repo fija **Q4_K_M** (`lmstudio-community/Qwen3.5-4B-GGUF`). Alternativas del mismo repo:

| Variante | Tamaño | VRAM estimada (20k, FA off, con mmproj) | Cabe en 8 GB |
|---|---|---|---|
| **Q4_K_M** (recomendada) | 2,71 GB | ~6,8 GB | sí |
| Q6_K | 3,46 GB | ~7,5 GB | muy justo |
| Q8_0 | 4,48 GB | ~8,5 GB | no |

La generación está limitada por ancho de banda de memoria, así que subir de cuantización cuesta velocidad:

- Q6_K: ~10–15 % más lento que Q4_K_M (≈40–43 tok/s)
- Q8_0: ~25–30 % más lento y probablemente no quepa con 32k de contexto

Recomendación: quedarse en **Q4_K_M**. En un modelo de 4B la diferencia con Q6_K solo se nota en casos límite. Si necesitas más precisión, sube a Q6_K y baja el contexto antes que a Q8_0.

Para cambiar de cuantización: descarga la variante en LM Studio, actívala, y reaplica los ajustes de carga. En OpenCode no cambia nada (`modelKey` sigue siendo `lmstudio/qwen/qwen3.5-4b`).

## Perfiles

El repo trae la configuración base (8 GB AMD/Vulkan) en la raíz y un perfil autocontenido por GPU en `profiles/`. Instala con `-Profile`:

| Perfil | Hardware | Contexto | Runtime | Estado |
|---|---|---|---|---|
| `profiles/rx6600-8gb` | RX 6600 8 GB + Ryzen 5 PRO 4650G | 20 480 | Vulkan | **Medido** (51,8 tok/s, 890 prefill, 6,42 GB) |
| `profiles/rtx4050-6gb` | RTX 4050 Laptop 6 GB + Ryzen 7 7735HS | 16 384 | CUDA | Estimado (sin medir) |

Cada perfil incluye su propia config de modelo, presets, plantilla de OpenCode y un README con el presupuesto de VRAM y los ajustes del sistema. El de 8 GB usa FA off + KV f16 porque ahí gana 42 % de prefill; el de 6 GB usa FA on + KV q8 porque primero tiene que caber.

## Estructura

```text
lmstudio/models/                 Configs por modelo (load + inferencia)
lmstudio/presets/                Presets de LM Studio
opencode/opencode.json           Config global (placeholder __OPENCODE_DIR__)
opencode/instructions/           Reglas para los modelos locales
scripts/benchmark.ps1            Medición de generación y prefill
scripts/tool-test.ps1            Prueba de tool-calling (4 casos)
install.ps1 / uninstall.ps1
CHANGELOG.md                     Historial de cambios
profiles/rx6600-8gb/            Perfil para RX 6600 8 GB (Vulkan, 20k) — medido
profiles/rtx4050-6gb/            Perfil para RTX 4050 Laptop 6 GB (CUDA, 16k)
```

## Desinstalar

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

Restaura la última copia de seguridad y elimina los presets instalados. El plan de energía y la preferencia de GPU no se revierten automáticamente (`uninstall.ps1` imprime cómo hacerlo).

## Notas

- En 8 GB de VRAM el 4B ocupa ~6,4 GB con 20k; no cargues otro modelo a la vez.
- El 3B y el 7B se retiraron el 2026-11-06. Para recuperarlos: `lms get "qwen/qwen2.5-3b@q4_k_m"` o `lms get "qwen/qwen2.5-coder-7b@q4_k_m"` (sus configs ya no se instalan).
- **LFM3-VL 2B fue retirado** (2026-11-02): no se recomienda para uso general. Este repo ya no instala su config ni sus presets.
- Si LM Studio no está en `%USERPROFILE%\.lmstudio\apps\bionic`, el instalador avisa y copia igualmente las configs; ajusta la ruta a mano.
- Los JSON no contienen claves ni datos personales; el instalador resuelve las rutas de tu usuario.
