# InkFlow — 当前任务与议题清单

Date: 2026-06-27
Status: v3.16；Schema v17；38 张业务表 + `_schema_meta` 元表；当前阶段：生产内核硬化中；最近全量验证：`407 passed, 4 warnings`

---

## 1. 当前结论

InkFlow 不能按“已经正式投产”判断。第 2 章本地兜底链路和第 3 章远端 writer/jury 链路已经跑通，证明 `init -> setup --chapter -> run --chapter -> review` 方向成立；但专家审阅确认，现有工程实现仍有若干生产级不变量没有完全固化，当前只能进入“受控试跑”，不能批量无人值守生产。

当前策略不是推倒重来，也不是继续零散打补丁，而是“推倒 40%，保留 60%”：

- 保留：CLI 入口、`.models` 模型配置、writer/jury 服务、Prompt/契约资产、分层裁判维度、setup 包、导出排版、现有测试框架。
- 硬化：正文真相源、run/shot 身份、review/reject/abort 语义、export selector、L3/L4 gate 状态机、远端评审失败归因。
- 暂缓：跨 schema 的 shot_id 主键改造。这是 P0，但需要单独迁移与数据兼容测试，不混入本轮小步修复。

本轮已完成第一批生产内核硬化：

- 显式远端 jury 配置不再因为 providers 为空而静默回落本地评分。
- 留白创意评审使用 `creative_score` 和 `creative_blank` winner 语义。
- 大纲重写后重新读取最新 shot contract，避免继续用 stale contract。
- `_update_contract()` 更新 beats 时保留 `must_land_json.title/event`。
- 四轨写手按 persona 分别编译 prompt，避免“意象师”身份污染节奏师/对话师/结构师。
- L4 从审计提示升级为封板前硬 gate；L4 未过不 finalize、不计 completed、不导出。
- L3 在 session complete 和自动导出前执行；L3 未过即停止封板/导出。
- 自动导出限定当前 `run_id`，并只导出 `done_green/done_yellow + current_revision_id`。
- 导出层保留正文并剥离模型生成的 Markdown 标题；纯文本导出也走相同正文排版清理。
- RetryBudget 同类熔断改为第 N 次立即触发，切换 failure type 重置连续计数。

---

## 2. 权威文档

| 文档 | 位置 | 当前状态 |
|------|------|:---:|
| 技术设计权威 | `docs/design.md` | 需标注 v3.16 / 受控试跑 / gate 硬停 |
| 实现契约 / DDL / 状态机 | `docs/implementation-contract-v0.md` | Schema v17，需记录 canonical truth source 下一阶段 |
| 人机流程 | `docs/flow.md` | 需明确 init/setup/run/review 与 L3/L4 封板边界 |
| 三棵树与正文真相源 | `docs/design-3tree-architecture.md` | 已补充 accepted canonical 待硬化边界 |
| 悬疑引擎 | `docs/suspense-engine.md` | 已实施核心闭环，待更多真实章节验证 |
| 开发历史 | `docs/history.md` | 本轮追加 PROD-CORE-HARDENING |
| Bug 记录 | `docs/bugfix.md` | 本轮追加 B55-B59 |

---

## 3. 已完成任务归档

详细实现记录见 `docs/history.md`。

| 阶段 | 已完成 |
|------|--------|
| P0 纵向闭环 | 导入第 1 章、确认契约、逐 shot 生成第 2 章、scope report |
| 真实章节验证 | 第 2 章本地兜底链路内容基本合格；第 3 章远端 writer/jury 链路 5/5 green 并导出 |
| 工作流收敛 | `init -> setup --chapter -> run --chapter -> review` |
| JURY-V5 | 硬规则 → 类型职责 → 文学 9 维；至少 2 个过线稿；单线返写 |
| 章节契约准入 | B52：旧章节限定、旧段落锁、过期 setup 包、setup/contract shot 数不一致提前失败 |
| 远端评审归因 | B53/B54：gate 淘汰不再显示均分 0；timeout/解析失败不混入文学分；全维度不可评为 `jury_unavailable` |
| PROD-HARDEN-1 | 本轮已修复 persona prompt、creative_score winner、L4/L3 硬停、当前 run 导出过滤、retry 熔断 |

---

## 4. 当前 P0 待办

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| P0 | CORE-1 | 正文 canonical truth source 改造 | 待开发 | review `--accept` 才产生 accepted/sealed canonical；`--reject/--revise/abort` 必须使对应章节不可被后续上下文和导出当作正式正文 |
| P0 | CORE-2 | run/shot identity 重构 | 待开发 | 同一章节多次重写不能复用旧 `shot_id` 跳过旧正文；shot identity 必须区分 logical shot 与 run attempt |
| P0 | EXPORT-4 | 导出 selector 升级为 accepted canonical | 待 CORE-1 | 默认导出只取人工接受的正式版本；调试导出必须显式指定 run |
| P0 | REVIEW-1 | 人工审稿状态机落库 | 待开发 | `review --accept/--revise/--reject` 不只写 YAML，还写 DB 审稿状态并影响后续上下文选择 |
| P0 | ABORT-1 | aborted/crashed session 失败归因收敛 | 部分完成 | abort/crash 后的非正式 revision 不进入事实锚点、previous context、默认导出 |
| P0 | VALID-1 | 真实章节小样验证 | 单元/集成回归已通过 | 用当前代码跑一个小章节/单 shot 远端 writer+jury 验证 L3/L4 硬停与导出过滤 |

---

## 5. 当前 P1 待办

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| P1 | CHAPTER-3-REVIEW | 第 3 章人工审阅 | 待人工 | 审阅 `D:\_Progs\.Story\《分流》\正文\分流_v01.c03_导出.md`，用 `ink review "分流" --chapter v01.c03 --accept/--revise/--reject` 记录结论 |
| P1 | CHAPTER-4-SETUP | 第 4 章生产前校准 | 待第 3 章审阅后执行 | 先吸收第 3 章审阅结论，再 `ink setup "分流" --chapter v01.c04 --force` |
| P1 | JURY-V5-REAL | 分层裁判真实项目持续观测 | 已有第 3 章样本 | 每章记录硬规则失败数、类型 gate 触发数、文学 9 维分布、过线稿数量和单线返写次数 |
| P1 | CREATIVE-3-EVAL | 留白创意评审效果评估 | 已修正 score_key | 比较标准 winner 与 creative winner 的高光率、合规风险和人工偏好 |
| P1 | STYLE-1 | 议论性/系统解释文本抑制评估 | L4 已硬化 | 统计 narrator intrusion、system voice、explanation 触发率，验证不再出现大段机制议论 |

---

## 6. 当前验证命令

```powershell
cd D:\_Progs\02Business\Writer\inkflow
python -m py_compile src\inkflow\cli.py src\inkflow\services\jury_service.py src\inkflow\services\outline_evaluator.py src\inkflow\services\writer_dispatcher.py src\inkflow\services\architect_gate.py src\inkflow\services\retry_budget.py src\inkflow\export\exporter.py
python -m pytest tests\test_jury_scoring.py tests\test_retry_budget.py tests\test_cli.py tests\test_architect_gate.py -q
python -m pytest -q
```
