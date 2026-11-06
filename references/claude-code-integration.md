# Claude Code Integration

Claude Code speaks the Anthropic Messages API. Local servers usually speak OpenAI Chat Completions. There are three ways to bridge them: Ollama's native API for small models, anthropic-proxy for one user on llama.cpp, and LiteLLM in front of a batched server for a team.

## 0. Preflight: settings files beat shell environment variables

Before writing a wrapper, read the user's Claude Code settings:

- `~/.claude/settings.json` (user)
- `<project>/.claude/settings.json` (project)
- `~/.claude/settings.local.json` (local overrides)

If any of them contains an `env` block with `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, or `ANTHROPIC_DEFAULT_*_MODEL`, then **shell environment variables will not override those values**. A wrapper that only does `export`/`set` still sends requests to the provider configured in the settings file, and the user sees "it is still using the online model".

Diagnose with one request: run `claude --model <local-only-id> -p "hi"`. If the online API rejects the model ID, or `/status` still shows the online base URL, the shell values were ignored.

Fix: put the local routing in a dedicated JSON file and pass it with `--settings`, which has higher precedence than the user settings file and applies only to that invocation:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8787",
    "ANTHROPIC_API_KEY": "anything",
    "ANTHROPIC_AUTH_TOKEN": "anything",
    "ANTHROPIC_MODEL": "claude-sonnet-4-6",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-6",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-sonnet-4-6",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-sonnet-4-6",
    "CLAUDE_CODE_SUBAGENT_MODEL": "claude-sonnet-4-6",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "100000",
    "API_TIMEOUT_MS": "900000"
  }
}
```

```bat
claude --settings "C:\path\claude-local.settings.json" --model claude-sonnet-4-6 %*
```

```bash
claude --settings "/path/claude-local.settings.json" --model claude-sonnet-4-6 "$@"
```

Rules:

- Override every `ANTHROPIC_DEFAULT_*_MODEL` and `CLAUDE_CODE_SUBAGENT_MODEL` that the user's settings define; otherwise background tasks and subagents keep using the online model IDs.
- Override `CLAUDE_CODE_AUTO_COMPACT_WINDOW` if the user's settings define it. It must be **below the server context**, because the compaction request carries the whole transcript plus the ~20K system prompt. Derive it as `round_down(server_ctx × 0.76, 1000)`; see `context-sizing.md` §4.
- Claude Code clamps the window to a floor of 100000 and warns when you ask for less. A value copied from a 1M-context online model will never trigger compaction on a 32K local model — and neither will a correctly small value, because of the floor. On a server context below ~110K, auto-compaction cannot work; size the context to 128K+ or tell the user to `/compact` manually at ~50–60% of the limit.
- `API_TIMEOUT_MS=900000` accommodates slow first-token latency from local prompt processing.
- The dedicated file is not written back; normal `claude` keeps using its original provider.

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
- If §0 found a conflicting `env` block in a settings file, the `export`/`set` examples above are ignored; use `claude --settings <dedicated.json>` there too.
- Do **not** append `/v1` to `ANTHROPIC_BASE_URL`; Claude Code appends `/v1/messages` itself.
- Set a context of at least 32K (`OLLAMA_CONTEXT_LENGTH=32768`); 4K is unusable for Claude Code. Ollama has no MoE expert offload in stable 0.40.x, so a big model may not afford 128K — in that case tell the user auto-compaction will not fire below ~110K and they must `/compact` manually (`context-sizing.md`).
- Big models in Ollama can be very slow (no MoE expert offload); this mode is best for small/medium models.

## 2. Performance mode: llama.cpp + anthropic-proxy

Use when the user wants a responsive coding agent.

### 2.1 Start llama.cpp

```bash
llama-server -m <model.gguf> \
  --n-cpu-moe 30 -ngl 999 \
  -c 131072 -fa on -ctk q8_0 -ctv q8_0 \
  --load-mode none -t 16 --parallel 1 \
  --reasoning-budget 0 --spec-type draft-mtp \
  --host 127.0.0.1 --port 8081 --jinja -a qwen
```

- `-c` and `--n-cpu-moe` are a pair, not independent knobs: size the context first (`context-sizing.md`), then offload enough experts to fit it. The numbers above are the measured 12GB/35B-A3B pair (128K, ~52 tok/s); do not copy them to a different model or VRAM size.
- Confirm `http://127.0.0.1:8081/health` returns ok and `/v1/models` shows the alias (`qwen`).
- A CUDA/Metal build is required; a CPU-only build will ignore `-ngl`.

### 2.2 Start anthropic-proxy

`.env`:

```env
ANTHROPIC_PROXY_UPSTREAM_URL=http://127.0.0.1:8081/v1/chat/completions
ANTHROPIC_PROXY_UPSTREAM_API_KEY=dummy
ANTHROPIC_PROXY_DEFAULT_MODEL=qwen
ANTHROPIC_PROXY_DEFAULT_SONNET_MODEL=qwen
ANTHROPIC_PROXY_DEFAULT_OPUS_MODEL=qwen
ANTHROPIC_PROXY_DEFAULT_HAIKU_MODEL=qwen
ANTHROPIC_PROXY_DEFAULT_SONNET_MODEL_NAME=Qwen3.6-35B-A3B (local)
ANTHROPIC_PROXY_DEFAULT_OPUS_MODEL_NAME=Qwen3.6-35B-A3B (local)
ANTHROPIC_PROXY_DEFAULT_HAIKU_MODEL_NAME=Qwen3.6-35B-A3B (local)
ANTHROPIC_PROXY_TOOL_FORMAT=native
ANTHROPIC_PROXY_FORCE_MODEL=1
ANTHROPIC_PROXY_LISTEN_ADDR=127.0.0.1:8787
ANTHROPIC_PROXY_REQUEST_TIMEOUT_SEC=600
ANTHROPIC_PROXY_LOG_LEVEL=info
```

- `UPSTREAM_API_KEY` is required by the proxy even when the local server does not check it; use `dummy`.
- `TOOL_FORMAT=native` for native tool calling; `xml` fallback if tool calls fail.
- To make Claude Code display the local model instead of a built-in Claude label, set the visible `DEFAULT_SONNET/OPUS/HAIKU_MODEL` IDs to the exact backend model name (for example the Ollama tag `qwen3.6:35b-a3b-mtp-q4_K_M`) and `..._MODEL_NAME` to the label to display — a human-readable name (`Qwen3.6-35B-A3B`) or the exact backend name if the user wants the full name shown — then launch with `--model <that-id>`. With all three IDs equal, `/v1/models` returns a single entry. With built-in IDs such as `claude-sonnet-4-6`, Claude Code always renders "Sonnet 4.6" even though the request is local.
- Three names are in play: the client-visible model ID (what Claude Code sends and displays), the `/v1/models` `display_name`, and the upstream model (`ANTHROPIC_PROXY_DEFAULT_MODEL` / llama.cpp `-a`). `FORCE_MODEL=1` maps any client ID to the upstream model, so the upstream alias can stay `qwen` while the client sees the Ollama tag. Model IDs containing `:` (Ollama tags) are accepted.
- Restart the proxy after editing `.env`; `/v1/models` reflects the new IDs and display names.
- Start from the directory containing `.env`.
- Verify `http://127.0.0.1:8787/health` returns ok.

### 2.3 Start Claude Code through the proxy

Preferred — dedicated settings file plus `--settings`. This works even when the user's `~/.claude/settings.json` already routes `claude` to an online provider (see §0):

```bat
claude --settings "C:\path\claude-local.settings.json" --model claude-sonnet-4-6 %*
```

```bash
claude --settings "/path/claude-local.settings.json" --model claude-sonnet-4-6 "$@"
```

Use `assets/claude-local.settings.json.tmpl` as the starting point.

Plain environment variables work **only if** no settings file defines a conflicting `env` block:

```bat
@echo off
chcp 65001 >nul
set "ANTHROPIC_BASE_URL=http://127.0.0.1:8787"
set "ANTHROPIC_API_KEY=anything"
set "ANTHROPIC_AUTH_TOKEN=anything"
set "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1"
claude --model claude-sonnet-4-6 %*
```

```bash
ANTHROPIC_BASE_URL=http://127.0.0.1:8787 \
ANTHROPIC_API_KEY=anything \
ANTHROPIC_AUTH_TOKEN=anything \
CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1 \
claude --model claude-sonnet-4-6
```

- `/v1/models` advertises Claude-style IDs; `FORCE_MODEL=1` maps them to the local model.
- `claude-sonnet-4-6` is a safe model ID to use with this proxy; the local model still does the work.
- Keep the normal `claude` command untouched. `--settings` applies only to that invocation.

### 2.4 Mid-conversation system messages (Claude Code 2.1.x)

Claude Code 2.1.x can send environment context and environment updates as `role: "system"` entries **inside** the `messages` array, not only in the top-level `system` field. Strict chat templates (Qwen and many other llama.cpp `--jinja` templates) require every system message to be the first message and otherwise return:

```text
500 upstream: Jinja Exception: System message must be at the beginning.
```

The first turn may succeed; the failure starts after a tool call or an environment update, and then every retry of that session fails.

Fix: insert a small sanitizer between Claude Code and anthropic-proxy:

```text
Claude Code -> 127.0.0.1:8787 (sanitizer) -> 127.0.0.1:8788 (anthropic-proxy) -> 127.0.0.1:8081 (llama.cpp)
```

The sanitizer parses the JSON request and moves every mid-list `system` message into the top-level `system` prompt (append it as a text block; create the field if absent), removes those messages from `messages`, and forwards the rewritten body. Keep the client-facing URL in the settings file at 8787; the proxy listens on an internal port. Use `assets/chat-sanitizer.js` as the starting point (Node, no dependencies; `SANITIZER_LISTEN_PORT`/`SANITIZER_UPSTREAM_PORT`, defaults 8787/8788). Log one line per rewrite (`hoisted N ...`), and verify by replaying the exact failed request: it must return 200. Restarting the Claude Code session alone is a temporary workaround — the next environment update can trigger it again.

## 3. Wrapper patterns

Use a dedicated settings file; it scopes the override to the invocation and survives an existing online-provider configuration.

### Bash/zsh alias

```bash
alias claude-local='claude --settings "$HOME/.claude/claude-local.settings.json" --model claude-sonnet-4-6'
```

### PowerShell function

```powershell
function claude-local {
    claude --settings "$env:USERPROFILE\.claude\claude-local.settings.json" --model claude-sonnet-4-6 @args
}
```

If no settings file exists and no `env` block is configured, an environment-scoped wrapper also works. Never mutate `$env:` without restoring it; the variables persist in the session and normal `claude` will silently use the local proxy.

### 3.1 Multiple local models on one GPU

When several Ollama models are installed, generate a registry and one wrapper per model instead of hand-editing ports:

- Scan `GET http://127.0.0.1:11434/api/tags`; resolve each model's GGUF/mmproj/draft from the Ollama manifest by layer mediaType (`application/vnd.ollama.image.model`, `.projector`, `.draft`). Do not infer the projector from FROM order.
- Write a registry (tag, command, blobs, profile, capabilities) and per-model settings JSON.
- Generate `claude-local-<slug>` wrappers. The wrapper runs the dispatcher with `-Prepare`, then `claude --settings <per-model-settings> --model <full-tag> %*`; keep the final call in the `.cmd` so `-p`, `--resume`, `--version` pass through unchanged.
- Store context and offload per model profile (`-c`, `--n-cpu-moe`) and generate the per-model settings file from the same number, so `-c` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` cannot drift. Reuse detection that only compares the model path and alias will silently keep an old `-c`; compare the full argument list, or require an explicit restart after `-Refresh`.
- Only one large model can be resident on a 12GB card. The dispatcher stops the previous llama-server/proxy and starts the target on the same ports (8081; public 8787 for the sanitizer; internal 8788 for anthropic-proxy) with a fixed upstream alias (`-a local`). The proxy's `DEFAULT_MODEL=local`, visible IDs/names = full Ollama tag, `FORCE_MODEL=1`.
- Reuse a running server only if its command line contains the target main blob and `-a local`, and `/v1/models` returns the target tag. Otherwise switch.
- Detect active local Claude Code sessions (command line contains the per-model settings path); abort unless `-Force`.
- Profiles: MoE (`--n-cpu-moe`), full GPU + mmproj, generic auto-fit. Enable an mmproj only when VRAM allows; a Qwen 35B mmproj can push a 12GB card over the limit.
- Management command: `claude-local-models -List / -Refresh / -Stop / -Switch <tag> -Force`. After `ollama pull`, run `-Refresh` to add the new wrapper.
- On laptops, check the vendor performance mode (Performance/Entertainment/Quiet; e.g. Clevo Fn+3) before tuning. Pin llama-server to P-cores and tune `-t`; on an 8-P-core CPU, 8 threads plus affinity can beat 16 threads. Vendor Quiet mode can cut throughput by 2–4× and is not fixed by `nvidia-smi` clock locks.

## 4. Context, tools, permissions

- Claude Code's system prompt + tool definitions ~20K tokens. 32K is the floor, 4K fails, and anything below ~110K defeats auto-compaction (see §0). Size with `context-sizing.md`; 128K is the practical target for agent work.
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
7. In `claude-local`, `/status` shows the local base URL; normal `claude` still uses its original provider.
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
- Set `ANTHROPIC_BASE_URL=http://127.0.0.1:8787` (no `/v1`). If the user's settings file defines `env`, put this in a dedicated `--settings` file instead.
- Verify `/v1/messages` with a tool schema before rolling out; LiteLLM's Anthropic compatibility varies by version.
- If LiteLLM's tool translation is unreliable, put `claude-code-router` in front for Anthropic↔OpenAI and keep LiteLLM for keys/quotas.
