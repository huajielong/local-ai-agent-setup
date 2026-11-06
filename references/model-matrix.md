# Model Matrix

Model landscape changes quickly. Treat tags/sizes as a starting point and verify with `ollama show <tag>` or the official model card before recommending.

Measured tok/s are per-machine examples. Tune vendor/OS power mode, backend offload, `-t`/affinity, context, and quant for each machine; do not copy numbers or flags across GPUs/CPUs. For multi-GPU workstations, sum VRAM for tensor parallel and measure concurrent throughput, not single-stream speed.

## 1. Hardware tiers

| Tier | Hardware | Primary model | Backend | Expected experience |
|---|---|---|---|---|
| S | NVIDIA ≥24GB VRAM, ≥64GB RAM | Qwen3.8-27B dense Q4 (~17.7GB); Qwen3.6-35B-A3B Q4 (22GB) | llama.cpp full GPU | Strong coding/agent; ~30–70 tok/s depending on model/GPU |
| A | NVIDIA 16–23GB VRAM, ≥64GB RAM | Qwen3.6-35B-A3B Q4 with partial offload; Gemma 4 26B-A4B Q4 (~16GB) | llama.cpp | Good agent; speed depends on offload |
| B | NVIDIA 12–15GB VRAM, ≥64GB RAM | Qwen3.6-35B-A3B Q4 via `--n-cpu-moe 24`; Gemma 4 12B Q4 | llama.cpp | Qwen ~60–100 tok/s in vendor Performance mode (~18–30 in Quiet) measured on 5070 Ti 12GB + i7-14650HX; `-t 8` + P-core affinity; prompt ~1258 tok/s; Gemma ~34 |
| C | NVIDIA 8–11GB VRAM, ≥32GB RAM | Gemma 4 12B Q4 (8GB); Qwen3.5-9B Q4 (~6GB) | llama.cpp / Ollama | Gemma may be tight at 32K; no 35B |
| D | 4–7GB VRAM or 16GB RAM | Qwen3.5-4B (~3GB); Gemma 4 E4B; TranslateGemma 4B | Ollama / llama.cpp | Small chat/translation; weak agent |
| E | CPU-only / <4GB VRAM | Qwen3.5-0.8B/2B/4B; TranslateGemma 4B CPU | Ollama CPU | Translation/Q&A only; no Claude-Code-class agent |
| Apple | Unified memory 16 / 24 / 32GB+ | 9B / 12B / 35B-A3B via MLX | Ollama / MLX / LM Studio | 32GB+ can try 35B-A3B; 16GB stick to 9B/12B |
| AMD | ROCm-supported GPU | Same VRAM tiers if ROCm works; else Vulkan/CPU | Ollama / llama.cpp | Check ROCm support per GPU; Vulkan fallback is slower |

**Never** promise a 35B-class model on 8GB VRAM or 16GB RAM. Say what fits and what the experience will be.

### Borderline fits

- **30B/35B-A3B MoE on 8GB VRAM + 32GB RAM** (for example Qwen3-Coder-30B-A3B Q4 or Qwen3.6-35B-A3B Q4): the weights are roughly 18–22GB. It can load with most experts on CPU, but prompt processing is slow, 32K context leaves little RAM headroom, and other apps can push it into swap. Treat it as an experiment, not the primary Claude Code model; a 9B/12B dense model at Q4 is more usable. If the user insists, cap context at 8–16K and say what speed to expect.
- **35B-A3B on 16GB RAM:** do not recommend; the weights alone exceed RAM.
- **Qwen3.8-27B dense on 12GB:** loads only with heavy offload (~5–8 tok/s); not an agent default.

## 2. Model registry (starting points)

| Model | Tag / file | Size | License | Notes |
|---|---|---|---|---|
| Qwen3.6-35B-A3B-MTP | `qwen3.6:35b-a3b-mtp-q4_K_M` | ~22GB | Apache 2.0 | MoE 35B/3B active; text+vision+tools; best 12GB+64GB agent compromise |
| Qwen3-Coder-30B-A3B | `qwen3-coder:30b` (verify tag) | ~18–19GB Q4 | Apache 2.0 | Coding-focused MoE 30B/3B active; good on 12GB+64GB with CPU experts; borderline on 8GB+32GB |
| Qwen3.8-27B | `qwen3.8:27b` | ~17.7GB Q4 | Apache 2.0 | Dense 27B; strong coding; best on 24GB full GPU; 12GB needs offload and is slow |
| Gemma 4 12B | `gemma4:12b` | ~8GB Q4 | Gemma Terms | 11.9B dense; text+vision+audio+tools; 262K context; fast multimodal |
| Gemma 4 26B-A4B | `gemma4:26b-a4b` | ~16GB Q4 | Gemma Terms | MoE 26B/4B active; 16GB+ |
| TranslateGemma 4B | `translategemma:4b` | ~3.3GB Q4 | Gemma Terms | 55 languages; translation specialist; 2K native context |
| Qwen3.5-9B | `qwen3.5:9b` | ~6GB Q4 | Apache 2.0 | 200+ languages; good 8–12GB general model |
| Qwen3.5-4B | `qwen3.5:4b` | ~3GB Q4 | Apache 2.0 | Light general/translation; disable thinking for speed |
| gpt-oss:20b | `gpt-oss:20b` | ~14GB | Apache 2.0 | MoE 21B/3.6B active; native tools; good 12–16GB agent; verify tool loop |
| GLM-4.7-Flash | `glm-4.7-flash` (or 12GB-specific quant) | ~19GB default | Check model card | 30B MoE; 12GB needs IQ2/Q2 quant; tool reliability drops at low precision |
| Gemma 4 E4B / E2B | `gemma4:e4b` / `gemma4:e2b` | ~3–4GB / ~2GB | Gemma Terms | Low-VRAM multimodal |

## 3. Quantization rules

- **Q4_K_M** is the default sweet spot: quality close to Q5/Q6, reasonable size/speed.
- **Q8_0** is bigger and slower with little practical gain for local agents; avoid on 12GB.
- **Q5/Q6** only when the model still fits with context and the user wants a little more quality.
- **Q2/IQ2** is a last resort. It can fit a larger model, but tool calling and long-context reliability degrade. Prefer a smaller model at Q4 over a larger model at Q2.
- You cannot "up-quantize" a Q4 model to Q6 and regain quality; you need the original higher-precision model.
- KV cache quantization (`q8_0`) is runtime and separate from weight quantization.

## 4. Context and memory

- Claude Code system prompt + tool definitions ~20K tokens. Use 32K context; 4K default is unusable.
- Translation: 2K context is enough and saves VRAM.
- Longer context costs KV cache; on 12GB, 32K is the practical ceiling for Qwen3.6 + Gemma 4.
- One big model at a time. 12GB cannot hold Qwen (10.8GB) + Gemma (7.9GB). TTS/vision/other GPU apps compete.

## 5. Speed expectations (rough, hardware-dependent)

| Model | 12GB + 64GB (llama.cpp) | 12GB Ollama | Notes |
|---|---|---|---|
| Qwen3.6-35B-A3B Q4 | ~60–100 tok/s Performance / ~18–30 Quiet (n-cpu-moe 24, MTP, `-t 8` + P-core affinity) | ~6.6 tok/s | Ollama lacks MoE expert offload; vendor Quiet mode caps CPU/GPU |
| Gemma 4 12B Q4 | ~34 tok/s full GPU | ~5 tok/s | llama.cpp much faster |
| TranslateGemma 4B | ~78 tok/s GPU / ~22 CPU | ~70–80 GPU | CPU variant 0 VRAM |
| Qwen3.8-27B Q4 | ~5–8 tok/s (12GB offload) | ~5 tok/s | 24GB full GPU is much faster |

## Measuring speed

- Report generation and prompt processing separately.
- Use at least 3 runs and ≥250 generated tokens; quote the median or sustained range, not a single sample.
- Record MTP acceptance (`draft_n_accepted / draft_n`), GPU power/clocks/P-state, and CPU utilization. On a 12GB card running a 22GB MoE model, `--n-cpu-moe` makes the CPU the likely bottleneck even when the GPU shows low utilization.
- A short 128-token prompt can be faster than sustained output; on the 5070 Ti laptop, Performance mode gave 77–104 tok/s on a quicksort prompt vs 61–67 on a ~300-character creative prompt, while Quiet mode gave 18–30. Do not publish a single peak as the expected speed.

Always measure on the target machine; laptop thermals/power modes can cut speeds substantially.

## 6. Selection heuristics

1. If the user wants a **coding agent**, prioritize tool calling and context: Qwen3.6-35B-A3B, Qwen3.8-27B, gpt-oss:20b, Gemma 4 12B.
2. If the user wants **translation**, use TranslateGemma 4B; it is smaller and better than a general model at the same size.
3. If the user wants **images/audio/video**, Gemma 4 12B is the multimodal default.
4. If the machine is **8–16GB RAM / no GPU**, recommend 4B-class models or a cloud API; do not force a local agent.
5. If the user is **non-technical**, prefer Ollama/LM Studio over raw llama.cpp, even at some speed cost.
6. If the user asks for "the strongest model", explain the VRAM/RAM ceiling first, then give the best fit — not the datacenter model.
7. If the user has 8GB VRAM + 32GB RAM and asks for a 30B/35B-A3B coder, explain the borderline fit before offering it; make a 9B/12B dense model the default.
