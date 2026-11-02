# Claude Code Integration

Claude Code speaks the Anthropic Messages API. Local servers usually speak OpenAI Chat Completions. There are three ways to bridge them: Ollama's native API for small models, anthropic-proxy for one user on llama.cpp, and LiteLLM in front of a batched server for a team.

## 1. Simple mode: Ollama native Anthropic API

Use when the user wants the least setup, or the model is small enough that Ollama's speed is acceptable.

```bash
export ANTHROPIC_BASE_URL=http://localhost:11434
export ANTHROPIC_AUTH_TOKEN=ollama
export ANTHROPIC_API_KEY=""
claude --model <ollama-model-tag>
```

Windows `.bat`:

```bat
@echo off
set "ANTHROPIC_BASE_URL=http://localhost:11434"
set "ANTHROPIC_AUTH_TOKEN=ollama"
set "ANTHROPIC_API_KEY="
claude --model qwen3.6:35b-a3b-mtp-q4_K_M %*
```

Rules:
- Ollama must be >=0.14 for `/v1/messages`.
- Do **not** append `/v1` to `ANTHROPIC_BASE_URL`; Claude Code appends `/v1/messages` itself.
- Set a context of at least 32K (`OLLAMA_CONTEXT_LENGTH=32768`); 4K is unusable for Claude Code.
- Big models in Ollama can be very slow (no MoE expert offload); this mode is best for small/medium models.

## 2. Performance mode: llama.cpp + anthropic-proxy

Use when the user wants a responsive coding agent.

### 2.1 Start llama.cpp

```bash
llama-server -m <model.gguf> \
  --n-cpu-moe 24 -ngl 999 \
  -c 32768 -fa on -ctk q8_0 -ctv q8_0 \
  --load-mode none -t 16 --parallel 1 \
  --reasoning-budget 0 --spec-type draft-mtp \
  --host 127.0.0.1 --port 8081 --jinja -a qwen
```

- Adjust `--n-cpu-moe` to the VRAM; see `backends.md`.
- Confirm `http://127.0.0.1:8081/health` returns ok and `/v1/models` shows the alias (`qwen`).
- A CUDA/Metal build is required; a CPU-only build will ignore `-ngl`.

### 2.2 Start anthropic-proxy

`.env`:

```env
ANTHROPIC_PROXY_UPSTREAM_URL=http://127.0.0.1:8081/v1/chat/completions
ANTHROPIC_PROXY_UPSTREAM_API_KEY=dummy
ANTHROPIC_PROXY_DEFAULT_MODEL=qwen
ANTHROPIC_PROXY_TOOL_FORMAT=native
ANTHROPIC_PROXY_FORCE_MODEL=1
ANTHROPIC_PROXY_LISTEN_ADDR=127.0.0.1:8787
ANTHROPIC_PROXY_REQUEST_TIMEOUT_SEC=600
ANTHROPIC_PROXY_LOG_LEVEL=info
```

- `UPSTREAM_API_KEY` is required by the proxy even when the local server does not check it; use `dummy`.
- `TOOL_FORMAT=native` for native tool calling; `xml` fallback if tool calls fail.
- Start from the directory containing `.env`.
- Verify `http://127.0.0.1:8787/health` returns ok.

### 2.3 Start Claude Code through the proxy

Windows `.bat`:

```bat
@echo off
chcp 65001 >nul
set "ANTHROPIC_BASE_URL=http://127.0.0.1:8787"
set "ANTHROPIC_API_KEY=anything"
set "ANTHROPIC_AUTH_TOKEN=anything"
set "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1"
claude --model claude-sonnet-4-6 %*
```

Unix:

```bash
ANTHROPIC_BASE_URL=http://127.0.0.1:8787 \
ANTHROPIC_API_KEY=anything \
ANTHROPIC_AUTH_TOKEN=anything \
CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1 \
claude --model claude-sonnet-4-6
```

- `/v1/models` advertises Claude-style IDs; `FORCE_MODEL=1` maps them to the local model.
- `claude-sonnet-4-6` is a safe model ID to use with this proxy; the local model still does the work.
- Keep the normal `claude` command untouched by using a wrapper or a shell function with scoped env vars.

## 3. Wrapper patterns

### Bash/zsh alias

```bash
alias claude-local='ANTHROPIC_BASE_URL=http://127.0.0.1:8787 ANTHROPIC_API_KEY=anything ANTHROPIC_AUTH_TOKEN=anything CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1 claude --model claude-sonnet-4-6'
```

### PowerShell function (save/restore env)

```powershell
function claude-local {
    $oldToken = $env:ANTHROPIC_AUTH_TOKEN
    $oldKey   = $env:ANTHROPIC_API_KEY
    $oldUrl   = $env:ANTHROPIC_BASE_URL
    $env:ANTHROPIC_AUTH_TOKEN = "anything"
    $env:ANTHROPIC_API_KEY    = "anything"
    $env:ANTHROPIC_BASE_URL   = "http://127.0.0.1:8787"
    try { claude --model claude-sonnet-4-6 @args }
    finally {
        $env:ANTHROPIC_AUTH_TOKEN = $oldToken
        $env:ANTHROPIC_API_KEY    = $oldKey
        $env:ANTHROPIC_BASE_URL   = $oldUrl
    }
}
```

Do not use a PowerShell function that sets `$env:` without restoring it; the variables persist in the session and the normal `claude` will silently use the local proxy.

## 4. Context, tools, permissions

- Claude Code's system prompt + tool definitions ~20K tokens. Use 32K context; 4K default fails.
- Tool calling: Qwen3.6, Gemma 4, gpt-oss:20b support native tools. TranslateGemma is not a coding/tool model.
- `TOOL_FORMAT=native` first; switch to `xml` only if tool calls fail.
- Do not use `--dangerously-skip-permissions` as a default. It removes approval gates for arbitrary shell commands.
- `claude -p` (headless) may hang on tool-permission confirmation without a TTY. Prefer interactive `claude-local`; for automation, configure allowed tools/permissions explicitly.
- Local inference is private, but Claude Code itself may still make network calls (updates, telemetry, web search). Do not claim "100% offline" unless those are disabled.

## 5. Verification

1. Model server health: `curl http://127.0.0.1:8081/health`.
2. Proxy health: `curl http://127.0.0.1:8787/health`.
3. Models: `curl http://127.0.0.1:8787/v1/models`.
4. Text: POST `/v1/messages` with a short prompt; expect Anthropic JSON.
5. Tools: POST `/v1/messages` with a simple tool schema; expect a `tool_use` block.
6. Claude Code: ask "你好"; then ask it to read a small file.
7. Normal `claude` still uses Anthropic.
8. Stop/restart releases VRAM.

## 6. Team mode: LiteLLM in front of vLLM/SGLang

For two or more concurrent users, do not put anthropic-proxy in front of a single-user llama.cpp process. Serve the model with a batched backend and let LiteLLM provide the Anthropic-facing endpoint and per-user keys:

```text
Claude Code -> LiteLLM :8787 (/v1/messages) -> vLLM/SGLang :8000 (/v1/chat/completions)
```

Minimal `litellm-config.yaml`:

```yaml
model_list:
  - model_name: claude-sonnet-4-6
    litellm_params:
      model: hosted_vllm/qwen
      api_base: http://127.0.0.1:8000/v1
      api_key: dummy
litellm_settings:
  drop_params: true
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
```

- Give each user a virtual key; do not share the master key. Set budgets/rate limits per key.
- Keep LiteLLM on `127.0.0.1:8787` or behind the team's auth gateway; do not expose it directly to the LAN.
- Set `ANTHROPIC_BASE_URL=http://127.0.0.1:8787` (no `/v1`).
- Verify `/v1/messages` with a tool schema before rolling out; LiteLLM's Anthropic compatibility varies by version.
- If LiteLLM's tool translation is unreliable, put `claude-code-router` in front for Anthropic↔OpenAI and keep LiteLLM for keys/quotas.
