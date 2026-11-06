# Changelog

## 2026-11-06

- **Config definitiva del 4B aplicada y verificada**: 20 480 de contexto, FA off, KV f16, offload 1,0, batch 1024, parallel 1, temp 0,3/top_p 0,9. Salida de OpenCode 4096 → **8192** para reescrituras largas (.tex, documentos).
- **Perfiles por GPU en `profiles/`**: `rx6600-8gb` (Vulkan, 20k, **medido**: 51,8 tok/s, 890 prefill, 6,42 GB) y `rtx4050-6gb` (CUDA, 16k, FA on + q8, estimado sin medir). Cada uno autocontenido: config de modelo, presets, plantilla de OpenCode y README con presupuesto de VRAM.
- **`install.ps1 -Profile rx6600-8gb|rtx4050-6gb`**: instala el perfil elegido; por defecto `rx6600-8gb`.

- **Se retiran Qwen 2.5 3B y Qwen 2.5-Coder 7B: queda solo Qwen 3.5 4B**. El 7B no emite `tool_calls` (1/4), tiene el peor prefill de los tres (237 tok/s) y ocupa 6,2 GB sin poder actuar de agente; el 3B solo servía para lotes y cada cambio de modelo costaba 4-8 s.
- Borrados del disco (6,16 GB) y de las configs: `qwen2.5-3b.json` y `qwen2.5-coder-7b.json` en el repo y en `user-concrete-model-default-config`.
- `opencode.json`: solo el modelo 4B y los agentes `general`, `coder` y `title`; fuera el agente `fast`.
- `install.ps1`, `lmstudio-configs.ps1` y `lmstudio-role.ps1` reducidos a un modelo y dos roles.
- Para recuperarlos: `lms get "qwen/qwen2.5-3b@q4_k_m"` o `lms get "qwen/qwen2.5-coder-7b@q4_k_m"` (habría que volver a añadir su config).

- **3 modelos, un rol cada uno**: Qwen 3.5 4B (orquestador + coder), Qwen 2.5-Coder 7B (código sin tools) y Qwen 2.5 3B (lotes/títulos).
- **Corregido el offload 0,8 → 1,0**: era la causa de la caída a 26 tok/s. El 4B pasa a **51,5 tok/s** y **891 tok/s** de prefill con 20k, FA off y KV f16 (6,41 GB VRAM).
- **Contexto 4B: 16 384 → 20 480**; OpenCode actualizado al mismo límite (`output` 4096).
- **El 7B deja de ser el agente `coder`**: `tool-test.ps1` da **1/4** (devuelve el JSON como texto, no `tool_calls`). El `coder` usa el 4B, que da 4/4.
- **El 3B pasa a FA off + KV f16** (sigue en 8k): 81,3 tok/s y **1248 tok/s** de prefill (antes 374), 3,48 GB, 4/4 en tool-calling. Matriz FA × KV medida en los tres modelos: gana en el 4B (627→890) y sobre todo en el 3B (3,3×), pero **pierde en el 7B** (237→175), que se queda con FA on.
- **El agente `title` usa el 4B**: evita cargar el 3B al inicio y el cambio de modelo.
- **`fast` solo para lotes**: el orquestador ya no delega operaciones cortas al 3B (cada cambio de modelo cuesta 4-8 s).
- **Temperaturas**: 4B 0,3/0,9; 7B 0,2/0,95; 3B 0,3/0,9. `coder` a 0,2 vía `request.body`.
- **BOM**: LM Studio ignora la config del modelo si el JSON lleva BOM (carga auto-fit con 81 664 de contexto y 4 sesiones). `install.ps1` y `lmstudio-configs.ps1` escriben UTF-8 sin BOM.
- **`lms load` no aplica la config por modelo**: el script `lmstudio-role.ps1` ahora carga por JIT (petición a `/v1/chat/completions`) y verifica contexto/parallel con `lms ps`.
- **Preferencia de GPU** actualizada al runtime Vulkan 2.70.0.
- **MTP**: `--speculative-draft-mtp` sigue fallando con estos GGUF; descartado.
- Limpieza de configs obsoletas (`qwen3.5-0.8b`, `qwen2.5-coder-7b-instruct`).

## 2026-11-03

- **Alternativas no-Qwen medidas**: Granite 4.1 3B (78 tok/s, prefill 742, 48k, 7,00 GB) y Granite 4.1 8B (33,5 tok/s, prefill 161, 64k, 7,11 GB), ambos 4/4 en tool-calling. Qwen 4B sigue ganando en prefill (920 tok/s). Nuevo `scripts/tool-test.ps1`.
- Granite 4.1 es híbrido (atención + estado recurrente): el KV casi no crece y el contexto largo sale casi gratis; el coste es un prefill 5,7× más lento en Vulkan.
- Los modelos importados desde HF no leen la config por modelo: hay que cargar con `-c <contexto> --parallel 1`.
- **LFM3-VL 2B retirado del repo**: se eliminan su config (`lmstudio/models/lfm3-vl-2b.json`), sus 2 presets, el agente `local-lfm3` y sus referencias en `install.ps1`, `uninstall.ps1`, `scripts/benchmark.ps1` y `README.md`.
- El agente `title` de OpenCode pasa a usar `lmstudio/qwen/qwen3.5-4b`.
- README: nueva sección de cuantizaciones (Q4_K_M / Q6_K / Q8_0) con estimación de VRAM y velocidad.
- README: nueva sección **Entorno verificado** con el hardware, runtime y rutas reales.
- Verificado: `install.ps1 -DryRun` valida 5 archivos y no copia nada de LFM3.
- **Limpieza del remoto**: eliminada la rama `master` (commit accidental ajeno al proyecto). El repo queda solo con `main`.
- Nuevo perfil **`profiles/rtx4050-6gb`** para RTX 4050 Laptop 6 GB: contexto 16k, CUDA, KV q8_0, batch 512, presets y plantilla de OpenCode con 16k. Incluye README con presupuesto de VRAM y ajustes de la notebook. Sin medir en ese equipo.
- **Qwen 4B: Flash Attention desactivado** → prefill de 629 a 916 tok/s (+46 %) sin pérdida de generación. El KV pasa a f16, así que el contexto baja de 32k a 20k para mantener margen de VRAM (6,78 GB usados). Verificado también que el runtime 2.65.1 es 22 % más lento en prefill que 2.67.0.

## 2026-11-02

- Versión inicial: configs optimizadas de carga e inferencia para Qwen 3.5 4B y LFM3-VL 2B (contexto 32k, batch 1024, KV q8_0, Flash Attention, GPU offload 100 %, thinking desactivado).
- Presets de LM Studio y system prompts.
- Config de OpenCode: provider `lmstudio`, agentes `local-qwen` / `local-lfm3`, títulos locales y compactación al 10 %.
- `install.ps1`, `uninstall.ps1` y `scripts/benchmark.ps1`.
- Plan de energía de alto rendimiento y preferencia de GPU en Windows.
