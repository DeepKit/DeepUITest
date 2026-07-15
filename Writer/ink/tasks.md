# Ink v2 Scene-first 当前任务

> 只记录未完成任务。已完成内容移入`history.md`。
> 当前法源：`docs/README.md`、`docs/design.md`、`docs/implementation-contract.md`
>
> **2026-07-15 对齐**：补登 5 块已完成工作（质量门真实化 A/B/C、章节悬疑
> 三层注入、工业事实漂移检测器解耦、通用章纲注入链路、P0-3/5 不变量测试
> 11 条）至 `history.md`；缺陷登记 BFX-068~071 至 `bugfix.md`。以下任务据此
> 校正进度。
>
> **2026-07-15 FastMeet 决议（Sol/GLM-5.2/StepFun 三家共识）**：《白灯法则》
> 7-30 投稿死线，旧 Shot 生产线产物全部作废，直接在 Scene-first 真实模型链路
> 产新稿。**唯一 P0 = 收口端到端生产命令 + 用第1章纵切验证 + 逐章滚动**。原
> Scene-first 闭环 P0 项（Accept/Export、四层双师、旧库迁移等）降级为死线后
> 推进，不阻塞投稿。质量门与停止规则硬编码：单章 2 轮上限、winner≥85、关键
> 维度≥80、底线 80、超时取最高分带缺陷接受；7-28 24:00 产稿硬截止。

## P0：白灯 7-30 投稿冲刺（唯一主线，压倒一切）

1. **Day1-2：收口 `ink produce-chapter` 端到端命令**（进度：**命令已实现 +
   deterministic 端到端冒烟通过 + `--no-accept`/续 force-accept 闭环验证 +
   真模型烟测链路实证**，见 history 2026-07-15；剩余：BFX-074 修复后产出真 winner）
   - 章纲注入 → `GenerationRoundDriver`（真实模型产 2 候选）→ `RealSelectionPort`
     选优 → jury 真实审 → `scene_accept` 落库 → `scene_export` 导出封版正文；
   - 硬能力：可恢复（run ID + 检查点）、幂等（重复执行不重复落库/不覆盖封版稿）、
     全程留痕（候选稿/jury 原始分/门禁结论/接受版本/导出校验值）、可人工接管
     （指定候选强制接受）；**deterministic 冒烟已验证全链路编排无 bug**
     （generate→validate→diff→select→accept→export，3 候选 2 轮 accepted:true）；
   - **`--no-accept` + 续 force-accept 已实现**：ch01 重校"产出不封版交裁定"
     语义——`--no-accept` 产 frozen winner 不封版 + 导出候选稿，作者裁定后
     `--force-branch-version-id` 续封版（force 模式免 outline-file）；
   - **真模型烟测进展（2026-07-15）**：`LOCAL_PROXY_KEY`+`INK_LLM_API_KEY` 双设
     +`openai-compatible` 真实命中本地代理 claude-xunfei-deepseek-v4-pro，
     generation（draft×3）→BRANCH_FROZEN×3→validation（chapter_review×3）全
     SUCCEEDED，新 role-config 链路实证打通（见 history 同日条目）。
   - **真 winner 已产出（2026-07-15）**：BFX-074 RESOLVED（见 1.5）后，`run_bfx074_diag.py`
     二跑 `final_status=selected`、`winner_branch_version_id=2`，branch 1 = selected。
     剩余：`scene-accept` 封版 + 纵切验收（见任务 2）。
   - **不做**：旧库 Cutover、通用 UI、复杂编排、旧 Shot 兼容。

1.5. **【已完成】BFX-074 真模型 validation 0 过门**（2026-07-15 RESOLVED，详见
   bugfix.md BFX-074/075/076）——根因订正：非过严，是 BFX-075（init 静默 seed
   `provider="mock"`）致真链路走桩；加 `INK_LLM_*` 环境变量绕过后，真模型 jury
   （glm-5-2 单 judge）实测打 85-96 高分，floor=75 合理，候选1/2 passed、候选3
   failed。`run_bfx074_diag.py` 二跑全程通过：`final_status=selected`，
   `winner_branch_version_id=2`，winner 已产出待 `scene-accept` 封版。BFX-076
   （selection UNIQUE 冲突）偶发不阻塞。**阻塞解除，进入第1章纵切验证**。

2. **【已完成】Day3：第1章纵切验证**（2026-07-15，详见 history 同日"纵切闭环"+"BFX-077 修复"）
   - **机械闭环（首跑）**：章纲启动 → 真 jury 7 维（9 attempt success）→ winner
     selected → `scene-accept` 封版（head_version=1）→ 导出与接受版本 hash 一致
     → 库状态可核验。**但发现导出正文是"江辞/陆衍希"言情线，非白灯第1章。**
   - **BFX-077 修复**：`_generation_prompt` 第三段漏 `f` 前缀 → `{brief}` 字面
     不插值 → 模型只收 82c 无 brief prompt（token_input=54）→ 自由发挥写言情。
     补 `f` 后 brief 进 prompt（token_input 54→321）。
   - **实质达标（修复后重跑）**：三候选正文全含白灯人设（许怀山/吕素琴/硫化/
     返潮/装车），零言情残留；7 维评分 93-99（character_voice 98 /
     scene_concreteness 99 等）；winner=branch_version 3 封版（head_version=1），
     导出 7064B 白灯正文（许怀山/硫化车间/第十七批/攀枝花）。
   - `--no-accept` + `scene-accept --branch-version-id` 续封版已验证。
   - **第1章白灯 ch01 真正文已封版产出**（`.bfx074/exported_ch01.md`，7064B），
     待作者裁定是否接受为正式第1章（见 memory ch01-redo-timeline，产出不封版
     交裁定——此处封版仅指管线 head 落库，不等于作者文学裁定）。
   - 纵切通过（机械闭环+实质达标），数据契约/质量门/产物目录已冻结，暂停架构
     重构进入逐章生产。

2.5. **【阻塞·P0】五专家连续评审暴露生产流程三个机制缺陷**（2026-07-15，
   评审报告 `AWT-20260715-171440-5aaf49`，详见 history 同日条目）
   - 第1章 7.2 / 第2章独立 7.5 / **两章连续 7.1**——句子物件氛围已超过
     结构完成度。评审定位三个 P0：
   - **P0-1 章节同构（生产流程主因）**：第2章重演第1章的装车/签字/卡车驶离。
     **根因确诊**：跨章 context 注入工程把前章封版正文**头+末各300字原文**
     注入后章 brief，模型把前章场景当"本章要复现的设定"复述，淹没章纲要求
     的新事件。实证：第2章开头400字整段重演装车签字，封条×3/装车×5/卡车×2。
     **当时验收"复现四二零四配方"实为重复病根**（复述≠续接）。memory
     `ink-context-injection-raw-text-backfires`。
   - **P0-2 完整因果链（设定层+流程层）**：大纲"冲突"字段把"密封件异常→
     前线哑弹"完整因果写死在一张卡，模型一次性铺给吕素琴。评审要求"每人只
     看一段"。修法需大纲拆视角信息边界 + 流程加视角契约字段。
   - **P0-3 科幻锚点缺失（设定层）**：大纲无"未来回环"字段，brief 不含
     2063/许望舒/衡光信息，模型写成纯工业厂史。修法需大纲加未来回环字段(1-3行)。

   **优化方案（生产流程侧，P0-1 为主，需作者裁定后实施）**：
   - **A. context 注入重做**（修 P0-1，最高优先）：context 不给正文原文，改给
     **结构化前情摘要**——分点"上一章已发生①…②…"，每点标"已发生,勿复述"。
     来源优先用封版时大纲的`章末钩子`字段(本就结构化)，次选小模型抽动作清单。
     prompt 显式约束"本章从新事件起笔,不得重演前章动作"。验收从"复现前章细节"
     改为"新事件起笔+前情作隐含背景不正面复述"。
   - **B. 视角契约字段**（修 P0-2）：章纲加`本章人物已知/未知信息`字段，
     prompt 约束角色信息边界，禁止单角色持有完整因果链。
   - **C. 未来回环字段**（修 P0-3）：章纲加`未来回环锚点`字段(1-3行)，
     brief 注入，prompt 要求章末或章中嵌一处极短未来回声(2063档案/许望舒读取/
     衡光案例库一行)。
   - **当前状态**：第3章已产稿(branch_version 8, selected 未accept)暂停审阅；
     逐章滚动暂停，等 A 实施后重产第2章验证同构消除，再续第3章及之后。
     B/C 涉及大纲修改，属作者裁定项，不在流程侧擅自改。

3. **Day4-11：逐章滚动生产（第2-5章 + 序章）**【暂停，待 P0-1 context 重做】
   - **生产线库**：新建正式白灯线库 `baideng_prod.db`（project_id=1，真模型池
     deepseek/glm/kimi 已 seed，2026-07-15 建）。不复用诊断库 baideng_bfx074_diag。
   - **【已完成】跨章 context 注入**（2026-07-15，详见 history 同日条目）：
     `brief_builder` 加 `_prev_chapter_context`——产第 N 章 brief 时取第 N-1 章
     封版正文头+末各 300 字注入 prompt（字数约束保持最末）。零额外 LLM 调用、
     token 可控、第1章/未封版/无 conn 三场景 graceful skip。`build_chapter_brief`
     签名扩 `conn/project_id` 可选（向后兼容）。`cli.py` produce-chapter 传 conn。
     单测 5 条全过 + real_ports/driver 回归 12 测全绿。
   - **【已完成】正式库产第1章封版 + 第2章带 context 产稿**（2026-07-15）：
     baideng_prod.db 第1章 3 候选1轮 winner=branch_version 3，正文 7938B 含
     许怀山×10/吕素琴×10/硫化×5/油纸包×4/返潮×1，零言情残留，accept 封版
     （snapshot_id=1）。第2章 brief 含前章 context（头300"一九七九年四月十七
     …许怀山…装车台…四二零四配方"+末300"烟囱的影子长长地投在空了的装车台"），
     产稿 winner=branch_version 4 正文 6639B 续接前章伏笔（油纸包×4/一九七八×5/
     密封件×5/装车×5/硫化×4），模型准确复现"第十七批 一九七九年四月十五日下线
     接口密封件 硫化橡胶 四二零四配方"——证明 context 真进 prompt 且被用于续接。
     accept 封版（snapshot_id=2）。详见 history 同日条目。
   - **逐章封版表**（2026-07-15 更新）：
     | 章 | 状态 | winner_branch | 封版snapshot | 重试 | 备注 |
     |----|------|---------------|--------------|------|------|
     | 1  | 已封版 | 3 | 1 | 0 | context 源,7938B |
     | 2  | 已封版 | 4 | 2 | 0 | 带前章context,6639B |
     | 3  | 未开始 | - | - | - | 下一步 |
     | 4  | 未开始 | - | - | - | |
     | 5  | 未开始 | - | - | - | |
     | 序章 | 未开始 | - | - | - | |
   - 每章：产2候选 → jury → 过门 accept/export/人工快审；
   - 2轮全章上限，第3轮起只做局部重写或人工修补；达预算取最高分带缺陷接受进卷级编辑队列；
   - 硬门（结构完整/场景无缺/无截断泄漏/无提示词泄漏/Scene-候选-jury-导出可追溯）失败必修；评分门（winner≥85，关键维度≥80，底线80）筛选用；人工门只审致命问题不逐句润色；
   - 每日核对剩余章数×单章周期是否超剩余时间，超即降级。

4. **Day12-14：卷级统稿**
   - 跨章一致性（人物/伏笔/时间线/信息揭示顺序）、文风统一、语言润色（六章齐备后一次做，不前期反复精修）。

5. **Day15：故障缓冲 + 投稿材料**（7-28 24:00 产稿硬截止，7-29~30 仅统稿/排版/投稿）

## P1：Scene-first 闭环（死线后推进，当前不阻塞）

> 以下为原 Scene-first P0，投稿死线内不推进，7-30 后恢复。进度已标，见上文。



1. **Chapter Accept与Export闭环**
   - 在现有Snapshot/CAS事务中加入Selection Decision、Human Decision和Runtime Event；
   - 接入Scene、Chapter、Book及伦理硬门；
   - 明确human actor权限，阻断AI Accept、Activate和更新Chapter Head；
   - 新增只读active Snapshot的正式export路径；
   - `accepted_decision_id`生产路径改为必填，禁止测试用NULL语义进入正式Accept；
   - 在Cutover前保持旧export不变，禁止双正文权威。

2. **Scene Contract四层与双师**（部分进度：四层装配 + 双师盲审不变量已过，见 history 2026-07-14 §5）
   - **已完成**：hard constraint/source DNA/soft goal/creative opening 四层装配（需两个 creative opening）；契约架构师自检、独立复审师、人类激活；reviewer family/blind context/prompt hash/独立性证据；阻断 AI 激活契约；复审序号按 contract 自增。
   - **剩余**：generation/repair task 从“非空 ID”升级为存在性、项目/章节作用域和有效状态校验；
   - **剩余**：实现 amendment、supersede 和 stale 传播（amendment 已记血统不改 clause，supersede/stale 落地待续）。

3. **评审与文学选优**
   - Scene资格门和Chapter绝对文学门槛；
   - blind pairwise ranking、Pareto保留和少数冠军；
   - 同构候选阻断；
   - 选优对象只能是完整Chapter Candidate Branch。

4. **事实认定与指导卡**
   - Fact Proposal生命周期，unknown不得当作false；
   - Guidance/Anti-pattern Card；
   - 最佳示例按需注入、反照抄、最大使用次数、冷却、撤销和效果归因；
   - 返工先归因，再决定是否增减契约或注入示例。

5. **旧生产库安全迁移**
   - 为既有SQLite文件库提供幂等migration；不能只修改新库`schema.sql`；
   - Scene边界dry-run和低置信人工裁定；
   - 影子回填Scene、Revision、Branch和Snapshot；
   - 旧导出与Snapshot导出hash parity；
   - 写入冻结、一次Cutover和回滚演练；
   - 实现并验证schema authority marker；
   - Cutover后legacy Shot只读。

6. **剩余Scene-first不变量**（进度：测试 3/5 已过，11 条全绿，见 history 2026-07-14 §5）
   - **已完成（3/5）**：四层装配、契约双师盲审、AI 不能激活、amendment 记血统、Guidance Card 生命周期、事实提案人-only 门 + 写 anchor、accept 需 decision_id。
   - **剩余（4/5）**：Accept Decision/Event 故障注入事务；
   - **剩余（4/5）**：AI 权限和受保护表 SQL lint；
   - **剩余（5/5）**：export 只读 active Snapshot；
   - **剩余（5/5）**：migration parity、Fact、Guidance 和 stale 传播；
   - 详见 `docs/invariant-traceability.md`。

7. **Repository与数据库边界加固**
   - 普通业务模块不得直接写Scene/Branch/Snapshot权威表；
   - 增加Scene-first SQL access lint；
   - 为写事务补Runtime Event；
   - PostgreSQL实现章节级锁、RLS和不可变权限；
   - SQLite真实文件库验证WAL、busy timeout与并发冲突；
   - `freeze_branch_version`接入必要Scene完整性、Contract、Fact和质量门；
   - Contract激活和Branch选择写入actor、Decision及Runtime Event。

8. **凭据处置**
   - 轮换曾出现在历史文档中的真实凭据；
   - 检查Git历史、日志和备份；
   - 增加secret scanning。

## P1：真实质量验证（进度：真实模型本地代理 10 章 e2e 已通，见 history 2026-07-14 §2~§4）

> 注：悬疑三层注入 / 工业事实漂移检测 / 通用章纲注入已��地为**影子层 +
> 真实模型 e2e**（10 章压测 winner 85+、suspense_tension 82–92），但**未切
> 生产 CLI、未改旧 Shot 生产路径**。以下为把该 e2e 收口成可投产 A/B 的剩余项。

1. 工业/动作章节A/B（e2e 链路已通，剩余：固定对照基线 + 双盲成对排序，产出可对比的 A/B 报表）；
2. 人物关系/潜台词章节A/B（链路同上，需补潜台词契约维度，当前 jury 只审 suspense_tension）；
3. 过渡/留白章节A/B（需补留白契约维度与对应 jury 准则）；
4. 统计作者偏好、候选差异、返工、成本、评审分歧和少数冠军命中（e2e 已产出 winner/suspense 分数，需落统计聚合与成本记账）；
5. 校准Scene/Chapter质量阈值，禁止直接沿用旧Shot分数（真实 jury 分已产出，需据 10 章基线校准绝对门槛）。

## P2：扩展

1. 主编台Scene契约diff；
2. Scene边界可视化；
3. Guidance Card效果分析；
4. 多项目事实同步。
