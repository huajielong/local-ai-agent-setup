# Performance Tuning

Goal: get the best generation speed and first-token latency for Claude Code on **this** machine, without overcommitting VRAM/RAM. Tune in this order and stop when the bottleneck is clear.

## 0. Measure first

- Baseline generation with at least 250 output tokens; measure prompt processing separately with a long prompt (~3K and, if possible, ~20K tokens).
- Run at least 3 times; report the median/sustained range. A 128-token, highly predictable prompt can be a best-case peak.
- Record: model/quant, context, KV type, backend flags, GPU clocks/power/P-state/utilization, CPU load/frequency, RAM, and background apps.
- For llama.cpp, read `timings` (`prompt_per_second`, `predicted_per_second`, draft acceptance). For Ollama, use `--verbose` eval counts.
- Do not compare different prompts, models, or quantizations as if they were the same benchmark.

## 1. OS / vendor power mode (often the biggest lever on laptops)

**Windows**
- Use AC power; set the Windows power plan/overlay to **Best performance**.
- Check the vendor Control Center: **Performance / Entertainment / Quiet** (Clevo/Colorful Fn+3; Lenovo Legion, ASUS Armoury Crate, MSI Center, etc. have equivalent modes). Quiet can cut throughput by 2–4×.
- NVIDIA Control Panel → Manage 3D settings → Power management mode → **Prefer maximum performance**. Check MUX/dGPU mode; disable Whisper Mode/Battery Boost.
- Close background GPU apps: ChatGPT/Codex desktop, NVIDIA Broadcast/Overlay, OBS, GPU-accelerated browsers, TTS.
- Check `nvidia-smi --query-gpu=power.draw,clocks.sm,utilization.gpu,pstate`. Low utilization at low clocks usually means the CPU/offload path is the bottleneck, not a GPU power cap — but a vendor Quiet mode caps both CPU and GPU.

**Linux**
- `powerprofilesctl set performance` (power-profiles-daemon), or `tuned-adm profile throughput-performance`.
- CPU governor: `cpupower frequency-set -g performance` (or `schedutil` if it performs better).
- NVIDIA: `nvidia-smi -pm 1`; inspect `nvidia-smi -q -d PERFORMANCE/POWER`. `-lgc`/`-pl` only if supported; always revert clocks with `-rgc` after benchmarking.
- AMD: `rocm-smi`, `amdctl`, `radeontop`; verify ROCm support for the GPU.
- Close compositor effects and background GPU jobs; check `nvidia-smi dmon`, `sensors`, `dmesg` for throttling.
- Laptop MUX/hybrid mode: use dGPU-only mode if available.

**macOS**
- Disable Low Power Mode; check `pmset -g` and `powermetrics` for thermal/power pressure.
- Close GPU-heavy apps; use MLX/Metal; watch unified-memory pressure. There are no NVIDIA-style clock locks.

**CPU-only**
- Small models only; tune threads; expect chat/translation/Q&A, not Claude-Code-class agency.

## 2. Backend and offload

- **llama.cpp**: prefer full GPU when the model fits. For MoE on tight VRAM, use `--n-cpu-moe` so attention/shared weights stay on GPU and experts live in RAM. Use `-fa on`, `-ctk/-ctv q8_0`, 32K context for Claude Code, `--parallel 1` for a single user. Enable MTP/draft only when the model supports it and measure acceptance.
- **Ollama**: set context via `OLLAMA_CONTEXT_LENGTH`, enable flash attention/KV quantization; some versions lack MoE expert offload, so large MoE models are usually faster in llama.cpp.
- **LM Studio**: GUI path; check bundled llama.cpp version, GPU layers, and MoE offload.
- **vLLM / SGLang**: team/multi-GPU path; use `--tensor-parallel-size`, `--gpu-memory-utilization`, and max model length. Put LiteLLM in front for Anthropic-compatible `/v1/messages` and per-user keys; measure concurrent throughput, not single-stream speed.
- **MLX**: Apple Silicon; unified memory; use MLX quantized models; no CPU expert offload.

## 3. CPU threads and affinity

- Detect topology: Windows `Win32_Processor` plus P/E-core info; Linux `lscpu -e`, `lstopo`, `numactl`; macOS `sysctl hw.perflevel*`.
- Pin llama-server to P-cores (or a CCD/CCX on AMD) and tune `-t`. On an 8-P-core CPU, 8 threads plus affinity can beat 16 threads that spill onto E-cores. Benchmark 4/8/12/16; do not copy values across machines.
- On multi-socket/NUMA systems, keep the model and threads on the same NUMA node where possible.

## 4. Model, quant, context

- Q4_K_M is the usual sweet spot; Q2/IQ2 hurts tool calling and long-context reliability; Q8 is rarely worth the size/speed cost.
- Use 32K context for Claude Code (system prompt + tools ~20K tokens); translation can stay at 2K. q8_0 KV cache saves VRAM.
- Dense models are simpler and often higher quality per parameter; MoE models are faster when partially offloaded. Pick for the use case, not parameter count.
- Verify tool calling: the model must advertise `tools` and pass a simple tool-call test; translation-only/embedding models are not Claude-Code models.
- Prompt processing matters as much as generation: a 20K system prompt at 60 tok/s prompt processing is a 5-minute wait. Prefer high prompt throughput and MTP/prefix caching where supported.

## 5. Validate

- End-to-end Claude Code: `/status` shows the local base URL; one normal prompt; one small-file read/tool call; normal `claude` still uses its original provider.
- Measure 3 runs; report sustained generation and prompt speed, VRAM/RAM, and stop/restart behavior.
- If results are lower than expected, revisit step 1 (vendor/OS power), step 2 (offload/backend), then step 3 (CPU threads/affinity).

## 6. Common traps

- Vendor Quiet/Entertainment mode; battery power; MUX/hybrid mode; background GPU apps.
- `nvidia-smi -lgc`/`-pl` is not a substitute for the vendor performance mode, and many laptops do not support it.
- CPU-bound MoE looks like “GPU idle” (low power/utilization); check CPU load and memory bandwidth.
- Thermal throttling and laptop power limits; clean fans, raise the laptop, use the vendor Performance mode.
- Wrong context/KV/quant; 4K context fails for Claude Code.
- Stale terminal PATH, LF-only Windows `.bat`/`.cmd`, settings `env` precedence, model display IDs.
- On 12GB, only one large model can be resident; switching models must stop the previous server/proxy.

## 7. Expected ranges (examples, not guarantees)

Use `references/model-matrix.md` for the model/VRAM tiers. Measured numbers depend on vendor power mode, CPU, GPU, context, quant, and prompt. Example: Qwen3.6-35B-A3B Q4 on a 12GB RTX 5070 Ti laptop + i7-14650HX with `--n-cpu-moe 24`, MTP, 32K context, `-t 8` + P-core affinity, vendor Performance mode: ~61–67 tok/s generation on a 300-character creative prompt; ~77–104 on a 128-token quicksort prompt; ~1258 tok/s prompt processing on a 3K prompt. In vendor Quiet mode the same setup drops to ~18–30 tok/s. Treat these as a data point, not a promise.

## 8. Case study: 12GB RTX 5070 Ti laptop (2026-11-06)

Hardware: RTX 5070 Ti Laptop 12GB, i7-14650HX (16C/24T), 64GB DDR5-5600, Windows 11. Model: Qwen3.6-35B-A3B Q4_K_M, 32K context, `--n-cpu-moe 24`, MTP, llama.cpp b12017. Tests were direct to llama.cpp `:8081`; quicksort = 128 output tokens; creative = ~300 Chinese characters; prompt = 3016 tokens. Generation figures are 3 runs unless noted.

| Scenario | Creative tok/s | Quicksort tok/s | 3K prompt tok/s | GPU |
|---|---:|---:|---:|---|
| **Worst**: vendor Quiet + `-t 16`, no affinity | ~18 | ~27 | ~700 | ~19W, P4 |
| **Best**: vendor Performance + `-t 8` + P-core affinity | ~65 | ~88 | ~1258 | 66–71W, P0 |
| **Improvement** | **~3.6×** | **~3.2×** | **~1.8×** | — |

Same model, same prompt, same 32K config; the difference is the vendor power mode and CPU scheduling. Intermediate tests showed GPU clock locking alone did not help, while P-core affinity gave ~20% in Quiet mode; the final `-t 8` choice is empirical. The old 65 tok/s was a single Performance-mode quicksort run; the tuned configuration now exceeds it. These numbers are a data point for this exact laptop; benchmark each machine.
