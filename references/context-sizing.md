# Context sizing

Claude Code's system prompt plus tool definitions are roughly 20K tokens before the user types anything. Under-sizing the context is the most common reason a working local setup dies mid-session with:

```text
400 upstream: request (45949 tokens) exceeds the available context size (32768 tokens), try increasing it
```

and why `/compact` fails with exactly the same error — the compaction request carries the whole transcript, so it overflows too.

Do not hardcode 32K. Derive the context from the model's KV footprint and the machine's VRAM, then derive the auto-compact window from the context.

## 1. Three numbers that must stay consistent

| Number | Where it lives | What it controls |
|---|---|---|
| Native max context | model metadata (`ollama show <tag>` → context length; GGUF `*.context_length`) | hard ceiling; asking for more is silently capped |
| Server context | llama.cpp `-c` / Ollama `OLLAMA_CONTEXT_LENGTH` / vLLM `--max-model-len` | what the server actually allocates |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | the `env` block of the `--settings` JSON | when Claude Code decides to compact |

Rule: `auto_compact < server_ctx <= native_max`.

The classic failure is `auto_compact = 100000` copied from a cloud model while `server_ctx = 32768`: compaction never fires, and by the time it would, the request is already over the limit.

**Claude Code clamps `CLAUDE_CODE_AUTO_COMPACT_WINDOW` to a floor of 100000** (it emits a warning when you ask for less). Consequence: on a server context below ~110K, auto-compaction cannot fire no matter what you set. Either size the context to at least 128K, or accept manual `/compact` at ~50–60% of the context. There is no settings-file workaround.

## 2. Compute the KV cache per token

```text
kv_bytes_per_token = block_count × head_count_kv × key_length × (bytes_K + bytes_V)
```

- Read `block_count`, `attention.head_count_kv`, `attention.key_length`, `attention.value_length` from the GGUF header (`scripts/gguf-kv-budget.py` does this).
- `bytes per element`: f16 = 2, q8_0 ≈ 1.0625, q4_0 ≈ 0.5625. `-ctk` and `-ctv` can differ.
- If `key_length`/`value_length` are absent, use `embedding_length / head_count`.

Worked example — Qwen3.6-35B-A3B Q4_K_M, 41 layers, 2 KV heads, key/value length 256, `-ctk q8_0 -ctv q8_0`:

```text
41 × 2 × 256 × (1.0625 + 1.0625) = 44,608 bytes ≈ 43.6 KB/token
```

| Context | KV cache |
|---|---|
| 32K | 1.4 GB |
| 64K | 2.8 GB |
| 96K | 4.2 GB |
| 128K | 5.6 GB |
| 256K | 11.2 GB |

The model advertises 256K, but on a 12GB card the KV cache alone would consume the whole GPU.

## 3. Budget against VRAM

```text
weights_on_gpu + kv_bytes_per_token × ctx + compute_overhead + reserve <= VRAM_total
```

- `compute_overhead` (CUDA context, graph buffers, MTP draft context): 1–2 GB; measure, do not guess.
- `reserve`: 1–1.5 GB on Windows (desktop compositor), ~0.5 GB on headless Linux, 2–3 GB on macOS.
- Fastest reliable method: load once at 32K, read `nvidia-smi`, then treat the remaining free VRAM as the KV budget and convert it with `kv_bytes_per_token`.

If the KV cache does not fit, in order:

1. **Move one more MoE layer to CPU**: `--n-cpu-moe +1` frees roughly `main_size / block_count` — about 0.5–1 GB per layer for a 20 GB 35B-A3B.
2. **Quantize the KV cache**: `-ctk q8_0 -ctv q4_0` saves ~25%; `q4_0` for both saves ~45%. K is more sensitive than V.
3. **Lower the context** one rung.

More CPU layers cost generation speed. Measured on a 12GB RTX 5070 Ti laptop + 64GB RAM, Qwen3.6-35B-A3B Q4_K_M, MTP on:

| Server context | `--n-cpu-moe` | VRAM used | Generation | Prompt |
|---|---|---|---|---|
| 32K | 24 | 11.2 GB | ~86 tok/s | ~840 tok/s |
| 128K | 30 | 9.7 GB | ~52 tok/s | ~1000 tok/s |

Four times the context for ~40% of the generation speed is usually the right trade for an agent, because prompt throughput and prefix reuse dominate the experience.

## 4. Pick a rung, then set the window

Use a ladder — 32K → 64K → 96K → 128K → 192K → 256K — capped at the native maximum. Take the largest rung that leaves **at least 1 GB free while serving a real long request**, not right after load.

Then, once `server_ctx >= 128K`:

```text
CLAUDE_CODE_AUTO_COMPACT_WINDOW = round_down(server_ctx × 0.76, 1000)
```

Why 0.76: Claude Code starts compaction near 92% of the window, and the compaction request carries the transcript **plus** the system prompt and tool schemas, so anything at or above `server_ctx` cannot work.

| Server context | Auto-compact window |
|---|---|
| 128K | 100000 |
| 192K | 146000 |
| 256K | 195000 |

Below 128K the floor of 100000 applies (see §1) — do not pretend a smaller window fixes it.

## 5. Starting points by tier

| VRAM | Model | Server context | `--n-cpu-moe` | Notes |
|---|---|---|---|---|
| 8 GB + 32 GB RAM | 30B/35B-A3B Q4 | 16–32K | most layers | experiment only; no auto-compact |
| 12 GB | Qwen3.6-35B-A3B Q4 | 128K | 30 of 41 | measured; the Claude Code sweet spot |
| 12 GB | 12–14B dense Q4 | 96–128K | — | weights ~8 GB leave room for KV |
| 16 GB | Qwen3.6-35B-A3B Q4 | 128–192K | 18–24 | |
| 24 GB | Qwen3.6-35B-A3B Q4 | 256K | 0 | full GPU |
| 24 GB | 27B dense Q4 | 64–128K | — | dense KV is larger per token |
| Apple 24–32 GB unified | 12B / 35B-A3B | 64–128K | — | leave 2–3 GB for macOS |

Translation models stay at 2K; nothing about Claude Code applies to them.

## 6. Verify, do not assume

```bash
curl -s http://127.0.0.1:8081/props | jq '.default_generation_settings.n_ctx'
nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader
```

- `n_ctx` must equal the value you set; llama-server caps silently at the model's trained maximum.
- Free VRAM ≥ 1 GB.
- Send one request **larger than the old limit** (a ~40K-token filler is enough) and confirm HTTP 200 plus a plausible `usage.input_tokens`; an error only shows up past the boundary.
- In Claude Code, run a long session and confirm `/compact` succeeds rather than returning the same context error.

## 7. Traps

- `OLLAMA_CONTEXT_LENGTH` does nothing when you run `llama-server` directly. Setting it and seeing no change is expected, not a bug in Ollama.
- Launchers often reuse an already-healthy server without comparing flags. Changing `-c` and restarting the wrapper can leave the old server running; stop first, then start, then check `/props`.
- A model's advertised 256K is a ceiling, not a budget.
- Auto-compact window ≥ server context is always a bug, and Claude Code's 100000 floor makes it the default bug on small-context models.
- Prefix caching makes long contexts usable turn-to-turn, but the first request after startup or compaction pays full prompt processing: at ~1000 tok/s, 128K is about two minutes.
