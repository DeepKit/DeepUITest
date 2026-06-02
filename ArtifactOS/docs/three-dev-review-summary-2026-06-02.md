# 三名工程师并行审查 ArtifactOS 开发文档：汇总报告

> **审查日期**: 2026-06-02  
> **审查范围**: 全量文档（12 份 + 蓝图） + 所有代码（29 个迁移文件、4 个后端 Python 文件、Delphi 核心源码）  
> **审查者**: Developer A（架构与技术栈）、Developer B（数据模型与治理）、Developer C（流程与工作流）

---

## 一、总体结论：有条件启动（CONDITIONAL GO，三名审查者一致）

| 审查者 | 核心评分 | 结论 |
|--------|---------|------|
| Dev A（架构） | 完整性 7/10，一致性 5/10，可行性 8/10 | **条件启动** |
| Dev B（数据） | 完整性 7/10，一致性 7/10，正确性 6/10 | **条件启动** |
| Dev C（流程） | 完整性 7/10，一致性 8/10，可操作性 6/10 | **条件启动** |

**共识**：文档的架构设计稳固、领域模型一致性强、代码开发标准高。但**不能无条件下开始全面开发**——必须解决下面的阻塞项。

---

## 二、阻塞项（Blockers）— 合并去重后共 8 项

### 🔴 P0 阻塞（必须立即修复）

| # | 阻塞项 | 提出者 | 描述 |
|---|--------|--------|------|
| 1 | **ChainRunner SQL 注入** | Dev A | `ChainRunner.pas` 使用字符串拼接构造 SQL（第 68、88、93、153-161 行），用户输入含单引号即崩溃。P0 声明"已修复"是错误的——仅 Repository 层做了参数化，ChainRunner 未修复。 |
| 2 | **缺失文档 16/18/19/24** | Dev C | 微信通道(16)、交互修改与遗忘(18)、证据认知与进化(19)、数据库模型(24) 被流程文档交叉引用 30+ 次，但内容不可审阅。没有这些文档，流程链在数据边界、交互合约和 DB Schema 上引用未定义对象。 |
| 3 | **RSC/CTF/Contract 链条无代码实现** | Dev C | 蓝图 (01, §0.4.11) 明确要求"minimum chain: raw idea → RequirementFrame → ContentSpecSnapshot → ContractCandidate → Contract"。零代码实现。选题漏斗(08)和写作流水线(11)都依赖此链条。 |
| 4 | **Contract pipeline 数据表缺失** | Dev B | Docs 05 定义了 `RequirementFrame`、`ContentSpecSnapshot`、`ContractCandidate`、`ArtifactContract` 等表，29 个迁移中均未创建。`substudio_execution_task.contract_id` 和 `spec_status` 指向不存在的表。 |

### 🟡 P1 阻塞（必须在主要开发前修复）

| # | 阻塞项 | 提出者 | 描述 |
|---|--------|--------|------|
| 5 | **Case 层级验证触发器缺失** | Dev B | 文档规定 DaySubCase 不能直接挂到 WeekCase 下，但 `case_record` 表无任何触发器验证层级关系。20 行 PL/pgSQL 即可修复。 |
| 6 | **SubStudio-Artifact 1:1 约束缺失** | Dev B | 文档明确 "one SubStudio = one Artifact"，但 `artifact.sub_studio_id` 无 UNIQUE 约束。多个 Artifact 可静默绑定同一 SubStudio。 |
| 7 | **跨表状态同步触发器缺失** | Dev B | `trg_task_pipeline_artifact_status_sync`（Artifact 不能先于 Task 进入 sealed，Task 不能先于 Artifact sealed 进入 publishing）不存在。Smoke test 手工编排状态——无任何约束强制耦合。 |
| 8 | **Agent 引用混乱** | Dev A | Stack Decision 说"不再需要 Agent"，但同文档引用 Agent 7 次，代码中 `RuntimeInstanceTypeAgent` 和 `RuntimeCommandSourceAgent` 常量仍存在。新人读代码会误以为 Agent 是计划组件。 |

---

## 三、高风险项（非阻塞但需高度关注）

| 风险 | 提出者 | 描述 |
|------|--------|------|
| **生成管线无 Prompt 组装/LLM 调用基础设施** | Dev C | 写作流水线(11) Phase 1 清单 21 项，质量门禁(12) 20 项，总计 40+ 个 Phase 1 任务——零实现。无 prompt 组装机制、无 LLM 调用、无缓存感知分层注入。这是系统核心域逻辑的 80%。 |
| **Amy Desk 与实际代码语义鸿沟巨大** | Dev C | 文档描述 Amy Desk 具有注意力预算过滤、工作卡压缩、决策简报、准备动作面板。而 `amy_desk.py` 仅做两次原始 SQL 查询并以平铺表格显示。文档所说与代码所做完全不匹配。 |
| **FK 债是结构性的** | Dev B | 迁移 024 (`fk_roadmap.sql`) 记录了 25-30+ 个延迟 FK 关系。`studio.case_id`、`sub_studio.studio_id`、`artifact.blueprint_id` 等列为 nullable UUID，无数据库级 FK 约束。孤儿记录可能产生。 |
| **战略意图层仅存在于文档** | Dev B | `lighthouse_strategy_objective`、`case_objective`、`purpose_portfolio` 等核心治理对象在 docs 24 中有完整 SQL，但零迁移文件。 |
| **RealPublishGate 简化为一枚 flag** | Dev B | 文档定义 12 个条件，实际实现仅检查 `current_setting('artifactos.run_mode')`。L3 模式绕过整个门禁检查清单。 |
| **人类注意力预算无执行机制** | Dev C | Amy Desk 文档规定每日 Must Review 1-3 项、超 5 项为预算异常。但代码无任何注意力过滤、分类或溢出报警。 |

---

## 四、各审查者详细评分

### Dev A（架构与技术栈）

| 维度 | 评分 | 关键发现 |
|------|------|----------|
| 完整性 | 7/10 | Engine 生命周期完善；Desk 零实现；LISTEN/NOTIFY 未实现；条件编译宏未使用 |
| 一致性 | 5/10 | Agent 自相矛盾；ChainRunner SQL 注入（声称已修复但未修复）；DisconnectLocked 死锁 |
| 可行性 | 8/10 | 技术栈务实（Delphi + PG + DeepBase）；build.bat 可编译；主要挑战是范围深度而非技术可行性 |

### Dev B（数据模型与治理）

| 维度 | 评分 | 关键发现 |
|------|------|----------|
| 完整性 | 7/10 | 29 迁移覆盖 40+ 表；15-18 张文档定义的表未迁移；Contract pipeline 数据层完全缺失 |
| 一致性 | 7/10 | 强术语一致性；枚举值匹配；但 case_snapshot 缺少 3 个 hash 列；run_mode 枚举集不一致 |
| 正确性 | 6/10 | Shadow guard、QualitySnapshot 不可变性、WeChat 动作门控正确实现；但 Case 层级、SubStudio-Artifact 1:1、状态同步触发器均缺失 |

### Dev C（流程与工作流）

| 维度 | 评分 | 关键发现 |
|------|------|----------|
| 完整性 | 7/10 | 全流程链条覆盖全面；缺失文档 16/18/19/24 是关键断层；Phase 1 清单 100+ 项无优先级排序 |
| 一致性 | 8/10 | 术语一致性出色；文档 10 章节编号断裂；文档 13 重复模块标签；跨文档引用使用旧编号 |
| 可操作性 | 6/10 | 代码文件质量高（4 个文件）；但文档抽象与代码间存在巨大鸿沟（95% Phase 1 逻辑仅存在于设计意图中） |

---

## 五、建议行动计划

### 第一阶段：解除阻塞（预估 3-5 个工程日）

1. **修复 ChainRunner SQL 注入** → 改为 `ExecuteJson`/`InsertAndReturnIdJson`（参照 `Repository.pas`）
2. **补齐缺失文档 16/18/19/24** → 提供可审阅内容
3. **创建 Contract pipeline 数据表** → 至少 `artifact_contract`、`requirement_frame`、`contract_candidate`
4. **添加 Case 层级验证触发器** → `fn_guard_case_type_hierarchy`
5. **添加 SubStudio-Artifact 1:1 约束** → `UNIQUE (sub_studio_id)` 或部分唯一索引
6. **添加跨表状态同步触发器** → `trg_task_pipeline_artifact_status_sync`
7. **清理 Agent 引用** → 统一移除所有 Agent 常量或明确文档化
8. **实现 RSC/CTF/Contract 链条骨架** → 至少生成 RequirementFrame → ContentSpecSnapshot → ContractCandidate 的 Python 原型

### 第二阶段：降低风险（后续 2-3 周）

9. **实现 Prompt 组装基础设施** → 10 槽位选择性注入 + 缓存感知分层
10. **重构 Amy Desk** → 实现注意力预算过滤、工作卡压缩、准备动作面板
11. **开始 FK 硬化** → 按迁移 024 roadmap 执行 Phase 1B FK 约束
12. **添加 Engine lease 扩展** → `DoPollAndProcess` 中周期性调用 `ExtendCommandLease`

### 第三阶段：全面开发

解除所有阻塞项后，ArtifactOS 可以进入全面开发阶段。文档的基础架构稳固，开发标准高，领域模型一致性强——这是启动开发的坚实基础。

---

## 六、最终结论

**三名审查者一致认为：ArtifactOS 设计质量高，但当前不能直接进入全面开发。**

核心问题不是"设计是否有缺陷"，而是"代码与文档之间的鸿沟尚未跨越"。最关键的缺失是：
- 生成管线（prompt 组装 + LLM 调用）——这是系统核心域逻辑的 80%
- Contract pipeline 数据层——没有它，生成管线和质量门禁没有有效输入
- 缺失的基础文档 16/18/19/24——流程链在架构上引用未定义的边界

**解除上述 8 个阻塞项后，ArtifactOS 具备进入全面开发的充分条件。**