# 演擎 ArtifactOS

> 源体系驱动的通用媒体产出物操作系统

演擎 ArtifactOS 是一个把源体系、AI 生成、产出契约、媒体发布、反馈信号和人类裁决连接起来的通用媒体产出物操作系统。它的目标不是治理 AI，也不是只生成文章，而是让理论、品牌、产品资料、方法论、研究材料等可装载输入，稳定转化为可发布、可追溯、可校正、可反哺的媒体产出物，用于持续推广、传播放大和节省人工。

从产品类别看，它是一类产出物操作系统（Artifact Operating System）：内容只是外显载体，核心是管理源体系到产出物、发布痕迹、反馈证据和人类裁决之间的长期链路。

当前冻结的内核命题是：`Source-to-Artifact Production and Amplification Kernel / 源体系到产出物生产与放大内核`。权限、门禁、事件账本、能力注册和人类介入策略都是后台保障机制，必须服务于合格产出物生产与传播，不得反客为主扩展成通用 AI 管理平台。

## 品牌结构

| 子品牌 | 英文名 | 职责 |
|--------|--------|------|
| 观象 | SignalScope | 现实信号、热点、异常和研究问题发现 |
| 论演 | TheoryWeave | 理论映射、解释假设和观点推导 |
| 证链 | ClaimGraph | 断言、证据、反证和认知轨迹 |
| 行铸 | PraxisForge | 内容、研究、发布和策略行动 |

## 开发入口

| 文件 | 说明 |
|------|------|
| `DEVELOPMENT.md` | 开发前准备：环境、数据库、测试、发布边界、可认领任务和裁决事项 |

## 与 BCW / DeepFrames 的职责边界

```text
老板 / BCW
裁定目标、账号身份、SourcePack边界、实验命题、授权与停止条件
        ↓ 版本化 decision package
ArtifactOS
编译契约、排程、质量门禁、发布、留证、反馈和治理候选
        ↓ production contract
DeepFrames
生产视频、图文、封面、字幕、配音和候选资产包
```

这是个人单用户系统：ArtifactOS 在已应用策略范围内自动运行，但不得自行修改账号使命、理论法源、唯一主平台和重大资源比例。需要改变这些内容时，在结果摘要中提示老板。

ArtifactOS 不直接读取会议纪要，只导入Amy从BCW active决议生成的简洁YAML `decision_package`。导入时显示变更摘要，确认后应用，并保留上一版快照用于回退。

配置完成后，BCW/Amy通过ArtifactOS CLI继续安排运营和生产：

```text
artifactos bcw apply
artifactos config show|set
artifactos cycle plan
artifactos batch create
artifactos guide set
artifactos production run
artifactos schedule show
artifactos status
artifactos report
```

CLI负责把BCW的周期安排和生产指导转成ArtifactOS运行对象及DeepFrames内容契约。所有写命令应支持`--dry-run`，所有命令应支持`--json`，供Amy稳定调用。

详细接口规格：

- ArtifactOS侧：`docs/27.[协议]-BCW决议接入与治理回流-BCW-Interface.md`
- BCW侧：`D:/_Progs/.BetterCiv/08_元管理/BCW/protocols/bcw-artifactos-interface.md`

## 文档入口

### 蓝图（01-03）

| 编号 | 文件 | 说明 |
|------|------|------|
| 01 | `01.[蓝图]-产品蓝图-Blueprint.md` | 总愿景、品牌架构、核心对象、阶段边界、硬约束、第一接管面 |
| 02 | `02.[蓝图]-系统架构-Architecture.md` | 四子品牌、九大执行系统、数据流和存储边界 |
| 03 | `03.[蓝图]-实施路线图-Roadmap.md` | Phase 0-6 实施路线、七级能力闭合度、技术选型 |

### 模型（04-07）

| 编号 | 文件 | 说明 |
|------|------|------|
| 04 | `04.[模型]-案场与产出物模型-Case-Artifact-Model.md` | 案场时间层级、片场/子片场、复合产出物、蓝图、门禁、信号归因、决策压缩、候选路由、表达多样性 |
| 05 | `05.[模型]-写作契约-Contract.md` | 契约结构、RSC/CTF、认知字段和结构门禁 |
| 06 | `06.[模型]-状态机规范-State-Machine.md` | 状态轴、转换规则、Flags、跨对象联动和边界状态 |
| 07 | `07.[模型]-SourcePack装载-Loading.md` | Part A 通用 SourcePack 装载契约、Part B 一元论首个样板 |

### 流程（08-14）

| 编号 | 文件 | 说明 |
|------|------|------|
| 08 | `08.[流程]-选题漏斗-Topic-Funnel.md` | 观象 SignalScope、热点/理论双入口、写/不写判断 |
| 09 | `09.[流程]-素材库-Material-Library.md` | 素材原子、证据来源、版本和召回影响 |
| 10 | `10.[流程]-账号矩阵-Account-Matrix.md` | 账号画像、策略单元和认知成熟度 |
| 11 | `11.[流程]-写作流水线-Writing-Pipeline.md` | 上下文组装、自动生成、重写和抽检校准 |
| 12 | `12.[流程]-质量门禁-Quality-Gate.md` | 分层门禁、源体系忠实度、EvidenceClaim、PackageGate、SelfCertificationGate 和边界决策 |
| 13 | `13.[流程]-多平台发布-Publishing.md` | 行铸 PraxisForge、发布、召回、PublishingAdapter 协议和证据封存 |
| 14 | `14.[流程]-任务调度-Scheduler.md` | 案场调度、子片场执行任务、认知状态、事件日志和调度模式 |

### 交互（15-18）

| 编号 | 文件 | 说明 |
|------|------|------|
| 15 | `15.[交互]-Amy工作台-Amy-Desk.md` | Amy 办公桌、工作卡、每日精选审阅、1-8/9/0 准备动作协议、注意力预算 |
| 16 | `16.[交互]-微信通道-WeChat.md` | Amy 微信工作汇报接口、日报入口、动作等级、回复命令 |
| 17 | `17.[交互]-前夜审阅与影子运行-Evening-Shadow.md` | Part A 前夜审阅协议、Part B 首个 7 天影子运行规格 |
| 18 | `18.[交互]-交互修改与遗忘-Interaction-Forgetting.md` | Part A 交互修改与反馈沉淀、Part B 片场秘书、批量总编台与遗忘系统 |

### 认知（19）

| 编号 | 文件 | 说明 |
|------|------|------|
| 19 | `19.[认知]-证据认知与进化-Evidence-Evolution.md` | Part A 进化控制台（灯号、黄灯协商、AutoTune）、Part B CognitionTrace、EvidenceClaim、ClaimGraph |

### 治理（20）

| 编号 | 文件 | 说明 |
|------|------|------|
| 20 | `20.[治理]-会议体系与计划治理-Meeting-Governance.md` | 年会、半年会、季度会、月会、周会、日晨会协议，计划增减调整和字段级变更权限 |

### 商业（21-23）

| 编号 | 文件 | 说明 |
|------|------|------|
| 21 | `21.[商业]-用户画像与价值-User-Profile.md` | 目标购买者、商业化切口、用户问题和价值主张 |
| 22 | `22.[商业]-试点与信任-Pilot-Trust.md` | 商业化证据阶梯、试点 Offer、指标、Solo/Org 模式和数据信任边界 |
| 23 | `23.[商业]-外部协议-External-Protocols.md` | Part A 吸引信号交接协议、Part B 旧系统迁移与退出计划 |

### 数据（24）

| 编号 | 文件 | 说明 |
|------|------|------|
| 24 | `24.[数据]-数据库模型与治理-Database.md` | PostgreSQL 表结构、统一案表、约束、触发器、Guard DDL、迁移顺序 |

### 审计（25）

| 编号 | 文件 | 说明 |
|------|------|------|
| 25 | `25.[治理]-审阅整改记录-Review-Ledger.md` | 七轮专家审阅结论、已整改项、实现阶段重点检查、跨文档一致性审计和保留建议 |

### 技术（26）

| 编号 | 文件 | 说明 |
|------|------|------|
| 26 | `26.[技术]-技术选型与运行时架构-Stack-Decision.md` | VCL Desk、Delphi Engine、PG 直连、DeepBase 复用、AutoFix 和 Python 诊断层决策 |
| 27 | `27.[协议]-BCW决议接入与治理回流-BCW-Interface.md` | BCW decision package、Amy运营CLI与result summary简化协议 |
| 28 | `28.[审计]-Amy自主运营对象与CLI缺口-Amy-Operations-Audit.md` | 十个运营对象映射、CLI实测、P0缺口和首个合同级dry-run |
| 29 | `29.[架构]-PG中心化运行真相源优化方案-PG-Centered-Runtime.md` | PG唯一运行真相源、JSONB、受控Skill、Worker、fencing和跨机资产协议 |

## 运行配置库恢复

`ArtifactOSConfig.db`（SQLite，DB1）不在 git 跟踪中——它含运行时 Secrets（PG 密码，DPAPI 用户级加密）和 Logs，每次运行都会变。仓库只跟踪脱敏的 **`ArtifactOSConfig.seed.db`**（纯结构 + 静态种子数据，Secrets 置空）。

**数据库损坏/丢失时恢复：**

```bash
# 1. 从种子重建结构 + 静态数据（Settings/I18n/Languages/Themes/Categories 等）
cp ArtifactOSConfig.seed.db ArtifactOSConfig.db

# 2. 写入 PG 凭据（DPAPI 加密落 Secrets 表）
ArtifactOS.exe --set-secret ArtifactOS.DB.User fuyi01
ArtifactOS.exe --set-secret ArtifactOS.DB.Pass <your-pg-password>

# 3. 或用环境变量作 dev fallback（不落库）
export ARTIFACTOS_DB_USER=fuyi01
export ARTIFACTOS_DB_PASS=<your-pg-password>
```

凭据经 `LoadSecret`（首选，DeepBase DPAPI）→ 环境变量（dev fallback）→ `GetConfig`（明文 Settings，不推荐）三级解析（见 `ArtifactOS.Core.DB.Connection.pas`）。测试用 `ArtifactOSTestsConfig.db` 同理，由测试 runner 生成、已忽略。

