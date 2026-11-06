# Changelog

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
