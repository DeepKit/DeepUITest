# Ink v2 Scene-first 当前任务

> 只记录未完成任务。已完成内容移入 `history.md`，缺陷闭环见 `bugfix.md`。
> 当前法源：`docs/README.md`、`docs/design.md`、`docs/implementation-contract.md`、
> `docs/invariant-traceability.md`。
>
> **2026-07-16 对齐**：BFX-084 AI Repair Task 血统、BFX-085 Contract supersede/stale
> 传播、BFX-086 Accept 权威事务均已完成并归档。旧 Shot 产物及 BFX-079 前的第1/2章
> 不能作为当前四层 Scene Contract 架构的质量证据。

## 当前唯一工程 Action

1. **Scene-first AI 权限与受保护权威表 SQL 静态门**
   - 为 AI 不可 Accept、Activate、Freeze、更新 Chapter Head 补齐运行时反事实证据；
   - 扩展 `sql_access` lint，阻断 CLI/pipeline 绕过 Repository 直接读写 Scene-first
     权威状态表；
   - 收口扫描发现的真实旁路，不以扩大白名单代替修复；
   - 登记 `INV-AUTH-*` / `INV-SQL-*`，执行 H1-H4 与全量回归。

## 后续工程队列

2. **Scene-first Accept 完整质量硬门**
   - 将 Scene 完整性、Chapter 文学质量、Book 跨章 blocking issue、伦理硬门接入
     `accept_chapter()` 的权威事务；
   - 缺证据、证据过期或任一硬门失败时 fail-closed；
   - 人类 override 不得越过确定性质量/伦理失败。

3. **正式 Export 单一权威与防旁路**
   - 正式 export 只读 active、sealed、non-stale Chapter Snapshot；
   - 禁止未 Accept 候选、stale lineage 或 legacy Shot 混入正式书稿；
   - 增加生产源码 SQL/read-path lint 与可追溯 artifact metadata。

4. **旧生产库迁移与 Cutover**
   - 幂等 migration、Scene 边界 dry-run、低置信边界人工裁定；
   - Scene/Revision/Branch/Snapshot 影子回填；
   - legacy export 与 Snapshot export hash parity；
   - authority marker、写冻结、Cutover 与回滚演练；
   - Cutover 后 legacy Shot 只读。

5. **Fact 与 Guidance 生命周期**
   - Fact Proposal 的 proposed/verified/rejected/superseded 生命周期、来源和审核证据；
   - Fact 变化触发 Contract/Revision/Branch/Snapshot stale 传播；
   - Guidance/Anti-pattern Card 的范围、冷却、次数、撤销、防照抄和效果归因。

6. **生产运维闭环**
   - 项目/章节/轮次预算、调用上限、provider failover 和错误分类；
   - 幂等重跑、checkpoint、断点恢复、并发隔离、orphan/stale 巡检；
   - 正式库 WAL/busy timeout/备份恢复；
   - PostgreSQL 章节锁、RLS、不可变权限和受控 Head 更新函数；
   - secret scanning，并轮换历史文档中暴露过的凭据。

## 文学质量纵切验收

7. **当前架构重产第1、2章**
   - 正式数据库 doctor 全绿后，使用 active 四层 Scene Contract 重产；
   - 持久化 Contract、三家族 activation reviews、Generation Round、完整候选 Branch、
     jury 原始结果、Selection/Human Decision、Chapter Review、Snapshot 与 Runtime Event；
   - 第2章只读取第1章 active Snapshot 形成跨章上下文。

8. **预声明阈值的独立人类 A/B**
   - 工业/动作、人物关系/潜台词、过渡/留白三类章节建立固定基线和双盲成对排序；
   - 预先声明文学阈值，不在看完结果后调整；
   - 校准 Scene/Chapter 绝对门槛，禁止直接沿用旧 Shot 分数；
   - 统计人工偏好、候选差异、返工、成本、评审分歧和少数冠军命中。

9. **连续多章稳定性验证**
   - 双章通过后才恢复第3—5章滚动生产；
   - 连续5—10章验证事实、人物声音、时间线、伏笔、模板化、章间同构、悬念和情绪曲线；
   - 建立硬门漏检率、人工退回率、单章轮数/成本、自动门与人类盲评一致率。

## 作者门控

10. **卷级统稿与投稿**
    - 前置：工程纵切和连续多章稳定性验证通过、正文齐备；
    - 卷级人物弧线、伏笔、时间线、信息揭示顺序、节奏与文风统一；
    - 投稿级人工编辑、校对、作者封版、投稿格式 dry-run 与版本 hash 留档。

## P2 扩展

11. 主编台 Scene Contract diff；
12. Scene 边界可视化；
13. Guidance Card 效果分析；
14. 多项目事实同步。
