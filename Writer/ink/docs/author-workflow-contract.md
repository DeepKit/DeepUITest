# 作者工作流契约 — 完整生产版

> **状态**：v1（2026-07-04，质量硬门禁修订）
> **定位**：InkFlow v2 的用户可执行契约。技术实现必须服务这里定义的完整工作闭环，不存在 MVP 裁剪版。

## 1. 总原则

- 生产期不随机打断作者；人类只在 setup、contract confirm、review、import finalize、abort 等明确边界介入。
- 所有人工动作必须落 `writing_human_decisions`，包含 actor、reason、目标 session/run/chapter/shot、前置条件校验结果。
- 所有 AI 调用必须经 `LLMGateway`，落 `writing_ai_call_attempts` 与 `writing_runtime_events`。
- 所有正式正文必须来自 accepted canonical；未 accepted、rejected、degraded、failed run 的文本不得进入后续上下文或导出。
- 所有正式正文必须通过 shot/chapter/book 三层质量硬门禁；人工 accept 不得覆盖硬质量失败。
- 所有质量报告必须区分 `ES`/`SEMI_ES`/`NES` 证据层级和 `destructive`/`productive`/`neutral` 缺陷类别。
- polish 只修 destructive 缺陷；productive 偏离、角色声线、有效留白和故意粗粝必须保护，neutral 问题交 review。
- 已有稿重构是一等工作流，不是外部脚本。

## 2. 公开命令

| 命令 | 目的 | 必须产物 |
|------|------|----------|
| `ink init` | 创建项目、元契约草案、模型池配置 | `writing_projects`、`writing_meta_contracts`、`writing_contract_clauses` |
| `ink setup --chapter N` | 生成/更新章节节奏、shot 契约、大纲候选 | chapter specs、shot contracts、outline specs、task cards |
| `ink confirm-contract` | 人类确认元契约或章节/shot 契约 | `writing_human_decisions`、`writing_contract_changelog` |
| `ink write --chapter N` | 完整生成一章：draft、gate、jury、soft gates | drafts、eligibility、jury raw/aggregate、failure attributions |
| `ink review --chapter N` | 章级审核报告与候选正文展示 | chapter review、runtime report |
| `ink accept --chapter N` | 将 run 设为 accepted canonical | accepted review、human decision、hard seal |
| `ink revise --chapter N` | 人类要求修订并新建 run | human decision、新 run、旧 run 留档 |
| `ink reject --chapter N` | 拒绝当前 run，禁止进入正式正文 | rejected review、human decision |
| `ink resume --session ID` | 恢复崩溃 session | checkpoint/resume event |
| `ink import --source PATH --dry-run` | 导入已有稿并生成映射/问题清单 | import run、manifest、questions |
| `ink import --finalize RUN` | 人类确认导入并原子落库 | import decision、human decision、project data |
| `ink export` | 导出 accepted canonical 正文 | export artifact、runtime event |

## 3. Init / Setup

`init` 必须收集或生成：

- 项目身份：标题、类型、目标章节、目标字数
- 叙事声音：POV、时态、语体
- 硬边界：禁用事实、禁用词、允许 POV、容量下限
- 风格锁、世界知识、角色档案、母题系统、创意区
- 质量硬门禁：目标读者、文体标杆、正/反例、禁用俗套、水文模式、shot/chapter/book 阈值、盲评策略、继续阅读目标、protected_roughness
- writer model pool 与 jury model pool

`setup --chapter N` 必须生成：

- 章节节奏契约
- 每个 shot 的 must_land、anti_write、scene_contract、persona_assignment、soft_constraints
- 大纲候选与 drift_score
- task card 与 prompt snapshot

setup 后进入人工确认点：作者可 confirm、edit、abort。confirm 必须写 `writing_human_decisions(decision_type='contract_confirm')`。

## 4. Write

`write --chapter N` 是完整生产流水线：

1. 从 DB reload contract dataclass。
2. 为每个 shot 生成 X 篇同 persona 同 prompt 不同模型的候选稿。
3. deviant 仅作为创意边界参考，不进 winner 候选池。
4. 第一道 hard gate 先跑，失败稿不进入第二道。
5. 第二道 hard gate 通过后才进入 literary jury。
6. 3 裁判全评 12 维，raw 与 aggregate 分表落库。
7. quality floor 硬门禁：`final_score`、核心维度、裁判分歧、合格候选数全部达标后才可 winner。
8. winner 必须进入 `polish_revision`，局部精修后重新过 hard gates + quality floor；polish 必须保护 productive_deviations。
9. quality blocking gate N=3 不得 diagnostic 放行；必须 revise/reject 新建 run 或 failed。
10. shot soft seal 后不能回退；后续问题通过 revise/reject 新建 run。
11. 每次模型调用、状态转换、质量失败、补写都写 runtime event。

## 5. Review / Accept / Revise / Reject

`review --chapter N` 必须展示：

- 当前 run 与 previous accepted 的差异
- 每个 shot 的 winner、淘汰原因、hard gate、jury 维度分
- quality floor 报告：final_score、所有核心维度、裁判分歧、盲评、继续阅读、polish 前后差异
- ES/SEMI_ES/NES 证据分层与 destructive/productive/neutral 缺陷分类
- productive_deviations / protected_roughness 是否被保留；neutral_issues 等待什么裁决
- soft gate / quality blocking 失败说明与注入去向
- fact anchors、forbidden facts、POV、场景契约检查结果
- AI 调用失败、degraded 候选、补写次数和总成本

`accept` 前置条件：

- latest run completed
- 全 chapter shots 已 soft_sealed
- 每个 shot 的 winner 已通过 quality floor 且完成 polish_revision
- 章级 7 维全部达到 chapter_quality_floor
- 盲评通过，`would_continue_reading_score` 达到 `reader_pull_floor`
- 最近一次篇级滚动检测无 blocking issue
- 无 degraded draft 进入 winner
- 无未解决 import/review question
- 无 destructive blocking；productive_deviations 已保护；neutral_issues 已裁决或记录
- `preconditions_json` 与 `quality_report_json` 完整记录所有硬门禁证据

`accept` 不允许人工 override 硬质量失败。若 quality report 中任一 hard failure 为 true，唯一合法动作是 `revise` 或 `reject`。

`revise` 与 `reject` 必须新建或标记 run，不得覆盖旧 run。旧正文、prompt、AI attempts、jury scores 全部留档。

## 6. Import / Reconstruction

已有稿导入分两步：

1. `dry-run`：扫描源文件，生成 `writing_import_manifests` 与低置信 `writing_import_questions`，不写正式项目数据。
2. `finalize`：作者解决问题后，写 `writing_import_decisions` 与 `writing_human_decisions`，然后原子落库。

导入必须记录 source hash。源文件变化后，旧 dry-run 结果不得 finalize。

重构已有稿时，导入文本进入正文 revision 链；导入文本不得直接 accepted，必须走同一套 hard gates、quality floor、polish_revision、chapter review、book rolling check，不允许绕过 accepted canonical。

## 7. Export

导出只读取 accepted canonical，正文读取必须经过 `text_repository.read_current_text()` / `v_current_text`。导出前必须确认最近一次篇级滚动检测无 blocking issue。导出器必须清理结构标签，并写 runtime event。

## 8. 验收

完整生产验收必须跑通：

- `init`
- `setup --chapter 1..6`
- `confirm-contract`
- `write --chapter 1..6`
- 每章 `review`
- 至少一次 `revise` 或 `reject` 后重跑
- 至少一次 `polish_revision` 保护 productive_deviation 的验证
- 至少一次盲评与继续阅读质量证明
- 第 5 章触发篇级滚动检测
- `accept --chapter 1..6`
- `export`（必须无篇级 blocking issue）
- `import --dry-run` + `import --finalize`
- 崩溃恢复：drafting、jury、soft_gate、chapter_review、import_finalize 至少各一个断点

验收通过标准：无 degraded 假通过、无低于 shot/chapter/book 质量硬门禁的文本进入 accepted/export、无盲评/继续阅读失败文本进入 accepted、无 productive_deviation 被 polish 磨平、无人工 override 硬质量失败、无未审稿正文进入导出、所有 AI 调用可追溯、所有人工决策可追溯、所有旧关键不变量在 `invariant-traceability.md` 中有对应测试。
