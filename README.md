# Alex advice study — reference v3

[English methods and limitations](docs/METHODS.md) · [File guide](docs/FILES.md) · [Publication notes](docs/PUBLICATION.md)

用于复核和重现 v3 的研究项目包。包含原始候选、语料、筛选决定、情景、提示词，以及两批各 40 条原始建议。**没有参与者数据，没有 API 密钥，没有已完成的模型微调。**

## 一条命令运行离线流程

需要 Python 3.10 或更新版本，无第三方 Python 依赖。Windows、macOS、Linux 使用相同命令。

```bash
python scripts/reproduce.py
```

请先进入本 README 所在目录。运行结果位于 `build/`：288 条语料、60 条入选、60 条备用、2,304 条情景适用性记录、八个逐字节匹配的提示词、两批建议的 JSONL/CSV、归档 Word 副本及校验报告。这个命令不联网、不调用模型，也不会修改 `data/`、`results/`、`documents/`。

| 步骤 | 输入 → 输出 | 重现性质 |
|---|---|---|
| 来源收集与提取 | 46 个公开来源 → 382 条候选转述 | 已保存候选、来源 URL、定位和访问日期；原网页全文未分发 |
| 语义去重 | 382 → 288 保留＋93 合并＋1 排除 | 重放已记录的 AI 辅助判断；不是新运行的语义模型 |
| 适用性筛选 | 288 → 120 适用／有条件适用＋168 不适用 | 重放逐条规则，并生成八情景适用性矩阵 |
| 功能筛选 | 120 → 60 入选＋60 备用 | 重放功能、对照 ID、理由；60 不是预设配额 |
| 提示词 | 同一套 60 条材料＋各情景＋统一写作要求 | 八个提示词与原始生成输入逐字节相同 |
| Codex 结果 | 8 情景 × 5 次独立调用 → 40 条 | 原始响应、事件和参数记录与 08 Word 核对 |
| API 结果 | 8 情景 × 5 次独立调用 → 40 条 | 原始请求、响应和 token 用量与 10 Word 核对 |

**关于“GPT 网页版”：** 项目中此前这样称呼的 v3 批次，实际记录为 **Codex CLI，通过 ChatGPT 账户登录**；不是在 ChatGPT 浏览器页面手工输入。仓库命名为 `codex_chatgpt`，不将它错误标成浏览器实验。其 CLI 记录请求了 `gpt-6-astra`，推理强度 `medium`，但未独立核实服务端具体快照。

## 查看材料

| 文件夹 | 内容 |
|---|---|
| `data/corpus/` | 382 条候选、288 条语料、46 个来源、去重映射与措辞决定 |
| `data/selection/` | 288 条适用性决定、120 条功能筛选决定、60 入选／60 备用 |
| `data/scenarios.json`、`data/prompts/` | 八个情景、完整生成要求和参考材料 |
| `results/codex_chatgpt/` | Codex 登录方式生成的 40 条及原始事件 |
| `results/api/` | API 生成的 40 条、原始请求／响应与记录 |
| `documents/` | 01、02、07、08、10 Word 和老师原始情景文档 |
| `provenance/` | 原始脚本、发布副本日志和离线核验结果 |

08 与 10 是两个不同渠道的生成批次，不能合并为每情景十条同质重复；10 是当前 API 原始输出。原始 40 条正文没有因研究备注被修改或挑选。API 结果中的观察日志是 Codex 辅助记录，并非独立人工验证、质量分数或自动删除规则。**文末研究备注不展示给评价者。**

## 验证与重新打包

```bash
python -m unittest discover -s tests -v
python scripts/package.py --verify
python scripts/package.py
```

`--verify` 检查当前发布版的文件清单、SHA-256 和凭据模式。修改代码／数据后应先核查改动，再运行不带 `--verify` 的打包命令，重新产生清单和 ZIP。ZIP 位于 `dist/alex-advice-v3.zip`，不含派生的 `build/`、新生成的 `runs/`、密钥或 Git 历史。

## 准备新一轮生成：默认不调用模型

```bash
python scripts/generate.py --channel api --output runs/api-preview
python scripts/generate.py --channel codex_chatgpt --output runs/codex-preview
```

以上仅生成 40 个请求文件和新运行协议。输出目录必须是尚不存在的 `runs/` 子目录；不得覆盖原始记录。可以用 `--scenarios S01 S02` 只准备两个情景。五次调用相互独立，输入相同，不提示“与上一条不同”。

## 重新调用模型：单独选择

历史项目的 API key 已停止使用，仓库不包含它，也不会自动恢复使用。

如在未来决定使用**自己的新密钥**重跑，确认有对应模型权限和余额后执行：

```bash
python scripts/generate.py --channel api --output runs/api-new --execute --allow-paid-api
```

未设置 `OPENAI_API_KEY` 时，脚本会隐藏输入密钥；不保存密钥。不需要把密钥写进代码、README 或 GitHub。发生错误／截断后保留记录并停止，不自动重试、换模型或改写建议。

新运行会逐条保存请求、原始响应、记录，并导出 `generated_advice.jsonl`、`generated_advice.csv` 和 `format_checks.json`。格式检查不替代情景核查，也不自动改写或删除超出要求的输出。

Codex 新生成使用自己的 ChatGPT 登录：

```bash
codex login
python scripts/generate.py --channel codex_chatgpt --output runs/codex-new --execute
```

历史 CLI 为 `0.155.0-alpha.16.3`。不同版本可能不支持同一组隔离参数；脚本会保留错误并停止，不静默移除隔离要求。新调用不保证得到相同文本。**本次发布实际验证了离线重放、请求准备与模拟网络测试，没有使用已停用密钥开展新的付费测试。**

## 上传 GitHub

只上传这个项目文件夹内的内容，不要上传原桌面工作区或已有的其他 ZIP。可解压发布包后在 GitHub 新建空仓库，再从项目目录执行：

```bash
git init
git add .
git commit -m "Add reproducible Alex advice v3 materials"
git branch -M main
git remote add origin https://github.com/YOUR_ACCOUNT/YOUR_REPOSITORY.git
git push -u origin main
```

替换 `YOUR_ACCOUNT/YOUR_REPOSITORY`。本次交付不创建或发布远程仓库。GitHub Actions 会在 Windows/Linux 上运行离线复现、测试及清单检查，不需要配置任何模型密钥。

## 研究边界

主比较是**参考材料辅助 AI**与**普通成年人自主撰写的建议**；不能单独归因于 AI／人类本身能力。五次同情景输出可高度相似，不等于五种不同策略。本包仅覆盖已经完成的材料准备与生成，不含尚未收集的人类问卷数据或评价实验结果。

在相同已记录判断下可以重建语料、参考材料、提示词，并验证历史输出；不能保证重新检索网页、重新做判断或重新调用云模型后仍逐字相同。
