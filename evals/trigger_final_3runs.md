# Trigger Evaluation: local-ai-agent-setup

**Runs per query:** 3  
**Queries:** 14 (8 positive, 6 negative)

| Query | Expected | Triggered | Pass |
|---|---|---|---|
| MacBook M3 Pro 18GB 能跑什么本地大模型？ | yes | 3/3 | PASS |
| 双 4090 服务器，团队多人用 Claude Code，推荐 llama.cpp 还是 vLLM？ | yes | 3/3 | PASS |
| 帮我把 Ollama 的模型目录移到 D 盘，并把上下文设成 32K。 | yes | 3/3 | PASS |
| 怎么把这个本地模型部署方案做成给别人的安装包？ | yes | 3/3 | PASS |
| 怎么用 LiteLLM 把本地模型接到 Claude Code？ | yes | 3/3 | PASS |
| 我有一台 RTX 4090，想给团队搭本地 vLLM 推理服务，怎么选模型？ | yes | 3/3 | PASS |
| 我电脑只有 32GB 内存、没有独显，能跑本地模型吗？ | yes | 3/3 | PASS |
| 本地部署一个离线 AI 智能体，要求能调用工具。 | yes | 3/3 | PASS |
| Claude API 的 prompt caching 怎么用？ | no | 0/3 | PASS |
| 写一个 Python 快速排序。 | no | 0/3 | PASS |
| 如何用 React 做一个仪表盘？ | no | 0/3 | PASS |
| 帮我总结这份 PDF 的内容。 | no | 0/3 | PASS |
| 帮我清理 C 盘下载文件夹里的大文件。 | no | 0/3 | PASS |
| 推荐一个在线翻译网站。 | no | 0/3 | PASS |

## Summary

- Queries passed: **14/14**
- Positive runs triggered: **24/24**
- Negative runs triggered: **0/18**

Note: one negative query (React dashboard) timed out once during run 3; it was retried with a 150s timeout and confirmed not triggered. The retry is recorded in `trigger_final_run3.json`; the original timeout is preserved in `trigger_final_run3_original.json`.
