# Troubleshooting

## 1. First diagnostics to collect

```text
OS and version
nvidia-smi (or system_profiler / rocm-smi)
Total RAM and free disk
ollama list
ollama ps
Model server health endpoint
Proxy health endpoint
Last 20 lines of each server window/log
```

## 2. Windows: `ollama list` empty or `bad manifest`

Ollama 0.40.x on Windows can fail to read manifests through a directory junction or volume mount point:
`The system cannot find the path specified`.

Fix:
- Keep the model directory a plain drive-letter path, e.g. `D:\Ollama\models`.
- Point Ollama's app setting / `OLLAMA_MODELS` at that path.
- Restart Ollama and check `%LOCALAPPDATA%\Ollama\server.log` for `OLLAMA_MODELS`.
- Do not route the model directory through a junction on 0.40.x unless the bug is fixed in a newer version.

## 3. GPU not detected / CPU-only speed

- `llama-server --list-devices` must show `CUDA0`, `Metal`, or `Vulkan0`.
- A binary built without GPU support ignores `-ngl`; download the CUDA/Metal/Vulkan build.
- On Windows, the CUDA runtime DLLs may live in Ollama's `cuda_v13` folder; add it to `PATH` or place the DLLs next to the server.
- Check the driver (`nvidia-smi`) and the CUDA version the build expects.
- On AMD, confirm ROCm support for the GPU; otherwise use Vulkan or Ollama.

## 4. OOM / model won't load

- Close other GPU apps: TTS, ChatGPT/Codex desktop, NVIDIA Broadcast, browsers with GPU acceleration.
- Lower context: 32K → 16K → 8K.
- MoE: increase `--n-cpu-moe` (more experts on CPU, less VRAM).
- Use a smaller quant or a smaller model; do not force Q8 on 12GB.
- Only one big model at a time.
- Windows may reserve VRAM for the desktop; leave 0.5–1GB headroom.

## 5. Model loads but is very slow

- Confirm the backend: Ollama may be 5–10× slower than llama.cpp for new MoE architectures.
- Check `ollama ps` for CPU/GPU split; a high CPU share means VRAM is insufficient.
- Check `nvidia-smi` utilization/power/clocks; laptop power modes and thermals matter.
- Lower context; reduce background GPU apps.
- For MoE, tune `--n-cpu-moe`; too low causes VRAM thrash, too high puts too much on CPU.
- First Claude Code request is slow because of the ~20K-token system prompt; later turns are faster.

## 6. Proxy fails to start

- `ANTHROPIC_PROXY_UPSTREAM_API_KEY is required` → add `ANTHROPIC_PROXY_UPSTREAM_API_KEY=dummy` to `.env`.
- Proxy must run from the directory containing `.env`, or receive the env vars directly.
- Check the listen port (`8787`) is free.
- Check the upstream URL is the full `/v1/chat/completions` endpoint.
- macOS/Linux: make the binary executable (`chmod +x`).

## 7. Claude Code errors

- `Invalid model name`: use `claude-sonnet-4-6` with anthropic-proxy (it maps to the local model), or the exact local model name with Ollama native mode.
- Context errors: set 32K; 4K default is too small.
- Tool calls fail: switch `TOOL_FORMAT` between `native` and `xml`; test with a simple tool.
- Headless `claude -p` hangs: permission confirmation without a TTY; use interactive mode or configure permissions.
- `claude-local` still uses the online provider/model: `~/.claude/settings.json` (or project settings) defines an `env` block, and it wins over shell environment variables. Read the settings file and launch with `claude --settings <dedicated.json>`; `export`/`set` cannot override it. Confirm with `/status`.
- Model ID rejected by the online API after adding `--settings`: the settings file is read but `ANTHROPIC_BASE_URL` is missing or wrong. Put the base URL and model IDs in the same file.
- `CLAUDE_CODE_AUTO_COMPACT_WINDOW` warning: values below 100000 are clamped to 100000. Set 100000 or override the inherited value; on a 32K local model, long sessions can overflow before auto-compaction.
- Claude Code shows "Sonnet 4.6" / "Opus" although requests are local: the proxy advertises built-in Claude IDs, and Claude Code renders its own label for known IDs. Set `ANTHROPIC_PROXY_DEFAULT_*_MODEL` to the local alias (for example `qwen`) and `ANTHROPIC_PROXY_DEFAULT_*_MODEL_NAME` to a local name, then launch with `--model qwen`; confirm with `/v1/models`.
- Normal `claude` starts using local proxy: environment variables leaked; prefer a `--settings` wrapper, or clear `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`.
- Base URL: do **not** append `/v1` to `ANTHROPIC_BASE_URL`.

## 8. Model blob path/hash changed

- Scripts that hardcode `sha256-...` blob names break when a model is re-pulled.
- Run `ollama show <model> --modelfile`; take the `FROM` path(s).
- Update the script config. For Gemma, the second `FROM` is the vision projector.
- Alternatively, resolve the path at runtime instead of hardcoding.

## 9. Chinese/Unicode garbled in terminal

- Usually a terminal encoding issue, not a model issue.
- Use the browser UI, `chcp 65001` on Windows, or write output to a UTF-8 file.
- Do not judge model quality from a garbled console.

## 10. Audio/video

- Image input is the most reliable multimodal path.
- Video support depends on the runtime/version; sample frames if needed.
- Audio support varies; use Whisper/faster-whisper for transcription if the local multimodal stack is unreliable.

## 11. Disk / downloads

- Model downloads are 2–30GB; check free space before starting.
- Ollama downloads are resumable; do not interrupt.
- Keep at least 20GB free for runtime/cache.
- Do not package model weights for redistribution; download from official sources.

## 12. When to escalate

Escalate to a different backend or a smaller model if:
- The model cannot fit with 0.5GB VRAM headroom after tuning.
- The user's GPU is unsupported by the runtime.
- Tool calling is unreliable at the required precision.
- The machine has <16GB RAM and the user needs an agent; a cloud API may be the honest recommendation.

## 13. Windows wrappers and terminal PATH

- **LF-only `.bat`/`.cmd` files break cmd.exe parsing**: symptoms include fragments such as `'ude' is not recognized` or "The filename, directory name, or volume label syntax is incorrect." Save batch files with CRLF line endings and keep comments ASCII; prefer UTF-8 without BOM.
- **A new `.cmd` is not found in an already-open PowerShell/cmd window**: the process PATH may be stale. Put the shim in a directory already on PATH (for example the npm global bin where `claude.cmd` lives), add a PowerShell profile function that calls the `.bat` by absolute path, or open a new terminal. Verify with `Get-Command <name>` / `where <name>`.
- **Do not pass `/D` to `start` from Git Bash**: MSYS path conversion mangles it. Use PowerShell `Start-Process -WorkingDirectory ...`, or a `.bat` that `cd /d` to the right directory.
- After editing a proxy `.env`, restart the proxy and re-check `/health` and `/v1/models`; do not assume the running process reloaded it.

## 14. Speed is lower than expected

See `references/performance-tuning.md` for the full cross-platform checklist.

1. Measure generation and prompt separately from llama.cpp's `timings`; run at least 3 times with ≥250 output tokens and report the median/sustained range.
2. A short 128-token, highly predictable prompt can be a best-case peak (MTP acceptance >80%). Do not quote it as the sustained speed.
3. Check the MTP counters: `draft_n`, `draft_n_accepted`, `mean len`. Low acceptance reduces the benefit.
4. Check the runtime state during generation:
   - `nvidia-smi --query-gpu=power.draw,clocks.sm,utilization.gpu,pstate --format=csv -l 1`
   - CPU utilization and frequency; on 12GB cards with `--n-cpu-moe`, the CPU is often the bottleneck while the GPU sits at low power.
   - AC power, vendor performance mode, NVIDIA power management, MUX/hybrid mode.
5. Compare logs: `n_ctx`, `n_threads`, `graphs reused`, `graph reallocs`, model path and `--n-cpu-moe`. Identical logs but different tok/s point to the machine's power/thermal state, not the config.
6. Free VRAM/RAM and close other GPU/CPU apps; reduce context or adjust `--n-cpu-moe` if needed.
7. On laptops, do not assume `nvidia-smi` clock locks or persistence mode are available. Check the vendor Control Center performance mode, NVIDIA power management, MUX/hybrid mode, and background GPU apps. The same model and flags can run at different GPU clocks/power states across sessions; compare P-state, clocks, and power, not just tok/s.
8. Vendor power mode can dominate everything: Clevo/Colorful Control Center has Performance/Entertainment/Quiet modes (often Fn+3). Quiet can cut a 60–100 tok/s config to ~20–30 tok/s, and `nvidia-smi -lgc` will not help while the vendor mode is Quiet. Check the vendor UI/EC mode first.
9. On CPUs with P-cores and E-cores, pin llama-server to P-cores and tune `-t`: 16 threads on 8 P-cores can be slower than 8 threads plus affinity. The best value is workload-specific; benchmark at least 3 runs.
