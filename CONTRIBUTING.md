# Contributing

Thanks for improving `local-ai-agent-setup`.

## Before you open a PR

- Keep `SKILL.md` under ~500 lines; put details in `references/`.
- Keep detection scripts read-only. Do not add downloads, installs, or system changes.
- Do not add model weights, binaries, API keys, personal paths, or logs.
- Verify model tags and sizes against official sources before adding them.
- If you change behavior, add or update an eval in `evals/evals.json` and explain how you tested it.
- For trigger changes, update `evals/trigger_queries.json` and include before/after trigger results.

## Repository layout

```text
local-ai-agent-setup/
├── SKILL.md
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── assets/        # 启动脚本、Claude 设置、代理 .env、健康检查模板
├── references/    # 模型矩阵、后端对比、Claude Code 接入、性能调优、排错、许可证
├── scripts/       # detect-hardware.ps1 / .sh（只读检测）
└── evals/         # 功能断言、触发查询、评测结果
```

## Testing

Run the detection script on your OS:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/detect-hardware.ps1
```

```bash
bash scripts/detect-hardware.sh
```

Then run the relevant eval prompts with and without the skill and compare.

## License

By contributing, you agree that your contributions are licensed under the MIT License.
