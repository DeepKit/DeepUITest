# OCGS.090-深导DeepGuide统一产品体系

> 文档性质：产品体系整合终稿
> 日期：2026-05-12
> 状态：圆桌讨论整理稿
> 核心原则：一个底座，多个产品
> 统一品牌名：深导 DeepGuide
> 主持人：Claude
> 专家：张明远（商业化）/ 赵天宇（架构）/ 林薇（行业）/ 周恒（AI）/ 陈晓峰（市场）

---

## 0. 本文件定位

本文件将此前所有讨论中出现的多条产品线整合为**一个统一体系**，以深导 DeepGuide 为唯一品牌，以"一个底座、多个产品"为架构原则。

整合范围：

```text
整合进来：
  OCGS 理论方法（作为底座方法，不作为产品管理）
  深演·明理 DeepExplorer（→ 深导·教学）
  深演·旅图 DeepJourney（→ 深导·展示）
  DeepGuide Studio / Coach / Package
  深测 DeepUITest（→ 深导·测试）
  OCGS-se（→ 深导·工程治理）
  OCGS-Delphi / ActionGrid（→ 深导·Delphi）
  善用（→ 深导轻量入口）
  13 个行业分版（→ 行业配置包）

不纳入深导体系：
  深启 DeepLaunch — Windows 遥控器，独立产品线
  ShineOps — 灯塔内容运营系统，独立产品线
```

---

## 1. 关键决策记录

### 1.1 命名统一

```text
最终品牌名：深导 DeepGuide
不再对外使用的名称：DeepJourney、DeepExplorer、深演·明理、深演·旅图
内部可保留的历史代号：DeepJourney、DeepExplorer
OCGS-se 对外称：深导·工程治理
OCGS-Delphi 对外称：深导·Delphi
行业版命名：DeepGuide for + 行业名（非独立产品名）
```

### 1.2 B 类与 C 类合并

此前 B 类（深演 APP：教学器 + 展示引擎）和 C 类（深导企业版：Studio + Coach）作为两条独立产品线。现合并为深导统一体系下的四个前端产品。

### 1.3 行业分版降级为配置包

13 个行业版不再作为独立产品，改为底座之上的行业配置包。新增行业 = 新增配置包，不改底座代码。

### 1.4 理论不作为产品管理

OCGS 理论是底座方法，不是产品。对内指导产品设计，对外不直接销售。

---

## 2. 总架构

```
深导 DeepGuide
│
├─ 底座 DeepGuide Platform
│   ├─ Journey Schema           统一旅程数据模型
│   ├─ Journey Runtime          路由 / 门禁 / 恢复 / 留痕引擎
│   ├─ Validator                Schema 校验 + 语义校验 + DryRun
│   ├─ Risk Engine              风险分级 / 确认 / 阻断
│   ├─ Trace Engine             证据链 / 版本追踪
│   ├─ AI Layer                 辅助编排 / 受控匹配 / 卡点分析
│   └─ Industry Adapter         术语映射 / 扩展字段 / 风险规则
│
├─ 产品 1：深导·编排    DeepGuide Studio
├─ 产品 2：深导·陪跑    DeepGuide Coach
├─ 产品 3：深导·展示    DeepGuide Showcase
├─ 产品 4：深导·教学    DeepGuide Teach
├─ 产品 5：深导·深用    DeepGuide for Software
├─ 产品 6：深导·深客    DeepGuide for Service
├─ 产品 7：善用
├─ 产品 8：深导·测试    DeepGuide Test
├─ 产品 9：深导·Delphi  DeepGuide for Delphi
│
└─ 行业配置包（11 个）
    ├─ for Tax / for Government / for Banking / for Insurance
    ├─ for Healthcare / for HR / for Education / for Quality
    └─ for Store / for Park / for Compliance
```

---

## 3. 底座：DeepGuide Platform

所有产品共享的技术底座。底座不直接面向用户销售，通过产品端间接服务。

### 3.1 Journey Schema

统一旅程数据模型，融合原 scenario.json 和 BusinessJourneyPackage。

核心对象：

```text
Package         旅程包元信息
Output          宝物定义
IntentTrigger   意图触发
Journey         业务旅程
Field           场域
AccessGate      门禁
GateCondition   门禁条件
GuideCard       图卡
RouteRule       路由规则
RiskPolicy      风险策略
LostRecovery    迷路恢复
TraceSchema     留痕结构
TestCase        测试样例
HumanDecisionLog 人类决策记录
VersionRecord   版本记录
```

### 3.2 Journey Runtime

执行引擎，负责：

```text
加载旅程包
识别当前 Field
判断 GateCondition
执行 RouteRule
触发 RiskPolicy
进入 LostRecovery
记录 Trace
反馈当前状态
```

### 3.3 Validator

三层校验：

```text
Schema 校验：字段类型、必填、枚举值
语义校验：引用完整性、路径可达、孤儿检测
DryRun：完整播放模拟
```

### 3.4 Risk Engine

```text
L0 只读/浏览
L1 低风险可撤回
L2 影响业务记录/客户结果
L3 高风险不可逆、法律或资金相关
L2/L3 必须确认，L3 必须留痕
```

### 3.5 Trace Engine

```text
记录：用户输入、意图匹配、旅程选择、门禁通过、风险确认、恢复路径、完成结果
绑定：旅程包版本、场景哈希
不可篡改：关键 Trace 绑定 Evidence
```

### 3.6 AI Layer

三个角色：

```text
辅助编排：专家口述/演示 → AI 生成旅程草稿 → 专家校正 → 发布
受控匹配：用户输入 → AI 匹配已发布旅程包 → 数字候选（不自由生成）
卡点分析：Trace 数据 → AI 分析卡点 → 优化建议 → 回流编排端
```

关键约束：

```text
AI 只能引用已审核发布的旅程包内容
不编造业务规则
不跳过风险确认门禁
不确定时给数字候选让用户选
```

### 3.7 Industry Adapter

行业适配配置包结构：

```text
术语映射表      OCGS 术语 → 行业语言
扩展字段        行业特有数据模型
旅程模板库      5-10 个高频业务模板
风险规则        行业默认风险策略
演示数据        脱敏售前素材
销售话术        行业特定价值表达
```

---

## 4. 产品清单

### 产品 1：深导·编排 DeepGuide Studio

```text
定位：给专家、管理员、流程负责人使用的旅程包制作工具
用户：业务专家 / 流程负责人 / 培训负责人 / 合规负责人

核心能力：
  宝物定义器
  AI 主持式门禁倒推（必须从 Output 倒推，不从入口顺推）
  场域/门禁/图卡编辑器
  风险策略编辑器
  LostRecovery 编辑器
  意图触发语编辑器
  测试中心（红绿灯机制）
  审核发布中心（草稿 → 自检 → 专家审核 → 合规审核 → 发布）

图卡视觉规则：
  粉红实线  当前主焦点
  粉红虚线  候选目标
  浅蓝      场域
  浅绿      成功状态
  浅黄      风险区
  灰色      弱化背景

数字候选规则：
  所有前台选择项必须使用 1-9 阿拉伯数字编号
  用户可语音说数字选择
```

### 产品 2：深导·陪跑 DeepGuide Coach

```text
定位：给一线员工、新人、小白使用的业务陪跑工具
用户：窗口人员 / 客服 / 柜员 / 新员工 / 临时工

核心能力：
  语音/文字输入
  意图识别 → 旅程匹配 → 数字候选
  图卡播放（看图操作）
  迷路恢复 LostRecovery
  风险确认（L2/L3 不可自动跳过）
  完成验证 + Trace 留痕
  呼叫专家

核心原则：
  不是自由聊天机器人
  优先使用已审核发布的旅程包
  所有候选数字化
  高风险必须确认
  关键执行留痕

主流程：
  UserInput → IntentResolve → TreasureCandidate → JourneySelect
  → GuideCardPlay → RiskConfirm / LostRecovery
  → OutputVerify → TraceComplete
```

### 产品 3：深导·展示 DeepGuide Showcase

```text
定位：可视化展示任意能力旅程
用户：任何人

核心能力：
  读取 scenario.json / BusinessJourneyPackage
  播放旅程步骤
  解释每一步为什么发生
  展示 Gate / Evidence / Treasure
  切换角色视角

来源：原 深演·旅图 DeepJourney
关系：展示端是编排端和陪跑端的可视化窗口
用途：售前演示、培训展示、治理效果可视化
```

### 产品 4：深导·教学 DeepGuide Teach

```text
定位：OCGS 交互式教学工具
用户：管理者 / 工程师 / 研究者 / 潜在用户

核心能力：
  5 章教学场景：
    1. 能力裸奔     理解"能≠序"
    2. 目的绑定     理解 Ability 为什么要绑定 Purpose
    3. 合当约束     理解 Purpose≠Due
    4. 高风险行为   理解 L3 需要确认/承责/证据/封存
    5. 完整链路     看懂 Ability→Purpose→Due→Evidence→Seal
  固定教学场景，低配置自由度
  强解释、强对比

来源：原 深演·明理 DeepExplorer
关系：教学端使用与展示端相同的播放引擎，只是内容为内置教学场景
用途：让新人看懂 OCGS，降低认知门槛
```

### 产品 5：深导·深用 DeepGuide for Software

```text
定位：软件使用与客户成功方向
用户：软件用户 / SaaS 客户成功团队 / 软件厂商

一句话：让客户不会用系统时，按图卡完成真实任务

场景：
  首次配置
  数据导入
  权限设置
  报表生成
  审批流创建
  复杂后台操作

商业化优先级：第一优先
原因：最接近善用、可先服务自己软件、不需要重行业销售、易做 Demo
```

### 产品 6：深导·深客 DeepGuide for Service

```text
定位：企业客服方向
用户：客服中心新人 / 在线客服 / 电话客服

一句话：把金牌客服的判断路径变成新人可执行旅程

场景：
  售后问题分类
  退款退货判断
  物流异常处理
  客户投诉安抚
  工单升级
  高风险客户话术

商业化优先级：第二优先
原因：新人培训痛点强、分支话术易结构化、专家能力复制价值明显
```

### 产品 7：善用

```text
定位：深导的轻量入口 / 个人版
用户：个人 / 小团队 / 软件厂商

一句话：个人与软件厂商版图卡说明书

与深导的关系：
  善用是用户接触"图卡引导"的第一站
  用户升级后进入深导·深用
  善用的图卡数据可导入深导·编排
  深导·陪跑不能直接执行的复杂操作 → 可调起善用

商业化：免费或低价，作为深导的获客漏斗
```

### 产品 8：深导·测试 DeepGuide Test

```text
定位：UI 行为 Mock 测试工具
用户：开发者 / 测试人员

核心能力：
  UI 行为 Mock 测试
  配置端 + 测试端
  共享数据库
  AI 阅读开发文档和代码生成测试配置
  红绿灯机制
  跨软件 Bug 记录库
  测试经验沉淀

适用：VCL / FMX / Windows 桌面程序 / DeepGuide 各端 / 其他 OCGS 应用

来源：原 深测 DeepUITest
```

### 产品 9：深导·Delphi DeepGuide for Delphi

```text
定位：Delphi 项目的能力治理与窗体减肥
用户：Delphi 开发者

核心能力：
  ActionGrid — 轻量动作治理结构
  OCGS Runtime 的 Delphi 实现
  窗体能力治理（从事件肥胖到 OCGS-d Tier 2）
  符合性测试（Conformance Test）

解决：
  窗体膨胀 / TAction 混乱 / 功能入口写死
  路由无法热更新 / AI 生成代码难治理

来源：原 OCGS-Delphi + ActionGrid
关系：深导底座在 Delphi 工程领域的垂直实现
```

---

## 5. 行业配置包

行业配置包不是独立产品，是底座之上的配置层。新增行业 = 新增配置包。

### 5.1 配置包标准结构

每个行业配置包包含：

```text
术语映射表        OCGS 术语 → 行业语言
扩展字段          行业特有数据模型
旅程模板库        5-10 个高频业务模板
风险规则          行业默认风险策略
演示数据          脱敏售前素材
销售话术          行业特定价值表达
```

### 5.2 行业矩阵

| 行业 | 修饰名 | 中文 | 落地梯队 | 模式 |
|------|--------|------|----------|------|
| 软件使用 | for Software | 深用 | 第一梯队 | 自研直营 |
| 企业客服 | for Service | 深客 | 第一梯队 | 自研直营 |
| 人力资源 | for HR | 深人 | 第二梯队 | ISV 合作 |
| 制造质检 | for Quality | 深检 | 第二梯队 | ISV 合作 |
| 门店零售 | for Store | 深店 | 第二梯队 | ISV 合作 |
| 税务服务 | for Tax | 深税 | 第三梯队 | 渠道/集成商 |
| 政务窗口 | for Government | 深政 | 第三梯队 | 渠道/集成商 |
| 银行柜面 | for Banking | 深银 | 第三梯队 | 渠道/集成商 |
| 保险服务 | for Insurance | 深保 | 第三梯队 | 渠道/集成商 |
| 医疗导诊 | for Healthcare | 深医 | 第三梯队 | 渠道/集成商 |
| 教育教务 | for Education | 深教 | 第三梯队 | 渠道/集成商 |
| 园区物业 | for Park | 深园 | 第三梯队 | 渠道/集成商 |
| 法务合规 | for Compliance | 深法 | 第三梯队 | 渠道/集成商 |

### 5.3 落地梯队说明

```text
第一梯队（自研直营）：
  深导团队直接研发、销售、实施
  原因：场景通用、销售门槛低、可先用自己软件做样板

第二梯队（ISV 合作）：
  合作伙伴提供行业内容，深导提供平台
  原因：行业知识需要合作方，但销售周期可控

第三梯队（渠道/集成商）：
  系统集成商负责落地，深导提供平台和培训
  原因：销售门槛高、合规要求强、需要行业资质
```

---

## 6. 商业化策略

### 6.1 三档定价

```text
轻量版：
  包含：展示端 + 教学端 + 基础编排 + 善用
  定价：免费起步（3 个旅程包）+ 订阅解锁
  目标：获客 + 口碑 + 验证产品价值

标准版：
  包含：四端齐全 + 1 个行业适配包
  定价：按坐席数订阅，或按年许可
  目标：验证"专家能力复制"的商业闭环

企业版：
  包含：四端 + 多行业适配 + 私有部署 + 定制实施
  定价：项目制（实施费 + 年费）
  目标：建立行业样板案例
```

### 6.2 商业化节奏

```text
第一阶段（0-6月）：轻量版验证
  先用自己的软件做样板（善用 → 深用）
  积累真实旅程包
  验证"专家讲一遍 → AI 生成草稿 → 校正发布"的闭环

第二阶段（6-18月）：标准版拓展
  深客（客服）作为第一个外部行业
  积累 3-5 个客户案例
  打磨行业适配配置包

第三阶段（18月+）：企业版突破
  选一个重行业做深度样板
  建立行业合作伙伴渠道
  不自己扛所有行业，赋能行业 ISV
```

### 6.3 市场定位

```text
一句话：企业专家能力的数字化复制平台

不是什么：
  不是知识库 — 不存答案，带用户拿到结果
  不是培训系统 — 不事先学，现场陪跑
  不是 RPA — 不替人操作，指导人操作
  不是聊天机器人 — 受控旅程，不自由对话
  不是数字采纳平台 — 不只系统引导，还有业务判断和话术

是什么：
  把专家的判断、操作、话术、异常处理经验
  封装成可播放、可恢复、可确认、可留痕的旅程包
  让新人按专家路径执行
```

---

## 7. 不纳入深导体系的产品

以下产品可以使用 OCGS 思想，但属于独立产品线：

```text
深启 DeepLaunch
  定位：Windows 遥控器
  与深导关系：可调起深导陪跑端，但不属于深导体系

ShineOps
  定位：灯塔内容运营系统
  与深导关系：可为深导生产传播内容，但不属于深导体系
```

---

## 8. 与前版文档的映射

| 前版文件 | 前版概念 | 本版映射 |
|----------|----------|----------|
| OCGS.071 | B 类：深导企业专家能力化产品线 | 整合为本文件全部产品 |
| OCGS.071 | B 类：DeepGuide Studio | 产品 1：深导·编排 |
| OCGS.071 | B 类：DeepGuide Coach | 产品 2：深导·陪跑 |
| OCGS.071 | B 类：DeepSketch / 深图 | 编排端内的图卡/线框模块 |
| OCGS.071 | C 类：OCGS 工具支撑线 | 产品 8：深导·测试 + 底座 Validator |
| OCGS.071 | D 类：相邻产品线 | 不纳入，独立产品线 |
| OCGS.073 | 深演·明理 DeepExplorer | 产品 4：深导·教学 |
| OCGS.073 | 深演·旅图 DeepJourney | 产品 3：深导·展示 |
| OCGS.074 | 行业分版 | 行业配置包（降级为配置层） |
| OCGS.075 | DeepJourney 企业版 | 本文件重新定义 |
| OCGS.077 | BusinessJourneyPackage Schema | 底座 Journey Schema |
| OCGS.079 | DeepJourney Studio PRD | 产品 1 PRD 参考 |
| OCGS.081 | DeepJourney Coach PRD | 产品 2 PRD 参考 |
| OCGS.083 | MVP 实施路线 | 本文件 6.2 商业化节奏参考 |

---

## 9. 统一命名规范

```text
品牌名：    深导 DeepGuide
产品命名：  DeepGuide + [功能名]
行业命名：  DeepGuide for + [行业名]
中文简称：  深导·XX

正式名称对照：
  DeepGuide Studio           深导·编排
  DeepGuide Coach            深导·陪跑
  DeepGuide Showcase         深导·展示
  DeepGuide Teach            深导·教学
  DeepGuide for Software     深导·深用
  DeepGuide for Service      深导·深客
  DeepGuide Test             深导·测试
  DeepGuide for Delphi       深导·Delphi
  善用                       保留原名

不再对外使用的名称：
  DeepJourney    内部可保留为历史代号
  DeepExplorer   内部可保留为历史代号
  深演·明理      已并入深导·教学
  深演·旅图      已并入深导·展示
  深测           已改为深导·测试
  OCGS-se        对外改为深导·工程治理（本文件未单独列产品，作为 Delphi 同类方向保留）
```

---

## 10. 一句话总结

> 深导 DeepGuide 是以 OCGS 为方法底座的企业专家能力复制平台。一个底座，九个产品，十一个行业配置包。底座提供统一的旅程数据模型、路由引擎、风险引擎、留痕引擎和 AI 能力；产品覆盖编排、陪跑、展示、教学、行业垂直、测试和工程治理；善用作为轻量入口为深导获客；深启和 ShineOps 作为独立产品线不纳入深导体系。
