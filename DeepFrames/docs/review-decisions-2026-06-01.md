# DeepFrames 设计评审 — 问题逐项决策记录

**日期**: 2026-06-01
**已解决**: 数据库切换为 PostgreSQL（DB2/DB3 统一使用 PG，消除 SQLite 并发写入瓶颈 C4-C3）

---

## 决策记录

### #1 AI 管线质量评估 — ✅ 已决策
**选择**: C — 对抗差分
**方案**: 每篇文章跑两套 prompt，QA Agent 标记差异点，人只看差异做选择。不建 golden dataset。
**理由**: 人的判断在对比场景下更稳定；偏好数据可累积复用。

### #2 构建与测试自动化 — ✅ 已决策
**选择**: B → A（Phase 1 用 .bat 脚本，Phase 2 结束后接入 AutoFix）
**方案**: `build.bat` + `test.bat` 立即可用；Phase 2 后注册 AutoFix 场景做自动化闭环。
**理由**: AutoFix 是 DeepBase 内置的本地编译→运行→检测→AI修复闭环，零外部依赖，天然适合 Delphi 体系。

### #3 图像生成一致性 — ✅ 已决策
**选择**: B — 风格参考图（Reference Image / img2img）
**方案**: Group 第一个 shot 的图作为锚点，后续 shot 通过 StepFun `step-image-edit-2` 基于锚点生成。
**理由**: StepFun 已有接口支持，改动小；Phase 1 简单表意路线不追求强一致性，锚点方案足够。

### #4 Style Keeper 机制 — ✅ 已决策
**选择**: B — 降级为确定性规则引擎
**方案**: 从 `style_anchor` + `group_style` 提取约束，从 `background_prompt` 提取实际值，字符串匹配/embedding 余弦相似度比对。不调用 LLM。
**理由**: 约束vs实际是规则匹配问题，不需要 LLM；与 #1 对抗差分方案可对接。

### #5 Worker 生命周期 + 资源管理 — ✅ 已决策
**选择**: A（先验证 DeepBase WorkerQueue 可行性）
**方案**: `TWorkerGuard` 管理 PID/内存上限/定时检查；渲染任务排队；Phase 1 最多同时 1 个渲染任务。

### #6 UI 交互模型 — ✅ 已决策
**选择**: 基于 DeepShell 的五区制（意图区-结果区两区理念 + DeepShell 原生布局）
**布局**:
- **左悬浮窗** (StructureWindow): 项目/文章树 + 版本配置参数面板（风格预设、A/B prompt、目标平台）
- **TopPanel**: [开始生成] [暂停] [导出] 快捷命令
- **MiddleHost**: 三种状态 — 空/生成中摘要/完成时A/B并排对比
- **右悬浮窗** (InspectorWindow): 选中 shot 的参数编辑器 + [重新生成] [对比A/B]
- **BottomPanel**: 任务日志，默认折叠
**理由**: DeepShell 原生五区布局完全匹配意图区/结果区/编辑区的三角色分工；不新建 UI 框架。意图和结果分离，中间纯结果展示。

### #7 DeepBase 全量耦合 — ✅ 已决策
**选择**: 全面集成，不抽象，不保留替代能力
**方案**: DeepFrames 对 DeepBase 的依赖是平台级设计，不是需要防御的技术债。DeepShell 是继承关系，Config/Security/Logging/Persistence 是基础设施，LLM/Speech adapter 是 provider 入口。DeepBase 坏了就修 DeepBase。
**理由**: DeepBase 和 DeepFrames 由同一人维护——架构上不存在"供应商风险"。抽象层只增加调用栈深度，不增加可靠性。

### #8 可观测性 — ✅ 已决策
**选择**: A（Phase 1-2）+ B（Phase 4+ 按需）
**方案**: TopPanel 显示进度、BottomPanel 承载异常/事件（异常时自动展开）。Phase 4 后可选增加任务耗时记录到 DB2 和诊断页。
**理由**: 单人项目只需要进度、异常、事件三个信息，全部用 DeepShell 已有的 TopPanel/StatusBar/BottomPanel 承载，零额外设计。

### #9 Worker 取消机制 + logical_key — ✅ 已决策

**#9a Worker 取消**: A — 进程信号为主，文件为辅
**方案**: 取消 = 先发 CTRL-BREAK → 等 5 秒 → 不退出则 TerminateProcess。cancel_file 保留作辅助信号。
**理由**: Windows 标准做法，Node.js/Python 都有内置 SIGINT 处理。

**#9b logical_key**: A — 分离身份和参数
**方案**: logical_key 只含业务身份（project + content_unit + variant），参数差异走 param_snapshot_json。同一身份的参数变更 = 覆盖旧结果，旧 job 标记 superseded。
**理由**: 身份和参数是两个独立概念，分离后去重逻辑正确且直观。

### #10 剩余问题 — ✅ 已决策

**#10a 黄灯累积**: B — 按类型分组展示
**方案**: 黄灯按 QA 已有的 issue type 分类（风格/时长/情感/覆盖），结果区差异列表按类别分组。不做自动升级为红灯。
**理由**: 分组让用户按类批量决策；对抗差分+结果区模型已经根本性改变了黄灯的消费方式，不需要额外阈值。

**#10b DB 备份**: A + PG 远程接口
**方案**: 当前本地 PG → `pg_dump` 脚本，关键操作前（migration/生成完成后）自动备份到 `{RootPath}\backups\`。同时定义 `IBackupService` 接口（DumpDatabase / RestoreDatabase），当前实现为 pg_dump 调用，未来远程 PG 时替换为远程备份实现。
**理由**: 本地 pg_dump 零依赖；接口边界为远程 PG 预留入口。

### #11 协作能力 — ✅ 已决策
**选择**: A（Phase 1-4）+ B 思路但不用 JSON（Phase 5+）
**方案**: 候选包即审阅包——导出 mp3/mp4 + quality snapshot 发给审阅者，反馈手动处理。Phase 5 后考虑 HTML 审阅包（浏览器可标注）。
**理由**: Phase 1 只需"让别人能看"，不需要"让别人能操作 DeepFrames"。

### #12 TTS 451 自动改写风险 — ✅ 已决策
**选择**: B — 改写 + QA 原文对照校验
**方案**: 允许自动改写，但改写后文本经 QA Agent 语义对比（vs 原文），相似度 > 95% 自动放行，低于阈值标黄灯展示给用户。
**理由**: 大多数 451 只是敏感词碰巧，同义词替换语义不变；QA 在"对比两句话意思是否相同"任务上足够可靠。

### #13 ASR 时间戳精度 — ✅ 已决策
**选择**: A（Phase 1-5 不做卡拉 OK）+ C（规则平滑同步做）
**方案**: 字幕整句显示不做逐字高亮；ASR 时间戳做规则后处理（禁止时间倒退、最小间隔约束）。卡拉 OK 效果推迟到 Phase 7。
**理由**: 整句字幕是 B站/音频平台标准做法；规则平滑去掉明显抖动，半小时写完。

### #14 H.264 专利 — ✅ 已决策
**选择**: B — 记录为 Phase 7 商业化前置条件
**方案**: 在关键约束文档中标注 H.264 专利评估；候选方案 VP9/AV1。当前不改编码。
**理由**: 自用不触发专利风险；AV1 编码速度不可接受（3-5x H.264）。

### #15 Worker 并行与叙事连贯性 — ✅ 已决策
**选择**: B — Assembler 增加叙事连贯性规则检测
**方案**: Assembler 加一条规则：检测相邻 shot 情感跨度 > 2 级标黄灯。不调 LLM，纯规则。不阻塞生产，在结果区展示。
**理由**: 规则检测成本极低；你不需要架构保证完美连贯——你只需要知道哪里断了。

### #16 归并组 A：文档/规范类 — ✅ 已决策（全部不修改）
- E1-L1 表前缀: 不改。E4-L1 命名混用: 不改（各语言惯例）。E5-L1 预设国际化: 不改（自用中文）。
- E1-M1 TS/Delphi 断层: 文档加备注"TS 仅概念说明，Delphi 为唯一契约"。

### #17 归并组 B：Phase 依赖类 — ✅ 已决策（全部按依赖顺序自然解决）
- E2-M1 QA 回流范围: Phase 3 明确。E2-M2 并行度基准: 实测后调参。E3-M1 转场: 随需加。
- E3-M2 FFmpeg 版本: Phase 4 锁定。E3-M3 视觉路线: 已有决策。E4-M1 Migration 工具: Phase 2 选择。
- E4-M2 Worker 版本兼容: 与 #5 一起做。E5-M1 多版本对比: #1+#6 已覆盖。E5-M2 撤销: 版本记录替代 undo。

### #18 事件溯源 — ✅ 已决策
**选择**: A — 不加事件表，依赖现有 prompt_run + quality_gate_result + 版本链
**理由**: 现有三张表已经提供比事件流更强的回溯能力——记录了"为什么变"而不只是"变了"。

---

## 最终评估

### 修订后评分

| 专家 | 原评分 | 修订评分 | 变化原因 |
|------|--------|---------|---------|
| Expert 1 系统架构师 | 7 | **9** | DB→PG 消除存储风险；DeepBase 全量耦合重新定性为平台级设计；logical_key 分离身份与参数 |
| Expert 2 AI/ML管线工程师 | 6 | **8** | 对抗差分覆盖评估缺口；Style Keeper 降级为确定性规则消除模糊性；TTS 451 增加 QA 语义校验；叙事连贯性规则检测 |
| Expert 3 媒体制作工程师 | 8 | **8** | 图像生成一致性通过 img2img 解决；ASR 规则平滑可用；H.264 专利记录为 Phase 7 前置条件 |
| Expert 4 平台/DevOps工程师 | 5 | **8** | CI/CD→AutoFix 零外部依赖；DB→PG 消除并发瓶颈；Worker 信号取消；DB 备份策略落地 |
| Expert 5 产品/UX策略师 | 7 | **9** | 意图区/结果区两区交互模型替换 IDE 布局；黄灯按类别分组；对抗差分匹配选优流程 |

**修订加权平均：8.4/10**（原 6.6/10 → 提升 1.8 分）

### 修订后与原评分的差异分析

原评分低不是因为设计差——核心架构决策（音频/视频双线独立、Video IR、时间轴量化、文档链、DB 三层边界、integration.* 契约）全部正确且优雅。原评分低是因为评审框架假设了一个"商业化、多人团队、独立基础设施"的产品——但这个假设不成立。

修订后的评分基于真实约束重新评估：

| 原评审的隐式假设 | 实际约束 | 影响 |
|----------------|---------|------|
| 需要 CI/CD 服务器（GitHub Actions） | DeepBase AutoFix 已提供本地闭环 | CI/CD 风险消除 |
| DeepBase 是外部框架有供应商风险 | DeepBase 和 DeepFrames 由同一人维护 | 解耦需求消除 |
| 需要多用户协作 | 单人自用工具 | 协作能力降为 Phase 5+ |
| 需要 metrics/tracing/alerting | 用户就是开发者，看 UI 就够 | 可观测性降为 UI 承载 |
| SQLite 适合单机 | 单机但多 Worker 并发写 → 不适合 | DB→PG 解决 |
| Golden dataset 是质量保证唯一途径 | 对抗差分 + 人眼是更精确的评估 | 评估框架转向 |
| UI 应该是创作工具范式 | DeepShell 五区制已覆盖意图/结果/编辑三个角色 | UI 设计重置 |

### 未消除的风险（接受为设计约束）

| 风险 | 严重度 | 接受理由 |
|------|--------|---------|
| Delphi VCL Windows-only | 低 | 自用版目标就是 Windows；FMX 作为未来选项保留在文档中但不承诺时间表 |
| 单人 bus factor | 中 | 单人项目固有的 bus factor，不通过架构解决 |
| Remotion 商业许可未评估 | 低 | HyperFrames 优先，Remotion 不阻塞 Phase 1-5 |
| 视觉表达路线演进不明确 | 低 | "简单表意优先"已是明确决策；Phase 5 后基于实际效果讨论下一步 |

### 设计优势（自原评审保留并强化）

1. 音视频双线独立架构 — 核心设计亮点
2. Video IR 中间表示 — 隔离渲染后端变更
3. 文档链可追溯性 — 从 source 到 package 的完整版本链
4. 双时间戳坐标系 — local + global 设计
5. 全局时间轴量化算法 — 防止帧累计漂移
6. 质量门控分级策略 — pass/warn/fail + 可配置控制点
7. DB1/DB2/DB3 边界 + PG — 配置/业务/集成清晰分离
8. ArtifactOS integration.* 契约 — 跨系统边界典范
9. 候选包概念 — 生产与发布解耦
10. 降级策略 — 时间轴完整性兜底
11. **新增**：意图区/结果区 DeepShell 五区交互模型 — 简洁且匹配实际工作流
12. **新增**：对抗差分 + A/B 并行选优 — 人机分工正确
13. **新增**：AutoFix 构建闭环 — 零外部依赖的质量保障