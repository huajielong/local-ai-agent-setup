---
name: local-ai-agent-setup
description: Use this skill whenever the user wants to run a local LLM, a local AI agent, or Claude Code with local models on any computer; asks what model their hardware can run; or wants to set up or reconfigure Ollama, llama.cpp, LM Studio, MLX, vLLM, SGLang, LiteLLM, or an Anthropic proxy; or needs a team/multi-user local inference server. It detects OS/GPU/VRAM/RAM/disk, chooses a model and backend tier, and produces a confirmed setup plan. Trigger even if the user only says "本地大模型", "本地 AI", "离线 AI", "端侧模型", "跑得动什么模型", "Claude Code 本地", "Claude Code 本地模型", "本地部署", "本地模型速度慢", "性能调优", "多 GPU", "工作站", "团队本地模型", "多用户本地推理", "vLLM 本地部署", "Ollama 模型目录", "Ollama 配置", "本地模型迁移", "32K 上下文", "上下文大小", "上下文开多大", "context size", or gives hardware specs without naming a tool. Also trigger when someone wants to turn a working local setup into a portable handover package or a setup guide for another computer. Do not use for cloud-only API setup, generic CUDA/ROCm kernel development, or prompt-only tasks; use this skill only when the goal is on-device inference or a local Claude Code wrapper.
compatibility: Claude Code on Windows, macOS, or Linux. Detection scripts use PowerShell or bash; no third-party Python package is required.
version: 0.4.0
author: huajielong
license: MIT
---

# Local AI Agent Setup

Help the user choose and build the best local AI stack their computer can actually run. The goal is not "the biggest model" — it is the best model/backend combination for this machine, with realistic expectations and a safe, reversible setup.

`<skill-dir>` in the commands below means the directory containing this `SKILL.md` (the skill's base directory).

## Non-negotiable safety rules

1. **Detect first, read-only.** Run the hardware detection script before recommending anything.
2. **Do not download large files or install software before presenting a plan and getting confirmation.** A model is 2–30GB; ask first. If the user already asked to proceed, still state the estimated download size and disk impact.
3. **Use official sources only.** Ollama library, Hugging Face official repos, GitHub releases. Verify SHA-256 when the source provides one.
4. **Keep local services on 127.0.0.1.** Never bind a proxy or model server to 0.0.0.0 unless the user explicitly asks for LAN access and understands the risk.
5. **Do not change the user's normal `claude` command.** Use a separate `claude-local` wrapper. If any Claude Code settings file defines an `env` block, launch with `claude --settings <dedicated-settings.json> --model <id>`; shell environment variables lose to settings.
6. **Do not recommend `--dangerously-skip-permissions` as a default.** Local models can make mistakes; tool execution needs review.
7. **Respect licenses.** Model weights are not redistributable the way code is. Point users to official downloads and license terms; do not package weights without checking.

## Workflow

### 1. Detect hardware (read-only)

Pick the script for the OS:

- Windows:
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File "<skill-dir>\scripts\detect-hardware.ps1"
  ```
- macOS / Linux:
  ```bash
  bash "<skill-dir>/scripts/detect-hardware.sh"
  ```

If scripts cannot run, ask the user for:
- OS and version
- `nvidia-smi` output (or GPU model / VRAM)
- Total RAM
- Free disk space
- CPU model (optional)
- Whether Ollama / Claude Code / Node / LM Studio are already installed

### 2. Classify the machine

Use `references/model-matrix.md` for the full table. Quick tiers:

| Tier | Hardware | Typical model | Backend |
|---|---|---|---|
| S | NVIDIA ≥24GB VRAM, ≥64GB RAM | Qwen3.8-27B dense Q4, Qwen3.6-35B-A3B Q4 | llama.cpp full GPU |
| A | NVIDIA 16–23GB VRAM, ≥64GB RAM | Qwen3.6-35B-A3B Q4 with partial offload; Gemma 4 26B-A4B | llama.cpp |
| B | NVIDIA 12–15GB VRAM, ≥64GB RAM | Qwen3.6-35B-A3B Q4 via `--n-cpu-moe`; Gemma 4 12B | llama.cpp |
| C | NVIDIA 8–11GB VRAM, ≥32GB RAM | Gemma 4 12B Q4; Qwen3.5-9B/4B | llama.cpp / Ollama |
| D | 4–7GB VRAM or 16GB RAM | Qwen3.5-4B; Gemma 4 E4B; TranslateGemma 4B | Ollama / llama.cpp |
| E | CPU-only / <4GB VRAM | 1–4B models; translation or Q&A only | Ollama CPU |
| Apple | Unified memory 16GB / 24GB / 32GB+ | 9B / 12B / 35B-A3B (MLX) | Ollama / MLX / LM Studio |
| AMD | ROCm-supported GPU | Same VRAM tiers if ROCm works; else Vulkan/CPU | Ollama / llama.cpp |

**Never promise a 35B-class model on 8GB VRAM or 16GB RAM.** A 30B/35B-A3B MoE may technically load on 8GB + 32GB with CPU offload, but prompt processing and 32K context are poor; treat it as an experiment, not the primary agent. Say what will actually fit and what the experience will be.

**Single user vs team changes the backend, not just the model.** On a Linux/NVIDIA server with 2+ concurrent users, serving the Tier S model through vLLM/SGLang (plus LiteLLM for Anthropic-facing keys) is usually better than a single-user llama.cpp process.

### 3. Choose the backend

Use `references/backends.md` for details. Quick rules:

- **Ollama** — easiest cross-platform path; best for small/medium models and model management. New architectures may be slow on big models because Ollama lacks MoE expert offload.
- **llama.cpp** — performance path for MoE/large models; CUDA/Metal/Vulkan/ROCm builds; use `--n-cpu-moe` to keep experts in RAM and attention on GPU. This is usually the best choice for Qwen3.6-35B-A3B on 12GB.
- **LM Studio** — GUI alternative for non-CLI users; bundled runtime and MoE offload.
- **MLX** — Apple Silicon; unified memory; good for 12B/35B-A3B.
- **vLLM / SGLang** — Linux/NVIDIA server path for teams and concurrent users; continuous batching and tensor parallelism across GPUs. Pair with LiteLLM when clients need an Anthropic-compatible endpoint and per-user keys. Not a native Windows option; use WSL2 or a Linux host.

### 4. Decide Claude Code integration

Use `references/claude-code-integration.md`. Two modes:

- **Simple mode:** Ollama's native Anthropic API (`http://localhost:11434`). Easy, but big models are slow.
- **Performance mode:** llama.cpp OpenAI API + `anthropic-proxy` (Go, cross-platform), then point Claude Code at the proxy (usually `http://127.0.0.1:8787`). This is the recommended path when the user wants an agent.

Before generating the wrapper, read `~/.claude/settings.json` and any project `.claude/settings.json`. If their `env` block sets `ANTHROPIC_BASE_URL` or model IDs, generate a dedicated settings JSON and launch with `claude --settings <file> --model <id>`; `export`/`set` alone will be silently ignored. See `references/claude-code-integration.md` §0.

Always keep normal `claude` untouched; generate a `claude-local` wrapper. If the user wants the UI to show the local model rather than a built-in Claude label, set the proxy's `ANTHROPIC_PROXY_DEFAULT_SONNET/OPUS/HAIKU_MODEL` to the local alias and `..._MODEL_NAME` to a human-readable name, then launch with `--model <local-id>`. Claude Code 2.1.x may send environment context as mid-conversation `role:"system"` messages; strict Qwen/llama.cpp Jinja templates reject these with `500 ... System message must be at the beginning`, so insert a sanitizer relay that hoists them into the top-level `system` prompt (client 8787 → sanitizer → anthropic-proxy 8788; see `references/claude-code-integration.md` §2.4). On a machine with multiple installed models behind one GPU, generate a registry and one wrapper per model; only one can be active at a time, and switching restarts llama-server/proxy (see `references/claude-code-integration.md` §3.1). For a team, put LiteLLM in front of vLLM/SGLang to expose `/v1/messages` and per-user virtual keys; point each `claude-local` at LiteLLM, not directly at the model server.

**Size the context per model before writing the wrapper.** Do not hardcode 32K: compute the KV footprint from the GGUF metadata and the VRAM budget (`scripts/gguf-kv-budget.py`, stdlib-only, does this from the GGUF header), then derive the auto-compact window from the chosen context (`references/context-sizing.md`). Claude Code clamps `CLAUDE_CODE_AUTO_COMPACT_WINDOW` to a floor of 100000, so a server context below ~110K cannot auto-compact at all — size to at least 128K when the hardware allows, and say so when it does not.

### 5. Present the plan (exact template)

Use this structure. Keep the main plan scannable; put details in tables and move long runbooks, monitoring, and rollout checklists into an appendix.

```markdown
## 1. Hardware report

| Item | Value |
|---|---|
| OS | ... |
| CPU | ... |
| RAM | ... |
| GPU / VRAM | ... |
| Free disk | ... |
| Existing tools | Ollama / Claude Code / Node / LM Studio / none |

## 2. Recommended tier

- Tier: S / A / B / C / D / E / Apple / AMD
- Why: one or two sentences tied to VRAM/RAM, not generic advice.

## 3. Model plan

| Role | Model | Size | License | Why |
|---|---|---|---|---|
| Primary | ... | ... | ... | ... |
| Fast / multimodal | ... | ... | ... | ... |
| Translation (optional) | ... | ... | ... | ... |

## 4. Backend plan

- Inference: Ollama / llama.cpp / LM Studio / MLX / vLLM / SGLang
- Claude Code bridge: none / Ollama native / anthropic-proxy / LiteLLM
- Concurrency: single user / team (approx. N users); if team, batched server + gateway + per-user keys
- Context: <N> for Claude Code (<x> GB KV, <y> GB VRAM free); auto-compact <window>; 2K for translation
- Context math: <layers> × <kv heads> × <head dim> × <bytes> = <kb> KB/token
- VRAM budget: ...

## 5. Setup plan

1. ...
2. ...
3. ...

## 6. Download / disk estimate

- Total download: ... GB
- Free disk required: ... GB

## 7. Verification

- Health endpoints / commands
- One end-to-end test

## 8. Risks and caveats

- Speed expectations
- VRAM sharing with other apps
- License terms
- What will not work

## Confirmation

"May I proceed with the downloads/installs above? Estimated download: ... GB."
```

### 6. Execute only after confirmation

- Install prerequisites only if missing.
- Pull models with official tags; show progress.
- Generate start scripts/wrappers from `assets/` templates, substituting paths, ports, model names, and the context/auto-compact values chosen in step 4.
- Put the context in exactly one place per model (the registry entry or a single variable) and pass it to both the server flag and `CLAUDE_CODE_AUTO_COMPACT_WINDOW`; two independent constants drift apart and produce the "request exceeds available context size" error.
- On Windows, save `.bat`/`.cmd` files with CRLF line endings and ASCII comments; LF-only batch files are misparsed by cmd.exe.
- Start services; verify health; run one end-to-end task.
- Write a short `README` with start/stop/health commands and known limits.

### 7. Verify and document

Minimum checks:
- Model listed (`ollama list` or GGUF path exists).
- Server context is the planned one: `curl -s http://127.0.0.1:8081/props | jq '.default_generation_settings.n_ctx'`, and free VRAM is still ≥1GB.
- One request larger than the context you previously considered safe (for example a 40K-token filler) returns 200 rather than a context-size error.
- Health endpoint for the model server.
- Health endpoint for the proxy (if used).
- A real completion (not just "server up").
- Tool call test if Claude Code is the target.
- Normal `claude` still uses its original provider; `claude-local` `/status` shows the local base URL.
- Measure generation at least 3 times with ≥250 output tokens; report the sustained range, not a single short-run peak.
- Stop/restart test.
- Report measured speed and VRAM.

### 8. Tune performance

Use `references/performance-tuning.md`. Tune in this order:

1. **OS/vendor power mode**: Performance (not Quiet), AC power, NVIDIA/AMD control panel, MUX/dGPU mode, close background GPU apps.
2. **Backend/offload**: GPU layers / `--n-cpu-moe`, flash attention, KV quantization, context, MTP/draft.
3. **CPU threads/affinity**: detect P-cores/CCD/NUMA; tune `-t`; benchmark 4/8/12/16.
4. **Model/quant/context**: Q4_K_M, the largest context that fits (see `references/context-sizing.md`), tool-capable models.
5. **Measure** at least 3 runs with ≥250 output tokens; report sustained generation and prompt speed; compare GPU clocks/power/P-state and CPU load.

Do not tune clocks or copy `-t`/affinity/`--n-cpu-moe` values from another machine before checking the vendor power mode and benchmarking. A vendor Quiet mode can cut throughput by 2–4× and is not fixed by `nvidia-smi -lgc`.

## Selection heuristics

- **Best model is use-case dependent.** Coding/agent → tool-capable model with 32K+ context; chat/translation → smaller/faster; team → batched backend. Score quality, fit, speed, and license; do not pick by parameter count alone.
- **Quality first, VRAM second, speed third** for coding/agent work. **Speed first** for translation/chat.
- **Dense vs MoE:** dense models are simpler and often higher quality per parameter; MoE models are much faster when partially offloaded. On 12GB, Qwen3.6-35B-A3B (MoE) is usually the best agent compromise.
- **Quantization:** Q4_K_M is the sweet spot. Q8 is slower and bigger with little practical gain; Q2/IQ2 hurts tool calling and long-context reliability.
- **Context:** Claude Code's system prompt + tool definitions are roughly 20K tokens, so 4K is unusable and 32K is only a floor. Budget the KV cache and take the largest rung that fits: on 12GB with a 35B-A3B Q4, 128K is reachable at ~52 tok/s by moving 30 of 41 MoE layers to CPU. Below ~110K the auto-compact window is clamped and sessions die at the context limit. See `references/context-sizing.md`. Translation models can stay at 2K.
- **Single user vs team:** llama.cpp/Ollama are simplest for one person; a team hitting one endpoint needs a batched server (vLLM/SGLang) behind LiteLLM. The model can be the same; concurrency changes the backend.
- **Multi-GPU/workstation:** sum VRAM for tensor parallel; use vLLM/SGLang + LiteLLM for concurrent users and llama.cpp for a single-user workstation. Measure concurrent throughput, not single-stream tok/s.
- **Borderline fit:** if the weights fit only by offloading most layers to RAM, say so and set expectations; prefer a smaller model at Q4 over a larger model that barely loads.
- **One big model at a time.** 12GB cannot hold two 8–11GB models. TTS/vision/other GPU apps compete for the same VRAM.
- **CPU-only is a different product.** 4B CPU models can translate and answer, but do not promise a Claude-Code-class agent.

## References

Read these only when needed:

- `references/model-matrix.md` — model tags, sizes, licenses, VRAM/RAM tiers, expected speeds.
- `references/context-sizing.md` — KV-cache math, VRAM budget, context ladder, auto-compact window, verification and traps.
- `references/backends.md` — Ollama vs llama.cpp vs LM Studio vs MLX; platform notes; proxy options.
- `references/claude-code-integration.md` — settings/env precedence, Anthropic proxy setup, model IDs, context, tool format, permissions.
- `references/performance-tuning.md` — cross-platform power/vendor modes, offload, CPU affinity, quantization/context, benchmark method, and traps.
- `references/troubleshooting.md` — common failures across OSes.
- `references/safety-licenses.md` — licensing, redistribution, privacy, security.

## Assets

Use these as starting points; substitute placeholders and keep paths platform-correct:

- `assets/anthropic-proxy.env.tmpl`
- `assets/claude-local.settings.json.tmpl` (preferred)
- `assets/claude-local.env.tmpl` (only when no settings file defines `env`)
- `assets/chat-sanitizer.js` (public 8787 → anthropic-proxy 8788; hoists mid-conversation system messages)
- `assets/health-check.ps1`
- `assets/health-check.sh`
- `scripts/gguf-kv-budget.py` — optional; reads a GGUF header and prints KV/token, the context ladder, and a suggested context from measured free VRAM

For start scripts, generate platform-specific commands from the model/backend plan rather than copying a Windows-only batch file to macOS/Linux.

## Anti-patterns

- Recommending the largest model before checking VRAM/RAM.
- Ignoring Apple Silicon/AMD/CPU-only machines.
- Telling the user to "just install Ollama" without a model/VRAM plan.
- Auto-downloading 30GB without confirmation.
- Claiming "100% offline/private" when the agent shell may still call the network.
- Exposing a local proxy to the LAN.
- Modifying the user's normal `claude` configuration.
- Writing `set ANTHROPIC_BASE_URL=...` when a settings file already defines `env`; the wrapper silently keeps using the online provider.
- Shipping LF-only Windows `.bat`/`.cmd` files.
- Quoting a single short-run tok/s peak as the expected sustained speed.
- Hardcoding 32K context while leaving `CLAUDE_CODE_AUTO_COMPACT_WINDOW` at 100000: compaction never fires and `/compact` overflows too.
- Setting the auto-compact window at or above the server context (it must fit the transcript plus the ~20K system prompt).
- Pointing Claude Code 2.1.x directly at a strict Jinja template without handling mid-conversation system messages.
- Tuning GPU clocks or copying `-t`/affinity/`--n-cpu-moe` from another machine before checking the vendor power mode and benchmarking.
- Using a translation-only or embedding model for Claude Code tool use.
