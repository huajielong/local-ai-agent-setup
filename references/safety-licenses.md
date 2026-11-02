# Safety, Privacy, and Licenses

## 1. Licensing

| Component | Typical license | Redistribution |
|---|---|---|
| Qwen3.6 / Qwen3.5 | Apache 2.0 | Allowed with license/notice |
| Qwen3.8 | Apache 2.0 (verify model card) | Allowed with license/notice |
| Gemma 4 / TranslateGemma | Gemma Terms of Use | Do not redistribute weights; users must download and accept terms |
| gpt-oss | Apache 2.0 | Allowed with license/notice |
| llama.cpp | MIT | Allowed with license |
| anthropic-proxy | MIT | Allowed with license |
| LM Studio | Proprietary terms | Do not redistribute the app |
| Claude Code | Anthropic terms | Users install and accept terms themselves |

Rules:
- Do not bundle model weights into a handover package without checking the license.
- Prefer `ollama pull` / official Hugging Face downloads on the target machine.
- Keep license files and source links with redistributed binaries.
- Verify SHA-256 for downloaded binaries when the project publishes checksums.

## 2. Security

- Bind model servers and proxies to `127.0.0.1`, not `0.0.0.0`.
- If LAN access is required, use a VPN/SSH tunnel and a client key; understand the exposure.
- Do not run agents with `--dangerously-skip-permissions` by default.
- Review tool calls and file edits before approving; local models make mistakes.
- Do not paste secrets, credentials, or private data into prompts; local logs/terminal history may retain them.
- Install binaries from official releases; verify signatures/checksums where available.
- Keep the OS, GPU driver, and runtime updated.

## 3. Privacy

- Local inference keeps model input on the machine.
- The agent shell (Claude Code) may still make network calls for updates, telemetry, web search, or model discovery.
- "100% offline" requires disabling those features and verifying with network monitoring.
- Shared logs/screen recordings can leak prompts; redact before sharing.

## 4. Honest expectations

- Local models are not cloud frontier models. Tool calling, long-horizon agents, and instruction following are weaker, especially at 4B–12B.
- 12GB VRAM cannot run two large models at once; TTS/vision apps compete for the same memory.
- Quantization is a trade-off: Q4_K_M is the practical default; Q2/IQ2 can break tool calls.
- Hardware tiers are guidance, not guarantees; measure on the target machine.

## 5. Handover package checklist

- [ ] Official binaries with licenses/checksums
- [ ] No model weights unless the license allows redistribution
- [ ] No API keys, accounts, or personal paths
- [ ] Commands to pull models from official sources
- [ ] Security notes (localhost, no bypass, no secrets)
- [ ] Verification checklist and support boundary
