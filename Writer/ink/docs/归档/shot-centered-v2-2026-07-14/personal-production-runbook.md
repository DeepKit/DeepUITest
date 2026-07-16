# Ink 个人小说生产运行手册（Shot 中心历史基线）

> **迁移提示（2026-07-14）**：本手册描述现有 shot 中心生产库的操作方式，只用于读取、备份和维护迁移前基线。Scene-first 新流程以 `scene-first-authority-amendment.md` 为权威；在 Scene Revision 和 Chapter Snapshot 迁移完成前，不得把本手册中的 shot 封版流程当作新架构已经落实。

## 上线范围

本手册面向单作者、本机 SQLite、本机 WiseGateway 真实模型代理。PostgreSQL、
RLS、多用户并发、TUI 不属于个人生产上线阻断项。

## 固定生产库

《白灯法则》当前生产库：

```text
D:\_Progs\.Story\《白灯法则》\.inkflow\inkflow.db
```

正文、revision、LLM attempt、jury、chapter review、ethics review 和人工决策
均以该数据库为唯一权威源。不要手工覆盖导出的 Markdown 来代替数据库修订。

## 每次生产前

```powershell
$env:PYTHONPATH = "src"
$db = "D:\_Progs\.Story\《白灯法则》\.inkflow\inkflow.db"

python -m ink.cli --db $db doctor --project-id 1

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
python -m ink.cli --db $db backup `
  --output "D:\_Progs\.Story\《白灯法则》\.inkflow\backups\inkflow-$stamp.db"
```

只有 `ready_for_personal_production=true` 且 backup
`integrity_check=ok` 时开始本轮写作。

## 章节生产

先 dry-run，确认 chapter/run/shot：

```powershell
python -m ink.cli --db $db write --project-id 1 --chapter 11 --run-id 203 --dry-run
```

真实生产必须指定本机代理：

```powershell
python -m ink.cli --db $db `
  --llm-provider openai-compatible `
  --llm-base-url http://127.0.0.1:8000/v1 `
  --llm-api-key-env LOCAL_PROXY_KEY `
  write --project-id 1 --chapter 11 --run-id 203
```

不要用 `mock` 或 `deterministic` 结果作为正文质量证据。

## 审章、责任审查和修订

```powershell
python -m ink.cli --db $db `
  --llm-provider openai-compatible `
  --llm-base-url http://127.0.0.1:8000/v1 `
  --llm-api-key-env LOCAL_PROXY_KEY `
  review --project-id 1 --chapter 11 --run-id 203

python -m ink.cli --db $db `
  --llm-provider openai-compatible `
  --llm-base-url http://127.0.0.1:8000/v1 `
  --llm-api-key-env LOCAL_PROXY_KEY `
  ethics-review --project-id 1 --chapter 11 --run-id 203 --actor author
```

若 chapter review 给出局部问题，使用 `repair`，不要直接改 canonical text：

```powershell
python -m ink.cli --db $db `
  --llm-provider openai-compatible `
  --llm-base-url http://127.0.0.1:8000/v1 `
  --llm-api-key-env LOCAL_PROXY_KEY `
  repair --shot-id SHOT_ID --run-id 203 --issue "具体问题"
```

`repair` 会产生新 revision、保留 `source_revision_id`，并自动重跑 chapter
review。

## 作者接受

程序过门不等于作者接受。阅读全文后只能由作者执行：

```powershell
python -m ink.cli --db $db accept `
  --project-id 1 --chapter 11 --run-id 203 `
  --actor author --reason "作者阅读全文后接受"
```

不满意时使用 `revise` 或 `reject`，不要为了推进进度绕过质量门。

## 批量审查

```powershell
python -m ink.cli --db $db `
  --llm-provider openai-compatible `
  --llm-base-url http://127.0.0.1:8000/v1 `
  --llm-api-key-env LOCAL_PROXY_KEY `
  review-batch --project-id 1 --run-id 203 --chapters 11-15
```

## Source clause 检查

```powershell
python -m ink.cli --db $db shot-coverage --project-id 1 --chapter 11
```

重要条款缺少证据时，用 `shot-coverage-set` 记录正文证据，而不是口头确认。

## 中断恢复

```powershell
python -m ink.cli --db $db resume --session-id SESSION_ID --dry-run
python -m ink.cli --db $db resume --session-id SESSION_ID
```

不得删除半成品 run 后重新伪造成功。所有失败 attempt 和恢复事件必须保留。

## 导出

仅导出作者已接受、质量门通过且满足责任审查要求的内容：

```powershell
python -m ink.cli --db $db export `
  --project-id 1 `
  --output "D:\_Progs\.Story\《白灯法则》\output\白灯法则.md"
```

## 故障处理

- `400`：模型名或参数错误；检查 role config/alias，不盲目重试。
- `401`：检查 `LOCAL_PROXY_KEY`，不要把 key 写进日志或正文。
- `429/5xx/timeout`：保留 attempt，让 gateway 按配置退避和 failover。
- capacity preflight 失败：提高项目调用预算后再写，不在中途硬闯。
- jury candidate shortage：让系统补充真实候选，不手工插 mock draft。
- chapter review 未过：优先定点 repair；结构性问题进入 revise 新 run。
- 数据库异常：停止写入，保留现场，从最近一次完整 backup 恢复副本验证。
