# local-ai-agent-setup

检测本机硬件，选一个真正跑得动的本地模型与推理后端，生成 `claude-local` 接入 Claude Code；下载和安装前先给方案。

**状态**：活跃维护 · v0.4.2 · MIT · 非 Anthropic 官方项目。

## 它解决什么问题

本地模型教程常常从“下载 30B 模型”开始，却不问显存、内存、磁盘、用途和供电模式。结果要么跑不起来，要么能跑但慢到没法用。

这个技能反过来：先读硬件，再按档位和用途选型，最后才谈模型参数。

- **8GB 显存**：9B/12B dense Q4；提到 30B/35B-A3B 时明确它只是实验方案，不承诺可用。
- **12GB 显存 + 64GB 内存**：Qwen3.6-35B-A3B 通过 llama.cpp `--n-cpu-moe` 把专家放内存，可跑 Claude Code。
- **24GB+ / 多卡工作站**：27B dense 或 35B-A3B 全 GPU；团队场景用 vLLM/SGLang + LiteLLM。
- **Apple Silicon**：Ollama/MLX/LM Studio，按统一内存选 9B/12B/35B-A3B。
- **无 GPU**：1–4B CPU 模型，明确能力边界，不承诺 Claude-Code 级 agent。

## 适合谁

**适合**：有本地 GPU 或 Apple Silicon、想用 Claude Code 接本地模型；需要在多台机器、不同显卡或工作站上复用同一套检测/选型/调优流程；需要团队本地推理方案。

**不适合**：只想用云端 API；做 CUDA/ROCm 内核开发；纯提示词工程；不愿意在下载/安装前确认。

## 安装

macOS / Linux：

```bash
git clone https://github.com/huajielong/local-ai-agent-setup.git \
  ~/.claude/skills/local-ai-agent-setup
```

Windows PowerShell：

```powershell
git clone https://github.com/huajielong/local-ai-agent-setup.git `
  "$env:USERPROFILE\.claude\skills\local-ai-agent-setup"
```

或者从 [v0.4.2 Release](https://github.com/huajielong/local-ai-agent-setup/releases/tag/v0.4.2) 下载 `local-ai-agent-setup-v0.4.2.skill`，按 Claude Code 的技能安装方式导入。

> [!IMPORTANT]
> 如果 `~/.claude/settings.json` 的 `env` 已指向在线模型（例如 DeepSeek），shell 里的 `ANTHROPIC_BASE_URL` 会被覆盖。技能会生成独立 settings 文件并用 `claude --settings` 启动，不要只 `export`。

## 第一次使用

安装后在 Claude Code 里直接说：

- “我的电脑能跑什么本地大模型？”
- “帮我用 Claude Code 接本地模型，别影响我正常的在线 `claude`”
- “按 Ollama 里已安装的模型生成 `claude-local-<name>`”
- “本地模型速度慢，帮我做性能调优”
- “给团队搭 vLLM + LiteLLM 的本地 Claude Code 代理”
- “把这套本地部署方案做成给别人的安装包”

技能应自动触发；如果没有，确认技能目录在 `~/.claude/skills/` 下，并重启 Claude Code。

触发后它会：只读检测硬件 → 分档并选模型/后端 → 给出含下载量、速度预期和风险的方案 → 你确认后才下载/安装 → 生成入口并跑一次真实请求验证。普通 `claude` 不受影响。

生成后的入口通常长这样（具体名称取决于本机安装的 Ollama 模型）：

```powershell
claude-local                    # 默认模型
claude-local-qwen3.6            # 指定 Ollama 模型
claude-local-gemma4             # 另一个模型
claude-local-models -List       # 查看已生成入口和当前活动模型
claude-local-models -Refresh    # 新装了 Ollama 模型后重新生成入口
claude-local-models -Stop       # 停止本地模型服务，释放显存
```

`claude-local-models -List` 的真实输出示例（模型和 PID 会不同）：

```text
Default: qwen3.6:35b-a3b-mtp-q4_K_M
Command                      Ollama tag                                    Profile      mmproj
claude-local-gemma4          gemma4:12b                                    gemma-full   True
claude-local-qwen3.6         qwen3.6:35b-a3b-mtp-q4_K_M                    qwen-moe     False
Active: qwen3.6:35b-a3b-mtp-q4_K_M (llama PID 31356, proxy PID 38696)
```

- `claude-local` 通过独立 `--settings` 指向本地代理，不会改掉全局配置。
- 12GB 显存一次只常驻一个模型；启动另一个入口会停掉之前的 llama-server/proxy。
- 有活跃本地会话时，切换默认中止；先执行 `claude-local-models -Switch <tag> -Force` 强制切换，再运行目标入口。

**v0.3.1 修复**：Claude Code 2.1.x 可能发送中途 `system` 消息，Qwen/llama.cpp 的 Jinja 模板会报 `System message must be at the beginning`。本地启动器内置 `chat-sanitizer`（客户端 8787 → 代理 8788），转发前自动把这些消息并入顶层 system。

**v0.4.0 变更**：上下文不再写死 32K。按模型 KV 开销和显存预算选出上下文，再由它反推自动压缩窗口。Claude Code 会把 `CLAUDE_CODE_AUTO_COMPACT_WINDOW` 抬到至少 100000，所以服务端上下文低于约 110K 时自动压缩永远不会触发——要么把上下文做到 128K+，要么手动 `/compact`。详见 [`references/context-sizing.md`](references/context-sizing.md)。

**v0.4.1 变更**：`CLAUDE_CODE_AUTO_COMPACT_WINDOW` 改为**按模型条件生成**：只有该模型的服务端上下文撑得起（≥100000 且留出约 20K 系统提示余量）才写入，否则从该模型的 settings 中整体省略。32K/96K 入口不再每次启动打印 25000 低于下限的警告，也不会把 100000 写到撑不下的模型上。每个 `claude-local-<model>` 都按自己的上下文档位计算，互不共用。

**v0.4.2 变更**：Windows 下每个 `claude-local-<model>` 要求生成**两份入口**：`.cmd`（PowerShell/cmd）和 `~/bin` 下的无扩展名 bash shim（Git Bash/MSYS）。MSYS 不会替裸命令补 `.cmd`，只有 `.cmd` 时 Git Bash 会报 `command not found`；技能新增模板与三终端验证清单。

## 核心能力

- **只读硬件检测**：Windows PowerShell / macOS-Linux bash 脚本，读取 OS、CPU、RAM、磁盘、GPU/VRAM、已装工具和 Ollama 模型。
- **模型矩阵**：Qwen3.6-35B-A3B、Qwen3.8-27B、Gemma 4 12B/26B-A4B、TranslateGemma 4B、Qwen3.5-9B/4B、gpt-oss:20b 等，含大小、许可证、适用档位和预期速度。
- **后端选择**：Ollama、llama.cpp、LM Studio、MLX、vLLM、SGLang；单用户和团队并发有明确分支。
- **Claude Code 接入**：Ollama 原生 Anthropic API、llama.cpp + anthropic-proxy、vLLM/SGLang + LiteLLM；生成 `claude-local` 包装脚本，用 `--settings` 隔离配置，不修改正常 `claude`。
- **多模型入口**：按 Ollama 已安装模型生成 `claude-local-<name>`（Windows 同时生成 `.cmd` 与 Git Bash 无扩展名 shim），单 GPU 单模型常驻切换，管理命令 `claude-local-models -List/-Refresh/-Stop/-Switch`。
- **上下文预算**：按 GGUF 的层数/ KV 头/head dim 算出每 token 的 KV 开销，再按显存选 32K→256K 档位，并由上下文反推 `CLAUDE_CODE_AUTO_COMPACT_WINDOW`（撑不起时省略该键，每个模型独立计算）；附 `scripts/gguf-kv-budget.py` 直接算。见 [`references/context-sizing.md`](references/context-sizing.md)。
- **性能调优**：电源/厂商模式、offload、CPU 亲和性、量化/上下文；完整清单见 [`references/performance-tuning.md`](references/performance-tuning.md)。
- **团队/多用户/工作站**：vLLM/SGLang 连续批处理、Tensor Parallel、LiteLLM 虚拟密钥/配额/审计、SSH 隧道/VPN、仅绑 `127.0.0.1`。
- **安全门控**：下载/安装前必须确认；服务只绑 localhost；不默认 `--dangerously-skip-permissions`；尊重模型许可证，不打包权重。

## 模型选择与平台

完整表格见 [`references/model-matrix.md`](references/model-matrix.md)。快速规则：

| 场景 | 优先选择 |
|---|---|
| 编程 / Agent / Claude Code | 支持工具调用、上下文能拉到 128K 的模型；12GB 可用 Qwen3.6-35B-A3B MoE + CPU offload |
| 快速问答 / 多模态 | Gemma 4 12B 等全 GPU 模型 |
| 翻译 | TranslateGemma 4B（GPU/CPU 版本按显存选择） |
| 团队 / 多用户 / 多 GPU | vLLM/SGLang + LiteLLM；按并发吞吐评估，不用单流 tok/s |
| Apple Silicon | Ollama/MLX/LM Studio；按统一内存选 9B/12B/35B-A3B |
| CPU-only | 1–4B 模型；只承诺翻译/问答，不承诺 Claude-Code 级 agent |

**不要按参数规模选模型。** 先看用途和工具调用，再看显存/内存能否放下，最后看速度。

支持的平台与后端：

| 平台 / 硬件 | 推荐后端 | 说明 |
|---|---|---|
| Windows + NVIDIA/AMD | llama.cpp / Ollama / LM Studio | 注意厂商性能模式、P/E 核、MUX、Batch CRLF |
| Linux + NVIDIA | llama.cpp / vLLM / SGLang + LiteLLM | 多 GPU 张量并行、并发吞吐、NUMA/CCD |
| Linux + AMD | ROCm 支持的 llama.cpp / Ollama | 先验证 ROCm 支持；否则 Vulkan/CPU |
| macOS / Apple Silicon | Ollama / MLX / LM Studio | 统一内存；Low Power Mode/thermal 会影响速度 |
| CPU-only | Ollama / llama.cpp | 小模型；能力边界要讲清楚 |

## 性能调优

完整清单见 [`references/performance-tuning.md`](references/performance-tuning.md)。核心顺序：

1. **OS / 厂商电源模式**：笔记本 Control Center 的 Performance/Entertainment/Quiet（Clevo/Colorful 常见 Fn+3）、Windows 电源计划、NVIDIA 控制面板、Linux `powerprofilesctl`、macOS Low Power Mode。
2. **后端 offload**：llama.cpp `-ngl` / `--n-cpu-moe` / flash attention / KV 量化 / 上下文 / MTP；Ollama、LM Studio、vLLM/SGLang 的对应项。
3. **CPU 线程/亲和性**：识别 P-core/E-core/CCD/NUMA，把 llama-server 绑到 P-core，调 `-t`（4/8/12/16 实测）。
4. **量化/上下文**：Q4_K_M、q8 KV；上下文按 KV 预算算出来（见 [`references/context-sizing.md`](references/context-sizing.md)），32K 只是下限。
5. **基准**：至少 3 次、≥250 token，区分短测峰值和持续速度，记录 GPU 时钟/功耗/P-state 和 CPU 负载。

一个真实案例，同一台 RTX 5070 Ti Laptop 12GB、同一个 Qwen3.6-35B-A3B Q4、同一个 32K prompt，只差厂商电源模式和 CPU 调度：

| 场景 | 创意长文 | quicksort 短测 | 3K prompt | GPU |
|---|---:|---:|---:|---|
| **最差**：Control Center 安静 + `-t 16` | ~18 tok/s | ~27 tok/s | ~700 tok/s | ~19W / P4 |
| **最好**：Control Center 性能 + `-t 8` + P-core 亲和性 | ~65 tok/s | ~88 tok/s | ~1258 tok/s | 66–71W / P0 |
| **提升** | **~3.6×** | **~3.2×** | **~1.8×** | — |

这不是承诺值，也不是可以复制到其他机器的参数；每台机器必须重新检测、实测和调优。详细数据见 [`references/performance-tuning.md`](references/performance-tuning.md) 的案例研究。

## 评测与验证

触发率评测（v0.1，14 条查询 × 3 轮，原始数据见 [`evals/trigger_final_3runs.md`](evals/trigger_final_3runs.md)）：正例 8 条 **24/24 次触发**，负例 6 条 **0/18 次触发**，查询级 **14/14 通过**。

功能评测：v0.1 做过 28/28 断言测试，但原始运行日志没有保留，因此这里不引用耗时/token 数字；v0.2/v0.3 未重新跑完整功能评测。当前以真实安装、真实请求和工具调用验证为准。

本地 skill-evaluator 评估（2026-11-06，针对 v0.3.0）：**91/100，安全门禁通过**。评分维度和报告见 [`evals/skill-evaluator-2026-11-06.md`](evals/skill-evaluator-2026-11-06.md)。这是本地主观评估，不是官方认证；v0.3.1 后未重新评分。

## 安全提示

> [!WARNING]
> 本地推理不等于 Claude Code 完全离线：更新、遥测、web search 等仍可能联网。模型服务和代理默认只绑 `127.0.0.1`，不要改成 `0.0.0.0`，除非你明确需要局域网访问并理解风险。

- 检测脚本只读，不修改系统；下载/安装前必须明确确认，默认只给方案。
- 不包含模型权重；模型从官方来源下载，许可证由使用者自行接受。
- 模板中的 `API_KEY=dummy` 是占位值；仓库不包含真实 API Key 或个人路径。
- 完整说明见 [`references/safety-licenses.md`](references/safety-licenses.md)。

---

MIT licensed · [LICENSE](LICENSE) · [Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md)
