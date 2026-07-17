# Ink v2 Scene-first 当前任务

> 只记录未完成任务。已完成内容移入 `history.md`，缺陷闭环见 `bugfix.md`。
> 当前法源：`docs/README.md`、`docs/design.md`、`docs/implementation-contract.md`、
> `docs/invariant-traceability.md`。
>
> **2026-07-15 对齐**：BFX-084 AI Repair Task 血统、BFX-085 Contract supersede/stale
> 传播、BFX-086 Accept 权威事务均已完成并归档。Fact/Guidance 生命周期（阶段1-7：
> Fact 状态机、Contract-Fact 绑定、Fact/Contract supersede 联动 stale、消费门、
> Guidance Card 生命周期与 max_uses 守卫）已完成，登记为 INV-FACT-002~009、
> INV-GUIDANCE-001~007。旧 Shot 产物及 BFX-079 前的第1/2章不能作为当前四层
> Scene Contract 架构的质量证据。全量回归 863 passed、10 skipped。
>
> **2026-07-16 裁定（作者）**：Ink 按全新系统重新投产，**旧库不做迁移**。
> 旧 Shot/Contract/评分/Accept 不满足当前血统与硬门要求，迁入只会带来结构兼容但
> 缺真实证据的"假权威"数据，并长期保留双架构旁路面。旧库降级为只读归档，
> 旧正文仅作文学参考材料，需复用时必须重新走 Contract→Generation→Review→Accept
> 链路，不允许导入为权威正文。原"旧生产库迁移与 Cutover"整项待办移除。
>
> **2026-07-17 黄金闭环进展**：① doctor 模型池分离检查逻辑已完成（`_check_model_pool_separation`，
> 能准确诊断 writer/jury 池重叠与 jury<5）；② 库重建机制 + stale_marks 迁移 + 统一迁移跟踪
> （`migrate_db`/`schema_migrations`）+ export/rebuild 工具已完成，实测 legacy 库缺 8 张表
> （不止 stale_marks 三表，还有 gate 证据/fact 绑定/repair/schema_migrations），发现并修复
> BFX-092（无统一迁移机制）、BFX-093（schema_authority 游离表）。**正式库已原地替换**
> （rebuild --apply --force 自动备份 legacy 为 .bak×2 后全新建，新库 80 表带齐、参数回灌、
> 游离表清除；两份备份留存）。**doctor 仍非绿但非回归**：报 project_config + model_pool_separation
> 两 fail，与 legacy 库一致，属项目级模型池配置（writer/jury 池相同 3 模型、jury<5），需
> 先配置模型池让 doctor 全绿再进 ③。下一步 ③ 四层契约重产 ch01/02。

## 当前唯一工程 Action

1. **生产运维闭环**
   - ✅ 统一迁移跟踪机制（`migrate_db`/`schema_migrations`/迁移文件）—黄金闭环②完成（BFX-092 修复）；
   - 项目/章节/轮次预算、调用上限、provider failover 和错误分类；
   - 幂等重跑、checkpoint、断点恢复、并发隔离、orphan/stale 巡检；
   - 正式库 WAL/busy timeout/备份恢复（`rebuild_prod_db.py` 已带 `PRAGMA busy_timeout=5000`，但正式库 WAL/备份恢复策略待定）；
   - PostgreSQL 章节锁、RLS、不可变权限和受控 Head 更新函数；
   - secret scanning，并轮换历史文档中暴露过的凭据（BFX-091 明文凭据部分已完成，历史 git 暴露需轮换）。

## 文学质量纵切验收

2. **全新正式库初始化与重产第1、2章**
   - ✅ 全新库初始化机制就位（`rebuild_prod_db.py` 默认 dry-run + `export_legacy_params.py` 只读导参）—黄金闭环②完成；正式库替换待定时机；
   - 全新空库初始化（不迁移旧库），运行 `doctor` 直至全绿；
   - 使用 active 四层 Scene Contract 重产第1、2章；
   - 持久化 Contract、三家族 activation reviews、Generation Round���完整候选 Branch、
     jury 原始结果、Selection/Human Decision、Chapter Review、Snapshot 与 Runtime Event；
   - 第2章只读取第1章 active Snapshot 形成跨章上下文。

3. **预声明阈值的独立人类 A/B**
   - 工业/动作、人物关系/潜台词、过渡/留白三类章节建立固定基线和双盲成对排序；
   - 预先声明文学阈值，不在看完结果后调整；
   - 校准 Scene/Chapter 绝对门槛，禁止直接沿用旧 Shot 分数；
   - 统计人工偏好、候选差异、返工、成本、评审分歧和少数冠军命中。

4. **连续多章稳定性验证**
   - 双章通过后才恢复第3—5章滚动生产；
   - 连续5—10章验证事实、人物声音、时间线、伏笔、模板化、章间同构、悬念和情绪曲线；
   - 建立硬门漏检率、人工退回率、单章轮数/成本、自动门与人类盲评一致率。

## 作者门控

6. **卷级统稿与投稿**
   - 前置：工程纵切和连续多章稳定性验证通过、正文齐备；
   - 卷级人物弧线、伏笔、时间线、信息揭示顺序、节奏与文风统一；
   - 投稿级人工编辑、校对、作者封版、投稿格式 dry-run 与版本 hash 留档。

## P2 扩展

9. 主编台 Scene Contract diff；
10. Scene 边界可视化；
11. Guidance Card 效果分析；
12. 多项目事实同步。
