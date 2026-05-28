# OCGS.071-OCGS理论下产品矩阵终版

> 文档性质：终版产品矩阵  
> 版本：v1.0  
> 核心范围：OCGS 理论下的产品体系、产品线关系、命名边界与优先级  
> 最终命名修正：DeepJourney 对外升级为 **深导 DeepGuide**  
> 重要边界：DeepLaunch / ShineOps 是相邻产品线，不属于“深导企业专家能力化产品线”，但可受 OCGS 方法指导。

---

## 0. 本文目的

本文用于冻结当前 OCGS 理论下的产品矩阵。

此前讨论中出现了多条产品线：

```text
OCGS
OCGS-se
OCGS-Delphi
ActionGrid
DeepJourney
深导 DeepGuide
深图
DeepGuide Studio
DeepGuide Coach
DeepUITest / 深测
DeepLaunch / 深启
ShineOps
善用
```

为了防止混淆，本文统一回答：

```text
1. OCGS 理论下到底有哪些产品线？
2. 哪些是核心产品？
3. 哪些是行业分版？
4. 哪些是工具支撑线？
5. 哪些只是相邻产品线，不应混入本组？
6. DeepJourney、深导、深图、Coach、Studio 的关系是什么？
7. 后续文件应按什么产品矩阵继续写？
```

---

## 1. 总体判断

OCGS 不是单个软件，而是一套“能力有序治理”的理论底座。

它可以派生出三类产品：

```text
第一类：方法论 / 框架 / 运行时产品
  解决“能力如何被治理”的问题。

第二类：企业专家能力化产品
  解决“专家能力如何转成一线可执行旅程”的问题。

第三类：工具支撑产品
  解决“如何开发、测试、维护、交付这些能力治理系统”的问题。
```

此外，还有两条相邻产品线：

```text
DeepLaunch / 深启：
  Windows 遥控器产品线。

ShineOps：
  灯塔内容运营系统产品线。
```

它们可以使用 OCGS 思想，但不属于本文的 OCGS 企业产品矩阵核心。

---

## 2. 最终产品矩阵总览

```text
OCGS 理论体系
│
├─ A. OCGS 核心理论与运行时产品线
│   ├─ OCGS Core
│   ├─ OCGS Runtime
│   ├─ OCGS-d / AI 主持式倒推开发流程
│   ├─ OCGS-se / 通用软件工程能力治理
│   ├─ OCGS-Delphi / Delphi 能力治理
│   └─ ActionGrid / 轻量动作治理结构
│
├─ B. 深导 DeepGuide 企业专家能力化产品线
│   ├─ DeepGuide Platform / 深导平台
│   ├─ DeepGuide Studio / 深导编排中心
│   ├─ DeepGuide Coach / 深导前台助手
│   ├─ DeepGuide Runtime / 深导旅程运行时
│   ├─ DeepGuide Package / 标准业务旅程包
│   ├─ DeepSketch / 深图引擎
│   └─ 行业分版
│       ├─ 深用 DeepUse
│       ├─ 深客 DeepService
│       ├─ 深政 DeepGov
│       ├─ 深税 DeepTax
│       ├─ 深银 DeepBank
│       ├─ 深保 DeepInsurance
│       ├─ 深医 DeepMed
│       ├─ 深人 DeepHR
│       ├─ 深教 DeepEdu
│       ├─ 深检 DeepQuality
│       ├─ 深店 DeepStore
│       ├─ 深园 DeepPark
│       └─ 深法 DeepCompliance
│
├─ C. OCGS 工具支撑产品线
│   ├─ 深测 DeepUITest
│   ├─ OCGS Inspector
│   ├─ OCGS Route Tester
│   ├─ OCGS Package Validator
│   ├─ OCGS Trace Center
│   └─ OCGS Template Library
│
└─ D. 相邻产品线 / 不混入深导企业线
    ├─ 深启 DeepLaunch / Windows 遥控器
    ├─ 善用 / 个人与软件厂商版图卡说明书
    └─ ShineOps / 灯塔内容运营系统
```

---

## 3. A 类：OCGS 核心理论与运行时产品线

这一类是所有后续产品的底层方法和技术底座。

---

### 3.1 OCGS Core

#### 定位

> **能力有序治理系统的核心理论。**

OCGS 解决的问题不是“怎么写一个功能”，而是：

```text
1. 能力什么时候出现？
2. 谁可以用？
3. 从哪个场域进入？
4. 要拿到什么宝物？
5. 要经过哪些门禁？
6. 条件不满足怎么办？
7. 迷路了怎么恢复？
8. 风险点怎么确认？
9. 执行过程怎么留痕？
10. 如何测试和封版？
```

#### 核心对象

```text
Output / 宝物
Field / 场域
AccessGate / 门禁
GateCondition / 门禁条件
RouteRule / 路由规则
GuideCard / 引导卡
RiskPolicy / 风险策略
LostRecovery / 迷路恢复
Trace / 留痕
Evidence / 证据
HumanDecisionLog / 人类决策记录
```

#### 主要用途

```text
1. 指导 DeepGuide 企业产品线；
2. 指导 OCGS-se 软件工程治理；
3. 指导 OCGS-Delphi；
4. 指导 DeepUITest 测试；
5. 指导 AI 主持式产品推导；
6. 指导复杂软件能力组织。
```

---

### 3.2 OCGS Runtime

#### 定位

> **OCGS 概念模型的运行时引擎。**

它负责在真实软件中执行：

```text
1. 加载 Package；
2. 识别当前 Field；
3. 判断 GateCondition；
4. 执行 RouteRule；
5. 显示 GuideCard；
6. 触发 RiskPolicy；
7. 进入 LostRecovery；
8. 记录 Trace；
9. 反馈当前状态。
```

#### 适用范围

```text
DeepGuide Coach
DeepGuide Studio 预览
OCGS-se 软件
OCGS-Delphi 应用
DeepUITest 测试环境
```

---

### 3.3 OCGS-d / AI 主持式倒推开发流程

#### 定位

> **用 AI 主持、人类选择的方式，从宝物倒推出门禁、场域、路由和能力。**

标准流程：

```text
1. 定义宝物 Output
2. 倒推负一号门
3. 继续倒推负二号门、负三号门……
4. 标注 Field / Gate / Condition
5. 生成图卡 / 引导
6. 配置风险和恢复
7. 生成能力
8. 测试门禁路由
9. 人工测试
10. 封版
```

#### 关键原则

```text
讨论时必须倒推；
不要从入口顺推；
AI 给选择题；
人类选择、修正、否定；
记录 HumanDecisionLog。
```

---

### 3.4 OCGS-se

#### 定位

> **面向通用软件工程的能力治理方法。**

它适用于：

```text
Web 系统
桌面系统
后台管理系统
企业内部软件
AI 生成软件
低代码平台
复杂业务系统
```

解决：

```text
1. 功能入口混乱；
2. 权限和流程写死；
3. UI 与业务能力耦合；
4. AI 生成代码缺少治理；
5. 软件越来越胖；
6. 功能多但没有秩序。
```

---

### 3.5 OCGS-Delphi

#### 定位

> **面向 Delphi 项目的能力治理与窗体减肥方案。**

重要修正：

```text
OCGS-Delphi 不只解决老项目；
所有 Delphi 项目都可以用。
```

解决：

```text
Delphi 窗体膨胀
按钮 / 菜单 / TAction / Event 混乱
功能入口写死
路由无法热更新
老项目难维护
AI 生成代码后难治理
```

---

### 3.6 ActionGrid

#### 定位

> **从 Delphi 窗体减肥问题中推导出的轻量动作治理结构。**

它是 OCGS 的早期前身之一，也可以独立作为轻量方案。

作用：

```text
1. 把动作从窗体代码中抽离；
2. 管理动作可见性、可用性、路由；
3. 与原生 TAction 融合；
4. 渐进式接入老项目；
5. 降低窗体肥胖症。
```

---

## 4. B 类：深导 DeepGuide 企业专家能力化产品线

这是 OCGS 最重要的企业应用产品线。

---

## 4.1 命名冻结

### 最终中文名

```text
深导
```

### 最终英文名

```text
DeepGuide
```

### 不采用

```text
DeepDirect
Direct
```

原因：

```text
Direct 更像指挥、命令、控制；
Guide 更像引导、陪着走、带路。
```

### 深图的定位

```text
深图 / DeepSketch
```

不是总产品名，而是深导中的图卡 / 线框 / FocusSketch 模块。

最终分工：

```text
深导 DeepGuide：
  总产品 / 企业专家能力化平台。

深导 Studio：
  编排中心。

深导 Coach：
  前台助手。

深图 DeepSketch：
  图卡、线框、场域示意、视觉引导模块。
```

---

## 4.2 DeepGuide Platform / 深导平台

#### 定位

> **把专家经验变成一线可执行业务旅程的企业平台。**

一句话：

> **深导：把专家经验变成一步步可执行的业务引导。**

完整表达：

> **深导 DeepGuide 是基于 OCGS 的企业专家能力化平台。它把专家经验、业务流程、风险规则、系统操作、标准话术封装成可播放、可恢复、可确认、可留痕的业务旅程包，让新人和一线员工也能像专家一样办事、接待客户、少犯错。**

---

## 4.3 DeepGuide Studio / 深导编排中心

#### 定位

> **给专家、管理员、流程负责人使用的旅程包制作与治理后台。**

主要功能：

```text
1. 新建业务旅程包；
2. 定义宝物 Output；
3. AI 主持式倒推门禁；
4. 编排场域和图卡；
5. 配置数字候选；
6. 配置风险确认；
7. 配置迷路恢复；
8. 配置意图触发语；
9. 测试旅程包；
10. 审核发布；
11. 版本管理。
```

核心用户：

```text
业务专家
流程负责人
培训负责人
合规负责人
系统管理员
```

---

## 4.4 DeepGuide Coach / 深导前台助手

#### 定位

> **给一线员工、新人、小白使用的业务陪跑助手。**

主要功能：

```text
1. 用户语音 / 文字输入；
2. 意图识别；
3. 宝物匹配；
4. 数字候选；
5. 播放图卡；
6. 看图操作；
7. 卡住时 LostRecovery；
8. 风险点确认；
9. 完成验证；
10. 执行留痕。
```

核心原则：

```text
不是自由聊天机器人；
优先使用已审核旅程包；
所有候选数字化；
高风险必须确认；
关键执行留痕。
```

---

## 4.5 DeepGuide Package / 标准业务旅程包

#### 定位

> **深导产品线的核心内容资产。**

一个标准业务旅程包包含：

```text
Package 元信息
Output / 宝物
IntentTrigger / 意图触发
BusinessJourney / 业务旅程
Field / 场域
AccessGate / 门禁
GuideCard / 图卡
RouteRule / 路由
RiskPolicy / 风险策略
LostRecovery / 迷路恢复
TraceSchema / 留痕结构
TestCase / 测试样例
HumanDecisionLog / 决策记录
VersionRecord / 版本记录
```

---

## 4.6 DeepSketch / 深图引擎

#### 定位

> **深导中的图卡、线框、场域示意和视觉引导模块。**

它负责：

```text
1. 生成 FocusSketch；
2. 显示粉红主焦点；
3. 显示粉红虚线候选目标；
4. 显示浅蓝场域框；
5. 显示浅黄风险区；
6. 显示浅绿成功状态；
7. 弱化灰色背景；
8. 支持看图操作；
9. 支持图卡播放。
```

它不是总产品名，只是深导内部能力。

---

## 5. 深导行业分版矩阵

DeepGuide 是母平台名。

不同行业对外应使用行业产品名。

---

## 5.1 行业版总表

| 行业 | 中文产品名 | 英文产品名 | 一句话定位 |
|---|---|---|---|
| 软件使用 / 客户成功 | 深用 | DeepUse Guide | 让客户不会用系统时，按图完成真实任务 |
| 企业客服 | 深客 | DeepService Guide | 把金牌客服路径变成新人可执行旅程 |
| 政务服务 | 深政 | DeepGov Guide | 让窗口新人按专家路径办事，少问人、少投诉 |
| 税务服务 | 深税 | DeepTax Guide | 把税务专家经验变成前台可执行旅程 |
| 银行柜面 | 深银 | DeepBank Guide | 让柜员按合规门禁办理业务 |
| 保险服务 | 深保 | DeepInsurance Guide | 把核保、理赔、客服流程变成标准旅程 |
| 医疗导诊 / 医保 | 深医 | DeepMed Guide | 让导诊、医保、收费流程按图处理 |
| HR / 人事行政 | 深人 | DeepHR Guide | 把入转调离、材料审核变成标准旅程 |
| 教育 / 教务 | 深教 | DeepEdu Guide | 把教务咨询、报名、学籍流程变成旅程 |
| 制造 / 质检 | 深检 | DeepQuality Guide | 把质检、巡检、设备操作标准化 |
| 门店 / 零售 | 深店 | DeepStore Guide | 让门店新人按标准流程接待、售后、盘点 |
| 园区 / 物业 | 深园 | DeepPark Guide | 把物业报修、访客、巡检变成旅程 |
| 法务 / 合规 | 深法 | DeepCompliance Guide | 把合规判断、材料检查、风险确认变成受控旅程 |

---

## 5.2 首选落地顺序

### 第一优先：深用 / DeepUse Guide

原因：

```text
1. 与善用和图卡说明书最接近；
2. 可先服务自己的软件；
3. 不需要重行业合规；
4. 易做 Demo；
5. 可卖给软件厂商 / SaaS 客户成功团队。
```

---

### 第二优先：深客 / DeepService Guide

原因：

```text
1. 客服新人培训痛点强；
2. 分支话术易结构化；
3. 专家能力复制价值明显；
4. 可快速展示效果。
```

---

### 第三优先：深税 / DeepTax 或 深政 / DeepGov

原因：

```text
1. 价值高；
2. 政策变更痛点强；
3. 但销售与合规门槛高；
4. 适合作为中期样板。
```

---

### 第四优先：深检 / DeepQuality

原因：

```text
1. 现场执行场景明显；
2. 与图卡和检查表结合度高；
3. 但需要行业素材。
```

---

## 6. C 类：OCGS 工具支撑产品线

这些产品服务于 OCGS / DeepGuide 的开发、测试、验证和交付。

---

## 6.1 深测 DeepUITest

#### 定位

> **Windows 桌面程序 UI 行为 Mock 测试系统。**

适用：

```text
VCL
FMX
Windows 桌面程序
DeepGuide Coach
DeepLaunch
善用
其它 OCGS 应用
```

核心能力：

```text
1. UI 行为 Mock 测试；
2. 配置端 + 测试端；
3. 共享数据库；
4. AI 阅读开发文档和代码生成测试配置；
5. 红绿灯机制；
6. 跨软件 Bug 记录库；
7. 测试经验沉淀。
```

它是 OCGS 产品线的重要质量保障工具。

---

## 6.2 OCGS Inspector

#### 定位

> **OCGS 运行状态检查器。**

用于查看：

```text
当前 Field；
当前 Gate；
可用 Route；
GateCondition；
RiskPolicy；
Trace；
用户当前位置；
为什么某个能力出现或不出现。
```

---

## 6.3 OCGS Route Tester

#### 定位

> **门禁路由测试器。**

用于测试：

```text
1. 正常路径；
2. 分支路径；
3. 风险路径；
4. LostRecovery；
5. 无效输入；
6. 权限不足；
7. 路由断裂。
```

---

## 6.4 OCGS Package Validator

#### 定位

> **旅程包 / 能力包发布前校验器。**

检查：

```text
1. 是否有 Output；
2. 是否有 CompletionGate；
3. Route 是否断裂；
4. 高风险是否有确认；
5. 数字候选是否合规；
6. LostRecovery 是否缺失；
7. 是否能走到宝物；
8. 版本号是否合法。
```

---

## 6.5 OCGS Trace Center

#### 定位

> **执行留痕与审计中心。**

用于记录：

```text
用户输入
意图匹配
候选选择
门禁通过
风险确认
异常恢复
完成结果
版本信息
责任证据
```

---

## 6.6 OCGS Template Library

#### 定位

> **标准模板库。**

包含：

```text
1. 宝物模板；
2. 门禁模板；
3. 图卡模板；
4. 风险模板；
5. LostRecovery 模板；
6. 行业旅程模板；
7. 测试样例模板。
```

---

## 7. D 类：相邻产品线，不混入深导企业线

这些产品可以使用 OCGS 思想，但不属于本文的 OCGS 企业旅程产品核心。

---

## 7.1 深启 DeepLaunch

#### 定位

> **Windows 遥控器。**

一句话：

> **按一个键，或说一句话，遥控你的 Windows。**

核心能力：

```text
1. 单键遥控；
2. F2 语音 / 文字遥控；
3. 数字候选；
4. 习惯链路学习；
5. 应用 / 文件 / 文件夹 / 工作流启动；
6. 低风险动作执行；
7. 不能直接做的任务调起善用。
```

与 OCGS 关系：

```text
可使用 OCGS 的门禁、风险、路由、Trace 思想；
但它是 Windows 遥控器产品线，不是深导企业版。
```

---

## 7.2 善用

#### 定位

> **个人 / 小团队 / 软件厂商版图卡说明书系统。**

它和深导接近，但战略层级不同。

```text
善用：
  更偏个人用户、小团队、软件上手、图卡说明书。

深导：
  更偏企业专家能力化、行业版、组织交付、审核发布、留痕。
```

善用可作为：

```text
1. 深用 DeepUse 的轻量前身；
2. DeepGuide Coach 的个人版试验田；
3. DeepLaunch 不能直接执行时的图卡说明书。
```

---

## 7.3 ShineOps

#### 定位

> **灯塔内容运营系统。**

负责：

```text
内容采集
内容分析
内容生成
多账号发布
任务管理
灯塔发光
```

它是内容运营产品线，不纳入 DeepGuide 企业旅程产品矩阵。

---

## 8. 产品矩阵关系图

```text
OCGS 理论
│
├─ 核心治理层
│   ├─ OCGS Core
│   ├─ OCGS Runtime
│   ├─ OCGS-d
│   ├─ OCGS-se
│   ├─ OCGS-Delphi
│   └─ ActionGrid
│
├─ 企业专家能力化层
│   └─ 深导 DeepGuide
│       ├─ Studio
│       ├─ Coach
│       ├─ Runtime
│       ├─ Package
│       ├─ 深图 DeepSketch
│       └─ 行业版
│           ├─ 深用
│           ├─ 深客
│           ├─ 深政
│           ├─ 深税
│           ├─ 深银
│           ├─ 深医
│           ├─ 深人
│           └─ 深检
│
├─ 工具支撑层
│   ├─ 深测 DeepUITest
│   ├─ Inspector
│   ├─ Route Tester
│   ├─ Package Validator
│   ├─ Trace Center
│   └─ Template Library
│
└─ 相邻产品线
    ├─ 深启 DeepLaunch
    ├─ 善用
    └─ ShineOps
```

---

## 9. 命名边界表

| 名称 | 是否属于 OCGS 核心矩阵 | 定位 | 备注 |
|---|---|---|---|
| OCGS | 是 | 底层理论 | 总根 |
| OCGS-se | 是 | 通用软件工程治理 | 工程化方向 |
| OCGS-Delphi | 是 | Delphi 能力治理 | Delphi 方向 |
| ActionGrid | 是 | 轻量动作治理 | OCGS 前身/组件 |
| 深导 DeepGuide | 是 | 企业专家能力化平台 | 最终主产品名 |
| DeepJourney | 历史/内部名 | 旧阶段母平台名 | 对外建议改为 DeepGuide |
| 深图 DeepSketch | 是 | 图卡/线框模块 | 不是总产品名 |
| DeepGuide Studio | 是 | 编排中心 | 企业后台 |
| DeepGuide Coach | 是 | 前台助手 | 一线使用 |
| 深用 DeepUse | 是 | 软件使用行业版 | 优先落地 |
| 深客 DeepService | 是 | 客服行业版 | 第二优先 |
| 深税 DeepTax | 是 | 税务行业版 | 中期 |
| 深政 DeepGov | 是 | 政务行业版 | 中期 |
| 深测 DeepUITest | 是 | UI 行为测试 | 工具支撑 |
| 深启 DeepLaunch | 相邻 | Windows 遥控器 | 不混入深导企业线 |
| 善用 | 相邻/轻量版 | 图卡说明书 | 可作为深用试验田 |
| ShineOps | 相邻 | 内容运营系统 | 不属于本组 |

---

## 10. 后续文件编号建议

建议后续 OCGS 产品矩阵文件采用：

```text
OCGS.071-OCGS理论下产品矩阵终版.md
OCGS.073-OCGS核心产品线总览.md
OCGS.074-DeepGuide行业分版与产品命名矩阵.md
OCGS.075-DeepGuide企业版产品定位.md
OCGS.077-DeepGuide标准业务旅程包Schema.md
OCGS.079-DeepGuide-Studio编排中心PRD.md
OCGS.081-DeepGuide-Coach前台助手PRD.md
OCGS.083-DeepGuide企业级MVP实施路线.md
OCGS.085-DeepGuide行业版模板库规划.md
OCGS.087-DeepGuide与OCGS-Runtime关系说明.md
```

说明：

```text
原 DeepJourney 文件可统一重命名为 DeepGuide；
如需保留 DeepJourney，可在文件中注明“DeepJourney 为旧称 / 内部代号”。
```

---

## 11. 当前最优先产品顺序

### 第一优先：深用 DeepUse Guide

原因：

```text
1. 最接近善用；
2. 可用自己的软件做样板；
3. 不需要重行业销售；
4. 适合做图卡旅程演示；
5. 可服务软件厂商客户成功。
```

---

### 第二优先：深导平台 DeepGuide Platform

原因：

```text
1. 需要统一 Studio / Coach / Package；
2. 是行业版的底座；
3. 是 OCGS 企业产品线主干。
```

---

### 第三优先：深客 DeepService Guide

原因：

```text
1. 客服新人痛点明显；
2. 专家经验路径易结构化；
3. 容易展示“新人像专家一样接待客户”。
```

---

### 第四优先：深测 DeepUITest

原因：

```text
1. 可以支撑自身软件质量；
2. 可测试图卡、门禁、UI 行为；
3. 但外部商业化可后置。
```

---

### 第五优先：深税 / 深政

原因：

```text
1. 价值大；
2. 但销售、合规、数据、采购难度高；
3. 适合作为成熟后行业样板。
```

---

## 12. 产品矩阵最终冻结句

> OCGS 理论下的产品矩阵分为四层：  
> **第一层是 OCGS 核心治理层**，包括 OCGS Core、Runtime、OCGS-d、OCGS-se、OCGS-Delphi 和 ActionGrid；  
> **第二层是深导 DeepGuide 企业专家能力化产品线**，包括 Studio、Coach、标准业务旅程包、深图引擎和深用、深客、深政、深税等行业分版；  
> **第三层是 OCGS 工具支撑线**，包括深测 DeepUITest、Inspector、Route Tester、Package Validator、Trace Center 和模板库；  
> **第四层是相邻产品线**，包括深启 DeepLaunch、善用和 ShineOps，它们可以使用 OCGS 思想，但不混入深导企业产品线。  
> 最终主产品名采用“深导 DeepGuide”，DeepJourney 作为旧称或内部代号处理，“深图”仅作为图卡 / 线框 / FocusSketch 模块名。
