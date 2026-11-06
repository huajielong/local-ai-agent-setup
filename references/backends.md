# Backends and Platform Notes

## 1. Comparison

| Backend | Best for | Pros | Cons |
|---|---|---|---|
| **Ollama** | Model management, small/medium models, translation | Cross-platform, one-command pull/run, easy API | Big new architectures may be slow; no MoE expert offload (`num_cpu_moe`) in stable 0.40.x; default context 4K on <24GB VRAM |
| **llama.cpp** | Performance on local hardware, MoE/large models | CUDA/Metal/Vulkan/ROCm; `--n-cpu-moe`; MTP; precise control | Manual flags; need matching GGUF; no model store |
| **LM Studio** | GUI users, quick experiments | Bundled runtime, MoE offload toggle, model browser | Another app; server API differs; less scriptable |
| **MLX** | Apple Silicon | Unified memory, good Metal performance | Apple-only; separate tooling |
| **vLLM** | Team/GPU server, concurrent users | Continuous batching, PagedAttention, tensor parallel across GPUs, OpenAI API | Linux-first; reserves GPU memory; AWQ/GPTQ/FP8 checkpoint support varies; not native Windows |
| **SGLang** | Agent serving, high throughput | RadixAttention prefix caching, structured output, OpenAI API | Linux-first; newer ecosystem; checkpoint support varies |
| **anthropic-proxy** | Claude Code with any OpenAI-compatible backend | Anthropic `/v1/messages`, SSE, tool translation, token count; Go single binary | Need to configure upstream/model |
| **LiteLLM** | Teams, many providers | Mature proxy, OpenAI + Anthropic endpoints, virtual keys | Python dependency; Windows `uvloop` issue with `[proxy]` extras; use a venv |
| **Claude Code Router** | Routing Claude Code to multiple providers | Purpose-built, transformers | Config UI/format changes across versions |

## 2. Platform matrix

| OS / GPU | Recommended | Notes |
|---|---|---|
| Windows + NVIDIA | llama.cpp CUDA + anthropic-proxy | Best performance; use `--n-cpu-moe` for 35B MoE on 12GB; vLLM/SGLang need WSL2 |
| Windows + AMD | Ollama / LM Studio; llama.cpp Vulkan or ROCm | ROCm support varies by GPU; Vulkan is the fallback |
| Windows CPU-only | Ollama CPU | 1–4B models; translation/Q&A only |
| macOS Apple Silicon | Ollama / MLX / LM Studio | Unified memory; `llama.cpp` Metal builds also work |
| Linux + NVIDIA | llama.cpp CUDA + proxy for one user; vLLM/SGLang + LiteLLM for a team | Same model can move between them; concurrency decides the backend |
| Linux + AMD | llama.cpp ROCm/Vulkan; Ollama | Check ROCm compatibility per GPU |

## 3. Ollama settings that matter

```bash
OLLAMA_MODELS=D:\Ollama\models          # optional custom model dir (Windows example)
OLLAMA_CONTEXT_LENGTH=32768             # Claude Code needs >=32K; 4K default is unusable
OLLAMA_FLASH_ATTENTION=1
OLLAMA_KV_CACHE_TYPE=q8_0               # best balance; q4_0 if VRAM is tight
OLLAMA_NUM_PARALLEL=1
OLLAMA_MAX_LOADED_MODELS=1
```

- Check actual quantization with `ollama show <model>`.
- Check loaded model/processor/context with `ollama ps`.
- On Windows, keep the model directory a **plain drive-letter path**; Ollama 0.40.x has a junction/mount-point manifest bug.

## 4. llama.cpp settings that matter

Core flags for a MoE model on 12GB:

```text
--n-cpu-moe 24        # keep experts of the first N layers on CPU; tune 16–32
-ngl 999              # offload all possible layers
-c 32768              # context; lower to 16384 if OOM
-fa on                # flash attention
-ctk q8_0 -ctv q8_0   # KV cache quantization
--load-mode none      # avoid mmap overhead when RAM is sufficient
-t 16                 # CPU threads; tune to physical cores
--parallel 1          # single user
--reasoning-budget 0  # disable thinking for speed; remove for complex reasoning
--spec-type draft-mtp # Qwen MTP speculative decoding, if supported
--host 127.0.0.1 --port 8081 --jinja -a qwen
```

- `--n-cpu-moe`: lower = more experts on GPU (faster, more VRAM); higher = more CPU (safer, slower). Tune until VRAM has ~0.5–1GB headroom.
- `--list-devices` must show `CUDA0` / `Metal` / `Vulkan0`; otherwise the build is CPU-only or the runtime DLL path is wrong.
- Match the GGUF architecture; a generic CUDA build may not support a brand-new architecture.

## 5. Team and multi-user serving (vLLM / SGLang)

llama.cpp and Ollama are built around one user; `--parallel 1` queues concurrent requests. If two or more people share the endpoint, use a batched server on Linux/NVIDIA:

| Stack | Use when | Notes |
|---|---|---|
| **vLLM** | Team server, one model across one or more GPUs | Continuous batching, PagedAttention, `--tensor-parallel-size N`; OpenAI-compatible `/v1`; AWQ/GPTQ/FP8 support depends on the checkpoint |
| **SGLang** | Agent traffic with shared system prompts or high throughput | RadixAttention prefix caching, structured output; OpenAI-compatible |
| **LiteLLM** | Anthropic facade, per-user keys, quotas | Exposes `/v1/messages`, maps to the vLLM/SGLang upstream, virtual keys |

A practical shape for 2× RTX 4090 (48GB total):

```bash
# Linux host; serve one model across both GPUs
vllm serve <model> --tensor-parallel-size 2 --max-model-len 32768 \
  --gpu-memory-utilization 0.90 --max-num-seqs 4 \
  --enable-prefix-caching --enable-auto-tool-choice --tool-call-parser hermes \
  --served-model-name qwen
```

- Use an AWQ/GPTQ 4-bit checkpoint when BF16 weights do not fit; confirm vLLM supports that architecture before promising it.
- `--enable-prefix-caching` is the biggest Claude Code latency win because the ~20K system prompt repeats every turn.
- `--tool-call-parser` must match the model/version (Qwen often uses `hermes`); verify a real `tool_use` response, not just a text completion.
- Start with `--max-num-seqs 4`; raise it only after watching KV-cache usage and preemption.
- Start at 32K context; raise it only after measuring KV-cache headroom.

SGLang equivalent:

```bash
python -m sglang.launch_server --model-path <model> --tp 2 --port 8000 \
  --context-length 32768
```
- Put LiteLLM on `127.0.0.1:8787` (or behind the team's auth gateway) and point Claude Code at LiteLLM. Do not expose vLLM/SGLang directly to the LAN without authentication.
- vLLM and SGLang are Linux-first. On Windows use WSL2 or a Linux host; on a single laptop GPU, llama.cpp remains the better fit.
- Measure with concurrent requests, not one prompt. A single-stream tok/s number hides the batching benefit.

## 6. Proxy options for Claude Code

Before using the client snippets below, read `claude-code-integration.md` §0. If any Claude Code settings file defines an `env` block, shell environment variables are ignored; launch with `claude --settings <dedicated.json>` instead.

### 6.1 Ollama native Anthropic API (simple)

- Ollama ≥0.14 exposes `/v1/messages`.
- Client:
  ```
  ANTHROPIC_BASE_URL=http://localhost:11434
  ANTHROPIC_AUTH_TOKEN=ollama
  ANTHROPIC_API_KEY=""
  claude --model <ollama-model>
  ```
- No `/v1` suffix on the base URL.
- Easy, but big models are slow in Ollama; use for small models or a quick trial.

### 6.2 anthropic-proxy (recommended for performance)

- Go binary, Windows/macOS/Linux releases.
- Config `.env`:
  ```
  ANTHROPIC_PROXY_UPSTREAM_URL=http://127.0.0.1:8081/v1/chat/completions
  ANTHROPIC_PROXY_UPSTREAM_API_KEY=dummy
  ANTHROPIC_PROXY_DEFAULT_MODEL=qwen
  ANTHROPIC_PROXY_TOOL_FORMAT=native
  ANTHROPIC_PROXY_FORCE_MODEL=1
  ANTHROPIC_PROXY_LISTEN_ADDR=127.0.0.1:8787
  ```
- Client:
  ```
  ANTHROPIC_BASE_URL=http://127.0.0.1:8787
  ANTHROPIC_API_KEY=anything
  ANTHROPIC_AUTH_TOKEN=anything
  CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
  claude --model claude-sonnet-4-6
  ```
- `/v1/models` advertises Claude model IDs; `FORCE_MODEL=1` maps them to the upstream model.
- `TOOL_FORMAT=native` for native tool calling; `xml` as a fallback.
- Verify `/v1/messages` text and a `tool_use` response before declaring success.

### 6.3 LiteLLM

- Supports Anthropic `/v1/messages` and many providers.
- On Windows, `pip install "litellm[proxy]"` may fail on `uvloop`; install core `litellm` plus `fastapi`, `uvicorn`, `python-multipart`, `pyyaml`, `jsonschema`, `aiohttp` manually, preferably in a venv.
- Do not upgrade the user's global Python environment without consent; isolate in a venv.

## 7. Choosing for the user

- **Non-technical / just wants it to work:** Ollama + LM Studio; use Ollama native API for small models.
- **Technical / wants performance, one user:** llama.cpp + anthropic-proxy.
- **Team / multiple concurrent users on Linux + NVIDIA:** vLLM or SGLang for batching, LiteLLM for the Anthropic facade and keys.
- **Team / multiple providers, one user:** LiteLLM or Claude Code Router.
- **Apple Silicon:** Ollama/MLX first; llama.cpp Metal if needed.
- **No GPU:** Ollama CPU with 1–4B models; be explicit about limits.
