# 深导 DeepGuide 产品矩阵

> 整理日期：2026-05-13
> 当前状态：开发文档收敛版
> 统一品牌：深导 DeepGuide
> 架构原则：一个协议底座，多个产品端，行业通过配置扩展

---

## 一句话定位

深导 DeepGuide 的愿景，是让新员工也能象专家一样完成工作。

它不是知识库、培训系统、聊天机器人或 RPA。它的核心对象是 `Journey Package`，核心闭环是：专家编排、协议校验、一线执行、旅程记录反馈、版本迭代。

---

## 开发真源顺序

当文档之间出现冲突时，按以下顺序判定：

1. `platform/06.DeepGuide-Journey-Protocol-v1.0.md`：协议真源，定义对象、状态机、MUST/SHOULD/MAY 规则。
2. `platform/07.journey-package.schema.json`：机器校验真源，负责 JSON 结构、类型、枚举、必填字段。
3. `platform/08.Validator规则清单.md`：语义校验真源，负责引用完整性、路径可达、风险治理、发布门槛。
4. Studio / Coach / Showcase 实现规范：解释各产品端如何消费协议。
5. 愿景、行业、市场、命名文档：非规范性说明，用于定位和讨论。

`platform/02.Journey-Schema统一数据模型.md` 和 `platform/05.协议补齐-DueSet完整覆盖.md` 已降级为协议说明与设计沿革，不再单独作为实现真源。

---

## 三层架构

```text
L1 通用底座 DeepGuide Platform
   Protocol / Schema / Validator / Runtime / Risk / Trace / AI / Industry Adapter
   -> 所有产品共享，不直接面向终端用户销售

L2 二级底座（行业交互模式）
   深财税 / 深用 / 深客 / 深政 / 深税 / 深银 ...
   -> 每个行业有自己的术语、扩展字段、默认风险规则和交互范式

L3 客户适配软件
   某企业的发票报销材料检查旅程包
   某银行的开户审核旅程包
   -> 旅程包 + 术语映射 + 风险规则 + 演示数据 + 审核链
```

---

## 产品清单

```text
深导 DeepGuide
│
├─ L1 通用底座
│   └─ DeepGuide Platform
│
├─ 通用产品端
│   ├─ DeepGuide Studio    深导·编排：写包、校验、审核、发布
│   ├─ DeepGuide Coach     深导·陪跑：播放已发布旅程包并记录旅程状态
│   └─ DeepGuide Showcase  深导·展示：只读解释、售前演示、教学
│
├─ L2 行业模式
│   ├─ DeepGuide for Finance & Tax  深财税（首个样板）
│   ├─ DeepGuide for Software  深用
│   ├─ DeepGuide for Service   深客
│   └─ 其他行业按配置包扩展
│
├─ 独立工具
│   ├─ DeepGuide Test          深导测试（独立产品，当前文档只保留接口预期）
│   └─ DeepGuide for Delphi    深导 Delphi
│
├─ 高级助理层
│   └─ DeepAssist 深助（红绿灯协议下的受控操作助理）
│
├─ 双悬浮面板（A 意图澄清对话框 / B 图卡展示区）
│   └─ 善用
│
└─ 支撑方法论
    ├─ OCGS Core
    ├─ OCGS-se
    └─ OCGS-d AI 主持式倒推流程
```

---

## MVP 开发优先级

本目录当前优先服务“旅程包闭环”开发，不把所有产品一次做完。

```text
P0：Protocol + JSON Schema + Validator + 财税/会计实操示例旅程包
P1：Studio 最小写包端（Output/Gate/Card/Route/Risk/LostRecovery）
P2：Coach 最小播放端（双悬浮面板/多轮意图澄清/意图候选/数字选择/状态机/Trace）
P3：反馈回流与版本治理
P4：Showcase、行业插件、深导测试集成
```

若 DeepGuide Test 独立推进，应另建文档目录，不阻塞上述 P0-P3。

---

## 目录索引

| 路径 | 内容 | 权威性 |
|---|---|---|
| `00-开发落地总纲.md` | 开发落地原则、MVP 切线、冲突处理 | 高 |
| `platform/06.DeepGuide-Journey-Protocol-v1.0.md` | 协议真源 | 最高 |
| `platform/07.journey-package.schema.json` | JSON Schema | 最高 |
| `platform/08.Validator规则清单.md` | 发布前语义校验规则 | 高 |
| `platform/09.示例旅程包计划.md` | 样例包与反例包计划 | 高 |
| `platform/10.财税发票报销材料检查旅程规格.md` | 首个财税样板旅程规格 | 高 |
| `studio/` | Studio 愿景、PRD、实现规范 | 中 |
| `coach/` | Coach 愿景与实现规范 | 中 |
| `showcase/` | Showcase 愿景与实现规范 | 中 |
| `for-service/` | 深客行业交互范式 | 中 |
| `行业配置包/` | 行业适配体系和行业矩阵 | 中 |
| `../DeepAssist/docs/` | 深助高级助理层与红绿灯协议（独立产品目录） | 中 |
| `支撑/` | OCGS 方法论、命名规范 | 中 |

---

## 当前开发判断

最先要交付的不是完整产品，而是一个能跑通的协议样板：

首个样板包：财税/会计实操中的“发票报销材料检查”，面向新入职财务助理 / 报销初审员。

1. 一个合法旅程包能通过 Schema 和 Validator。
2. Studio 能创建并发布这个包。
3. Coach 只能播放 `published` 包，执行过程产生 Trace。
4. L2/L3 风险步骤不能自动跳过。
5. 出错、迷路、召回和反馈都有明确路径。

这五点成立后，再讨论愿景扩展才有工程锚点。