# Novelix 研究记录与 InkFlow 启发

Date: 2026-06-29
Source: https://github.com/zxerai/novelix

## 1. 观察结论

Novelix 是一个 Node/pnpm monorepo，核心代码分在 `packages/core/src`，前端 Studio 在 `packages/studio`，CLI 在 `packages/cli`。README 宣称的核心能力不是单一写手，而是“规划、编排、写作、审计、修订、状态结算”的多 agent 管线。

对 InkFlow 有价值的不是照搬它的 agent 数量，而是它把长期事实和章节生产拆成了几类稳定工件：

| Novelix 工件 / 模块 | 作用 | InkFlow 对应启发 |
|---------------------|------|------------------|
| 7 个 truth files | `current_state.md`、`particle_ledger.md`、`pending_hooks.md`、`chapter_summaries.md`、`subplot_board.md`、`emotional_arcs.md`、`character_matrix.md` | InkFlow DB 是真相源，但可投影出可读 truth 文件，供 setup、审稿和 LLM prompt 稳定读取 |
| `chapter_memo` | 每章 7 段任务备忘，写手必须让每段在正文留下可定位痕迹 | InkFlow 的 `setup` 应输出 `fact_manifest` + `shot task card`，must_land 不能再是散文化愿望句 |
| `ContextPackage` | 从 truth files 和记忆库中按相关性选择上下文 | InkFlow 应把 previous context / accepted anchors / book_run draft context 统一成可审计 context package |
| `RuleStack` | 将 hard / soft / diagnostic 规则分层 | InkFlow contract-first gate 应明确硬事实、软表达、诊断提示三层，避免文学评分抵消硬错误 |
| review/revise cycle | audit → revise → reassess，默认有限轮次，保留最高分版本 | InkFlow 的 outline/draft 重写必须有轮次上限、净提升判断和失败归因 |
| state validator | 正文与 truth file 变更之间做一致性校验 | InkFlow fact anchors / setup manifest 也应在正文封板前做“正文是否支持状态变化”的反向校验 |
| snapshots / rollback | 人工 reject 可回滚章节状态和后续依赖 | InkFlow 已有 accepted canonical，可进一步增强 rejected 章节对 book_run draft context 的回滚可见性 |
| Studio | 展示章节状态、审计问题、truth files、知识图谱、用量等 | InkFlow 需要观测面，至少先做 CLI/Markdown report，后续再考虑 Web UI |

## 2. 对当前问题的直接启发

第 3 章问题的根源是大纲门禁没有起作用。Novelix 的做法提醒我们：章节计划必须先变成可验证的“章节备忘 / 事实清单”，不能只把大纲当自然语言交给写手。

InkFlow 应把 `setup --chapter` 的输出升级为：

```text
chapter setup
  → fact_manifest:
    allowed_facts
    forbidden_expansions
    must_land_anchors
    pov_known_unknown
    contract_numbers
    hook_requirements
    format_rules
    editorial_intent
  → outline prompt
  → outline hard gate
  → winning outline
  → shot task cards
```

这样大纲 gate 检查的是“是否覆盖 fact_manifest”，而不是“大纲看起来是否合理”。草稿 gate 检查的是“正文是否兑现 task card”，而不是“文字是否顺”。

## 3. 不应照搬的部分

1. Novelix 偏章级生产，InkFlow 是 shot 级精细控制。InkFlow 不应退回整章单稿审计，否则会丢掉 shot 级 L4 和 accepted fact anchor 的优势。
2. Novelix 的 truth files 是 Markdown 文件优先；InkFlow 的 DB3 仍应保持唯一真相源。可读文件只能是投影，不应成为第二套真相源。
3. Novelix 的 33/37 维审计范围偏网文和同人连续性。InkFlow 应保留文学 9 维和类型职责按需启用，不把所有维度变成每 shot 必审。
4. Novelix 默认 review/revise 是整章修订。InkFlow 对《分流》这类文学项目应优先定位到具体 outline / task card / shot / gate，不要动辄整章重写。

## 4. 建议迁移到 InkFlow 的最小集合

P0 只迁移四件事：

1. **fact_manifest**：从 setup 包编译结构化硬事实清单。
2. **chapter memo / task card**：把胜出大纲编译成每个 shot 的可检查任务卡。
3. **eligibility-before-PK**：大纲和草稿先判资格，只有 eligible 才进入文学 PK。
4. **state / truth validation**：正文封板前检查状态变化是否被正文支持，防止“事实锚点凭空更新”。

P1 再考虑：

1. 从 DB 生成可读 truth 投影文件。
2. 做 `ink report` / `ink status` 的管线观测面增强。
3. 增加 hook ledger 健康度和过期伏笔升级规则。
4. 增加人工 reject 后的 book_run draft context 可视化回滚报告。

## 5. 对管线质量的判断

管线是否有必要，取决于它是否比直写更可靠。旧管线的问题是“赛马之前没有资格线”，所以它会花更多钱选出更顺但更违约的稿。新管线的价值应该来自三点：

1. 写前：setup 把人类意图变成机器可审的 hard fact pack。
2. 写中：大纲和草稿先过资格，违约稿没有参赛权。
3. 写后：状态变化、fact anchors、hook 账本都能反查到正文证据。

如果这三点没落地，管线确实会变成算力浪费；如果落地，管线的优势不是“文笔必然更好”，而是“更少把错误推进到后续章节，更容易定位返工原因”。
