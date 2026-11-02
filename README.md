# local-ai-agent-setup

一个面向 [Claude Code](https://claude.com/claude-code) 的跨平台技能：检测本机硬件，选择能实际运行的本地模型与推理后端，并在下载/安装前给出可确认的部署方案。

A cross-platform Claude Code skill that detects your hardware, picks a local LLM stack you can actually run, and produces a confirmation-gated setup plan.

> 这不是 Anthropic 官方项目。

## 它解决什么问题

本地模型教程常常从“下载 30B 模型”开始，却不问显存、内存、磁盘和用途。这个技能先读取硬件，再按档位选型：

- **8GB 显存**：9B/12B dense Q4，明确不承诺 35B；如果提到 30B/35B-A3B，会说明它只是实验方案。
- **12GB 显存 + 64GB 内存**：Qwen3.6-35B-A3B 通过 llama.cpp `--n-cpu-moe` 把专家放内存。
- **24GB+ / 多卡**：27B dense 或 35B-A3B 全 GPU；团队场景用 vLLM/SGLang + LiteLLM。
- **Apple Silicon**：Ollama/MLX/LM Studio，按统一内存选 9B/12B/35B-A3B。
- **无 GPU**：1–4B CPU 模型，明确能力边界，不承诺 Claude-Code 级 agent。

## 核心能力

- **只读硬件检测**：Windows PowerShell / macOS-Linux bash 脚本，读取 OS、CPU、RAM、磁盘、GPU/VRAM、已装工具和 Ollama 模型。
- **模型矩阵**：Qwen3.6-35B-A3B、Qwen3.8-27B、Gemma 4 12B/26B-A4B、TranslateGemma 4B、Qwen3.5-9B/4B、gpt-oss:20b 等，含大小、许可证、适用档位和预期速度。
- **后端选择**：Ollama、llama.cpp、LM Studio、MLX、vLLM、SGLang；单用户和团队并发有明确分支。
- **Claude Code 接入**：Ollama 原生 Anthropic API、llama.cpp + anthropic-proxy、vLLM/SGLang + LiteLLM；生成 `claude-local` 包装脚本，不修改正常 `claude`。
- **团队/多用户**：vLLM/SGLang 连续批处理、Tensor Parallel、LiteLLM 虚拟密钥/配额/审计、SSH 隧道/VPN、仅绑 `127.0.0.1`。
- **安全门控**：下载/安装前必须确认；服务只绑 localhost；不默认 `--dangerously-skip-permissions`；尊重模型许可证，不打包权重。

## 安装

### 方式 A：克隆到 Claude Code 技能目录

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

### 方式 B：安装 release 中的 `.skill`

从 [Releases](https://github.com/huajielong/local-ai-agent-setup/releases) 下载 `local-ai-agent-setup.skill`，按 Claude Code 的技能安装方式导入。

安装后在 Claude Code 里直接说：

- “我的电脑能跑什么本地大模型？”
- “给团队搭 vLLM + LiteLLM 的本地 Claude Code 代理”
- “帮我把 Ollama 模型目录移到 D 盘，并设置 32K 上下文”
- “把这套本地部署方案做成给别人的安装包”

技能应自动触发；如果没有，确认技能目录在 `~/.claude/skills/` 下，并重启 Claude Code。

## 仓库结构

```text
local-ai-agent-setup/
├── SKILL.md
├── assets/        # 启动脚本、代理 .env、健康检查模板
├── references/    # 模型矩阵、后端对比、Claude Code 接入、排错、许可证
├── scripts/       # detect-hardware.ps1 / .sh（只读检测）
└── evals/         # 功能断言、触发查询、评测结果
```

## 评测

功能评测（iteration-3，两个区分性用例，每个配置 2 次）：

| 指标 | 本技能 | 旧版技能 |
|---|---|---|
| 断言通过 | **28/28** | 24/28 |
| 平均耗时 | **202.1s** | 230.1s |
| 平均 tokens | **62,046** | 65,174 |

触发率评测（14 条查询 × 3 轮）：

- 正例 8 条：**24/24 次触发**
- 负例 6 条：**0/18 次触发**
- 查询级：**14/14 通过**

说明：评测使用的是特定机器和模型，结果只代表方向性，不构成对任意硬件的承诺。评测原始数据在 `evals/`。

## 安全与隐私

- 检测脚本只读，不修改系统。
- 下载/安装前必须明确确认；默认只给方案。
- 模型服务和代理默认只绑 `127.0.0.1`，不暴露局域网。
- 不包含模型权重；模型从官方来源下载，许可证由使用者自行接受。
- 仓库不包含 API Key、个人路径或运行日志。

## 贡献

欢迎 issue / PR，尤其是：

- 新模型和量化标签（请附官方来源）；
- 新 GPU/OS 的检测结果；
- 后端兼容性修复。

提交前请确认：不包含模型权重、API Key、个人路径；检测脚本保持只读。详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

[MIT](LICENSE)
