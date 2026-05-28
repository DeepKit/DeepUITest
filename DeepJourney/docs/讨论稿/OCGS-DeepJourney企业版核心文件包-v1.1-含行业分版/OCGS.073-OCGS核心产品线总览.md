# OCGS.073-OCGS核心产品线总览

> 文档性质：产品线总览  
> 核心主题：以 OCGS 为核心的产品矩阵  
> 状态：v0.1 草案  
> 重要边界：本组文件不讨论原 Launch / DeepLaunch，也不讨论 Shine / ShineOps。

---

## 0. 本文目的

本文用于统一“以 OCGS 为核心”的产品线口径。这里讨论的不是启动器、不是内容运营系统，而是围绕 OCGS 的能力治理、专家能力封装、业务旅程、企业前台陪跑、软件工程治理和测试治理形成的产品群。

本组文件重点补齐：

```text
OCGS.075-DeepJourney企业版产品定位.md
OCGS.077-DeepJourney标准业务旅程包Schema.md
OCGS.079-DeepJourney-Studio编排中心PRD.md
OCGS.081-DeepJourney-Coach前台助手PRD.md
OCGS.083-DeepJourney企业级MVP实施路线.md
```

---

## 1. OCGS 核心思想

OCGS 可以理解为：

> **Ordered Capability Governance System：能力有序治理系统。**

它不只是软件架构，也是一套能力治理方法。它回答：

```text
1. 用户最终要拿到什么宝物 / Output？
2. 宝物之前的最后一道门是什么？
3. 用户处在哪个场域？
4. 进入下一步需要哪些门禁条件？
5. 出错、迷路、不确定时如何恢复？
6. 哪些动作能自动做，哪些必须指导做？
7. 哪些风险需要确认、留痕、回滚？
8. 能力如何测试、封版、迭代？
```

OCGS 的核心对象包括：

```text
Output / 宝物
Field / 场域
AccessGate / 门禁
GateCondition / 进入条件
RouteRule / 路由规则
Feedback / 反馈
LostRecovery / 迷路恢复
RiskPolicy / 风险策略
Trace / 留痕
HumanDecisionLog / 人类决策记录
```

---

## 2. OCGS 核心产品线

### 2.1 OCGS 方法论与运行时内核

定位：所有能力治理产品的底座。

内容包括：宝物倒推、AI 主持式门禁采访、Gate / Field / Route / Output 元模型、风险分级、测试与封版规则、Trace 与 Evidence 留痕规则。

### 2.2 OCGS-se：软件工程能力治理线

定位：面向一般软件工程的 OCGS 实施方法。

适用对象：Web、桌面、后台、企业内部系统、AI 辅助生成软件、多端业务系统。

解决问题：功能入口混乱、权限与流程写死、UI 与业务能力强耦合、AI 生成代码缺少治理、业务流程无门禁反馈闭环。

### 2.3 OCGS-Delphi：Delphi 项目能力治理线

定位：面向 Delphi 项目的能力治理与窗体减肥方案。

注意：OCGS-Delphi 不只服务老项目，也服务所有 Delphi 项目。

解决问题：窗体膨胀、按钮/菜单/Action/Event 堆积、功能入口写死、TAction 与业务能力绑定不清、老项目难测试难扩展、AI 生成 Delphi 代码缺少治理。

### 2.4 DeepJourney 企业版：企业专家能力化产品线

定位：把企业专家经验封装成可播放、可执行、可恢复、可留痕的业务旅程包。

一句话：

> **让新人、小白、一线员工，在复杂业务现场也能像专家一样办事、接待客户、少犯错。**

核心对象：

```text
BusinessJourneyPackage / 标准业务旅程包
DeepJourney Studio / 编排中心
DeepJourney Coach / 前台助手
```

### 2.5 DeepUITest / 深测：UI 行为 Mock 测试线

定位：对基于 OCGS 的桌面程序和业务旅程进行行为测试。

作用：测试旅程包是否能走通、图卡与真实界面是否匹配、按钮菜单表单状态变化是否正确、迷路恢复是否可用、红绿灯质量是否通过。

---

## 3. 不属于本组文件的产品线

### 3.1 DeepLaunch / 深启

DeepLaunch 当前定位是 Windows 遥控器，负责单键遥控、F2 语音/文字遥控、Windows 应用/文件/文件夹/工作流启动、习惯链路学习。它是另一个产品线，本组文件暂不讨论。

### 3.2 ShineOps

ShineOps 当前定位是灯塔内容运营系统，负责内容采集、分析、生成、发布、多账号和任务管理。它也是另一个产品线，本组文件暂不讨论。

---

## 4. OCGS 核心产品线关系图

```text
OCGS 方法论 / 内核
  ├─ OCGS-se：通用软件工程治理
  ├─ OCGS-Delphi：Delphi 项目能力治理
  ├─ DeepJourney 企业版：企业专家能力旅程化
  │    ├─ BusinessJourneyPackage Schema
  │    ├─ DeepJourney Studio 编排中心
  │    └─ DeepJourney Coach 前台助手
  └─ DeepUITest：UI 行为与旅程测试
```

---

## 5. 一句话总结

> 本组 OCGS 核心产品线的中心，不是 DeepLaunch，也不是 ShineOps，而是以 OCGS 为底座，把专家能力、业务流程、风险门禁、图卡指导、问答恢复、执行留痕组织成企业可用的 DeepJourney 业务旅程系统。


---

## 7. 行业分版修正

DeepJourney 不应只作为一个泛泛的企业版产品名对外销售。

正确关系是：

```text
DeepJourney Platform = 母平台 / 技术底座
行业分版 = 对外产品名
```

行业分版包括：

```text
深用 / DeepUse：软件厂商 / 软件使用旅程系统
深客 / DeepService：客服业务旅程系统
深政 / DeepGov：政务窗口业务旅程系统
深税 / DeepTax：税务业务旅程系统
深银 / DeepBank：银行柜面业务旅程系统
深医 / DeepMed：医疗导诊 / 医保业务旅程系统
深人 / DeepHR：人事行政业务旅程系统
深检 / DeepQuality：制造质检 / 巡检旅程系统
```

因此，本组 OCGS 核心产品线应从：

```text
DeepJourney 企业版
```

进一步细化为：

```text
DeepJourney Platform
  ├─ 深用 DeepUse
  ├─ 深客 DeepService
  ├─ 深政 DeepGov
  ├─ 深税 DeepTax
  ├─ 深银 DeepBank
  ├─ 深医 DeepMed
  ├─ 深人 DeepHR
  └─ 深检 DeepQuality
```

详见：

```text
OCGS.074-DeepJourney行业分版与产品命名矩阵.md
```
