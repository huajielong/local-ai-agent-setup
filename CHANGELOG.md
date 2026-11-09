# Changelog

## v0.4.2 — 2026-11-09

- Windows wrappers are now generated as a **pair per command**: `<name>.cmd` for PowerShell/cmd and an extensionless `<name>` bash shim for Git Bash/MSYS. MSYS does not append `.cmd` to bare command names, so the previous `.cmd`-only setup failed in Git Bash with `command not found` even when `~/bin` was on PATH.
- New `assets/claude-local.windows-bash.tmpl` with the prepare step, the `--version/-v/--help/-h` skip, and `exec claude ... "$@"`.
- SKILL.md and `references/claude-code-integration.md` now require generating both shims from the same tag/settings and verifying the bare name plus `--version` in PowerShell, cmd, and Git Bash for each `claude-local-<model>`.
- `references/troubleshooting.md` §13 documents the PATHEXT/MSYS symptom and fix.
- Anti-patterns: shipping only `.cmd`; implementing the bash twin as `cmd //c ... "$@"` (quoting breaks on spaces and `-p` arguments).

## v0.4.1 — 2026-11-09

- Per-model auto-compact windows are now generated conditionally. `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is written only when the model's server context can carry the compaction request (`candidate = max(100000, round_down(ctx × 0.76, 1000))`, and `candidate + 20K <= ctx`); otherwise the key is omitted from that model's settings file. This removes the `CLAUDE_CODE_AUTO_COMPACT_WINDOW="25000" ... treats it as the 100k minimum` warning that short-context wrappers (e.g. a 32K Gemma) printed at every launch, without pretending auto-compaction works.
- The settings template now has an optional `{{AUTO_COMPACT_SETTING}}` line, so omission is a first-class outcome. Docs state explicitly that every `claude-local-<model>` derives its own context and window from its own registry entry; models with different context rungs must not share one value.
- `scripts/gguf-kv-budget.py` now prints the derived window for 128K+ contexts and the omit-the-key guidance below that.
- Updated `references/context-sizing.md` (§1 two valid states, §4 decision rule and per-rung table, §6 verification, §7 traps), `references/claude-code-integration.md` (§0 rules, §3.1 multi-model generation, §4), `references/troubleshooting.md`, and SKILL.md (step 4, step 6, heuristics, anti-patterns).

## v0.4.0 — 2026-11-07

- Context sizing is now derived per model instead of hardcoded at 32K. New `references/context-sizing.md`: KV-cache math, VRAM budget, a 32K→256K ladder, how much each MoE layer moved to CPU buys, and the measured 12GB trade-off (32K/`--n-cpu-moe 24` ≈ 86 tok/s vs 128K/`--n-cpu-moe 30` ≈ 52 tok/s).
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is now a template variable and must be `round_down(server_ctx × 0.76, 1000)`. Documented the consequence of Claude Code's 100000 floor: below ~110K server context auto-compaction can never fire, and `/compact` overflows with the same error as a normal turn.
- New optional helper `scripts/gguf-kv-budget.py` (stdlib only) reads GGUF metadata and prints KV/token, the context ladder, and a suggested context from measured free VRAM.
- Docs updated to stop presenting 32K as the target: SKILL.md plan template, verification, tuning order, heuristics and anti-patterns; model-matrix, performance-tuning, backends, troubleshooting, claude-code-integration.
- Launcher guidance: store context + offload per model profile and generate `-c` and the auto-compact window from one number; reuse detection that compares only the model path will silently keep an old `-c`.

## v0.3.1 — 2026-11-06

- Fix Claude Code 2.1.x with strict chat templates: Claude Code can send environment context as mid-conversation `role:"system"` messages, which Qwen/llama.cpp templates reject with `500 ... System message must be at the beginning`. Document a sanitizer relay (public 8787 → anthropic-proxy 8788) that hoists those messages into the top-level `system` prompt; the local launcher starts it automatically.
- Troubleshooting and Claude Code integration references updated with the symptom, cause, port layout, and replay-based verification.

## v0.3.0 — 2026-11-06

- Multi-model local launchers: generate a registry from Ollama, one `claude-local-<name>` wrapper per installed model, per-model settings, and a management command (`-List/-Refresh/-Stop/-Switch`).
- Single-active-model switching on one GPU: stop the previous llama-server/proxy, start the target on fixed ports, reuse when the target blob and proxy model ID match.
- Model profiles: MoE CPU offload, full GPU with mmproj, generic auto-fit; mmproj opt-in based on VRAM.
- Active-session detection with `-Force` override; fixed upstream alias (`-a local`) and full Ollama tag as the client-visible model ID/display name.
- Laptop tuning: vendor Control Center Quiet mode can cut throughput 2–4×; Performance mode plus `-t`/P-core affinity restored 60–100 tok/s on the 5070 Ti laptop. `nvidia-smi` clock locks do not help while the vendor mode is Quiet.
- Add `references/performance-tuning.md`: cross-platform power/vendor modes, backend offload, CPU affinity/thread tuning, quantization/context tradeoffs, benchmark method, and traps. Add selection guidance for multi-GPU/workstation and use-case-based model choice; update triggers for 端侧模型/性能调优/多 GPU/工作站.

## v0.2.0 — 2026-11-06

- Fix: Claude Code settings files (`~/.claude/settings.json`) have higher precedence than shell environment variables. Document the preflight check and default the `claude-local` wrapper to `claude --settings <dedicated.json>` so an existing online-provider configuration cannot silently override local routing.
- Add `assets/claude-local.settings.json.tmpl`; wrapper templates now use `--settings`.
- Troubleshooting: wrapper still uses the online provider, model rejection after `--settings`, and the 100K auto-compact floor.
- Model display: set the proxy's visible model IDs to the exact backend name (for example the Ollama tag) and `*_MODEL_NAME` to the label to display (friendly name or the exact backend name) so Claude Code shows the local model instead of its built-in "Sonnet 4.6" label; launch with `--model <that-id>`.
- Windows launch pitfalls: CRLF-only batch files, stale terminal PATH, and `start /D` mangling from Git Bash.
- Speed measurement methodology: sustained vs short-run peak, MTP acceptance, GPU/CPU state, and log comparison.

## v0.1.0 — 2026-11-02

- Initial public release.
- Cross-platform hardware detection (Windows PowerShell, macOS/Linux bash).
- Model matrix and tier selection for 8GB–48GB VRAM, Apple Silicon, AMD, and CPU-only.
- Backends: Ollama, llama.cpp, LM Studio, MLX, vLLM, SGLang, LiteLLM, anthropic-proxy.
- Claude Code integration for single-user and team/multi-user deployments.
- Functional eval: 28/28 targeted assertions (iteration-3); 23/23 all-case assertions (iteration-2).
- Trigger eval: 14/14 queries; 8 positives 24/24, 6 negatives 0/18.
