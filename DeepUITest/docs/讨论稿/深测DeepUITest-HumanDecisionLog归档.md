# 深测 DeepUITest：HumanDecisionLog 专项归档

> 用途：快速查看本轮 DeepUITest 讨论中已经由用户确认或推进的关键决策。  
> 范围：从“UI 行为 Mock 测试”新话题开始，到“避免拖慢 DeepLaunch 和善用”的战略讨论为止。

---

## HumanDecisionLog-005

```text
状态：暂停「善用 × DeepLaunch 图卡演示案例」
新话题：多个桌面程序的 UI 行为 Mock 测试
核心问题：是否可以用 OCGS 软件支撑，还是应设计一个新软件
```

---

## HumanDecisionLog-006

```text
主题：UI 行为 Mock / 回归测试新产品命名与边界

产品名：
深测 DeepUITest

定位：
暂时只管 Windows 桌面程序的 UI 行为 Mock 测试 / 回归测试。

系统形态：
1. 配置端
2. 测试端
3. 两端共享数据库

重要边界：
暂不管 Web、移动端、接口测试、性能测试；
第一阶段只聚焦 Windows 桌面程序的行为链测试。
```

---

## HumanDecisionLog-007

```text
主题：DeepUITest 是否支持 AI 读取开发文档和代码生成测试配置
决定：支持
定位：作为 DeepUITest 的 AI 配置生成器模块
原则：AI 生成的是“候选测试配置”，不是直接可信的最终配置；必须经过人工审核和 Runner 回放验证。
```

---

## HumanDecisionLog-008

```text
主题：DeepUITest 支持范围与审核机制修正

新增支持：
1. Delphi VCL 桌面程序
2. Delphi FMX 桌面程序，暂时只管 Windows 下运行的 FMX 程序

新增机制：
红绿灯机制

目标：
AI 读取开发文档、代码、窗体结构、录制轨迹后，自动生成测试配置草稿；
系统用红绿灯标记可信度，减少人类逐条审核负担。

原则：
不是所有 AI 生成配置都让人从头审；
而是让人重点审黄色和红色项。
```

---

## HumanDecisionLog-009

```text
用户输入：继续
默认承接：继续细化 DeepUITest 红绿灯机制
目标：减少 AI 生成测试配置后的人工审核负担
```

---

## HumanDecisionLog-010

```text
用户要求：由我作为主持人，组织 5 个专家继续讨论
本轮议题：深测 DeepUITest 如何读取 VCL / FMX 开发文档与代码，生成测试配置，并接入红绿灯机制
```

---

## HumanDecisionLog-011

```text
主题：DeepUITest 增加跨软件 Bug 记录库

新增模块：
BugRecordLibrary / 跨软件 Bug 记录库

目标：
把多个桌面程序中出现过的 Bug、失败路径、控件识别问题、断言失败、配置错误、历史修复方案沉淀下来，
让 AI 在后续生成测试配置、判断红绿灯、解释失败原因、推荐修复方案时变得更聪明。

原则：
Bug 记录库不是单个软件的缺陷表，
而是跨软件、跨版本、跨技术栈的经验库。
```

---

## HumanDecisionLog-012

```text
选择：1
含义：继续讨论「DeepUITest 第一版 MVP 应该具体做哪些模块」
当前前提：
深测 DeepUITest = Windows 桌面程序 UI 行为 Mock / 回归测试系统
第一阶段支持 VCL / FMX
分为配置端 Designer、测试端 Runner、共享数据库
包含 AI 生成配置、红绿灯机制、跨软件 Bug 记录库
```

---

## HumanDecisionLog-013

```text
选择：5

战略定位：
深测 DeepUITest 第一阶段采用混合定位：

第一阶段：
自用基础设施 + OCGS 样板工程。

第二阶段：
再包装为 Delphi / VCL / FMX 开发者工具。

战略含义：
短期不急于商业化，不做大而全测试平台；
先服务自己的 DeepLaunch、善用、UniBase / DeepBase 等桌面软件矩阵；
同时用它证明 OCGS 的“宝物-门禁-行为链-断言-红绿灯-Bug库-封版”方法论价值。
```

---

## HumanDecisionLog-014

```text
用户输入：继续
承接上一轮建议：
讨论“深测 DeepUITest 第一阶段应该优先守住哪个软件？”

候选对象：
1. 深启 DeepLaunch
2. 善用
3. UniBase / DeepBase
4. OCGS-d
5. 多软件同时少量覆盖

结论倾向：
第一阶段优先守住 DeepLaunch。
```

---

## HumanDecisionLog-015

```text
用户输入：继续
承接上一轮建议：
讨论 DeepLaunch 三条命脉链中，哪一条应作为深测 DeepUITest 的第一样板。

结论：
第一样板应选择“已配置启动链”：
F1 → X → 指定程序启动。
```

---

## HumanDecisionLog-016

```text
用户输入：继续
承接上一轮建议：
讨论“深测 DeepUITest 与 OCGS 的关系怎么对外表达？”

当前前提：
深测第一阶段定位为：
自用基础设施 + OCGS 样板工程。

第一样板：
DeepLaunch 已配置启动链：
F1 → X → 指定程序启动。

结论：
内部定义：OCGS 能力质量治理系统。
对外表达：AI 辅助 Windows 桌面软件行为回归测试系统。
```

---

## HumanDecisionLog-017

```text
用户输入：继续
承接上一轮建议：
讨论第二样板“配置生效链”的战略价值。

当前顺序：
第一样板：已配置启动链
F1 → X → 指定程序启动

第二样板：配置生效链
绑定程序 → 保存 → F1 + X → 指定程序启动

第三样板：F2 候选执行链
F2 → 输入 / 转录 → 1-9 候选 → 执行 → 0 返回 / 取消

结论：
第二样板最能体现 DeepUITest 与普通 UI 测试的差异：
它验证配置是否真正转化成用户可调用能力。
```

---

## HumanDecisionLog-018

```text
用户输入：继续
承接上一轮建议：
讨论“深测 DeepUITest 未来对外时，目标客户是谁？”

候选客户：
1. Delphi / VCL / FMX 老项目开发者
2. 小团队桌面软件开发者
3. 企业测试部门
4. AI 辅助改造旧系统的人
5. OCGS 体系内用户 / 开发者

结论：
第一阶段自用；
第二阶段面向 Delphi / VCL / FMX 老项目开发者和桌面软件小团队；
第三阶段再考虑企业测试部门。
```

---

## HumanDecisionLog-019

```text
用户输入：继续
承接上一轮建议：
讨论“深测 DeepUITest 的护城河主轴是什么？”

候选护城河：
1. AI 读取代码 / 文档生成测试配置
2. OCGS 行为链 / 宝物门禁模型
3. 红绿灯可信度机制
4. 跨软件 Bug 经验库
5. VCL / FMX 老项目适配能力

结论：
主护城河不是 AI 读代码，
而是 OCGS 行为链质量治理闭环。
```

---

## HumanDecisionLog-020

```text
用户输入：继续
承接上一轮建议：
讨论“深测 DeepUITest 如何避免拖慢 DeepLaunch 和善用？”

当前战略前提：
深测第一阶段 = 自用基础设施 + OCGS 样板工程
优先守住 DeepLaunch
随后守住善用
但不能让深测变成新的主项目，拖慢 DeepLaunch / 善用本身。

结论：
采用“伴生开发 + 命脉链守护 + 选择性封版”。
主产品开发一条关键能力，深测补一条关键行为链。
每个产品先守三条命脉链。
```
