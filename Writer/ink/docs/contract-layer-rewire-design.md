# 契约层接线重做设计（根因修复，非补丁）

> 日期：2026-07-15
> 触发：五专家连续评审（AWT-20260715-171440）暴露 P0-1/2/3，深挖到架构根因
> 性质：架构级修复，非局部 bug 补丁。配套 BFX-079（见 bugfix.md）

## 1. 根因（实证，代码自白）

### 1.1 直接证据

**证据 A — `_ensure_scene_and_contract` docstring（cli.py:~1530）**：
> "Dead-line policy skips the dual-blind self_check / independent review;
>  the human actor activation is the seal."

它建的"契约"是空壳：`contract_hash = sha256(brief)`、`source_bundle_hash` 同一
hash，design 3.1 四层 clause（hard_constraints/source_dna/soft_goals/
creative_openings）一个没落，只建一行占位记录让外键跑通。

**证据 B — `brief_builder.py:8`**：
> "死线收口用：不落 chapter contract payload / scene contract 四层 clause"

**证据 C — 契约层工具零生产调用**：
`confirm_and_apply` / `record_contract_review` / `draft_contract` 只挂在
`confirm-contract` / `decision-session` 等 CLI 命令上（需人工手动跑），
produce-chapter 生产链路完全不调。`record_contract_review` 零生产调用方
（死代码）。

**证据 D — git 考古**：
契约层工具（DecisionSession/confirm_and_apply/stale 传播）是早期提交
（1b93f3c5、259145e2）建好；brief_builder 是今天（03bea0fe）新建，直接
裸拼大纲，未接任何契约层。两层不同时间、不同目的建，中间无接线。

### 1.2 根因三层

1. **表面**：7-30 死线压着，为端到端跑通砍契约审查闭环，用人工激活当封条。
2. **机制**：契约层（CLI 旁路工具）与生产层（produce-chapter）是两套独立
   建的工具，从未接线。契约层建好即搁置成死工具，生产层裸奔。
3. **真根因**：没有"契约必须贯穿生产"的硬约束，降级不可逆。第一次降级
   （跳双盲审查）无追责无回补，后续每层（brief 裸拼、context 注入正文）
   在"契约已缺位"错误前提上继续固化。错误前提被固化成架构。

### 1.3 一句话根因

> 设计定义了契约层（五级 Book/Volume/Part/Chapter/Scene + 四层 clause +
> 架构师起草/复审师审查/返工闭环），早期也建了工具，但契约层只挂在需
> 人工手动触发的 CLI 上，从未接线进自动生产链路；为赶死线建生产层时
> 用 docstring 一句"死线策略"把契约审查砍成空壳占位，降级无恢复点、
> 无门拦截、无追责，契约层沦为死工具、生产层裸奔，每层新代码都在
> "契约已缺位"的错误前提上继续固化。根因 = "契约贯穿生产"无硬约束 +
> 降级不可逆。

## 2. 层级落地现状（design §2 五级契约 vs 实现）

| 契约级 | design 定义 | schema 表/列 | 实际有内容 | 注入 brief | 生产调用 |
|---|---|---|---|---|---|
| Book | 有 | book_quality_floor | 仅数值 75 | ❌ | ❌ |
| Volume | 有 | volume_id | **NULL 空** | ❌ | ❌ |
| Part | 有 | part_id | **NULL 空** | ❌ | ❌ |
| Chapter | 3.1 四层 | writing_scene_contracts | **空壳** | ❌ | ❌ |
| Scene | 3.1 四层 | writing_scene_contracts | 空壳占位 | ❌ | ❌ |

stale_propagation.py:19/75/76 自承"无 volume_id/part_id 列，退化为全部章节"。

## 3. P0-1/2/3 在此根下的统一解释

- **P0-1 同构** ← 缺 Chapter 级"结构职责"契约（本章开篇/承接/转折/收束）
- **P0-2 全知** ← 缺 Chapter 级"知情边界"契约（3.1 hard_constraints 本有此字段，未注入）
- **P0-3 无科幻** ← 缺 Volume/Book 级"未来回环分布"契约（哪章嵌哪个锚点）

一个根，三个表现。

## 4. 解决方案（不打补丁，建硬约束）

核心：把"契约贯穿生产"从设计意图变成代码硬约束——生产层不接契约就跑不起来。

### 4.1 接线：produce-chapter 前置契约为硬 gate
- produce-chapter 开头校验：本章是否存在 `confirmed` 状态的 Chapter 级契约
  （含四层 clause payload）。无 → **拒绝产稿，报"请先 confirm 契约"**，不降级。
- 删 `_ensure_scene_and_contract` 的"死线策略跳过双盲审查"降级路径，恢复
  架构师起草→复审师独立审查→过度约束返工闭环为产稿必经步骤。

### 4.2 契约层下沉进生产链路（CLI 旁路 → 流水线环节）
把三步做成 produce-chapter 内部自动子步骤，不再依赖人工手动跑 CLI：
1. `draft_contract`（架构师起草）：小模型从大纲 + 卷级三表生成章级四层 clause
2. `record_contract_review`（复审师独立核源）：查过度约束/可执行性，过度约束→返工
3. `confirm_and_apply`（落契约版本 + stale 传播）

### 4.3 加降级恢复点 + 降级门
- 任何"跳过某契约步骤"的降级，代码里留 `debt_marker`（跳了什么、何时恢复）。
- produce-chapter 入口校验"存在 debt_marker → 警告/拒绝"。
- 降级必须可追责、可恢复，不可默默固化。先清那句"死线策略跳过"docstring。

### 4.4 契约成为唯一真相源
- brief_builder 改读契约表（卷级三表 + 章级四层）拼 brief。
- 撤掉大纲 markdown 裸拼 + 前章正文 context 注入（BFX-078 的正解）。
- 大纲降为"契约架构师起草的输入"，非产稿直接真相源。

### 4.5 加成篇连贯门 + jury 连贯维度
- coherence_gate：查同构（本章动作∩前章动作超阈值→失败）/视角越界（角色
  知情 ⊄ 契约分配→失败）/未来回环分布（本章是否落卷级分布表某锚点→缺则标记）
- jury scores 加"与前章连贯性"维度。
- 让"契约层接没接"在质量门上可观测：契约没接，连贯分必低，门会拦。

## 5. 落地顺序

1. 4.2 契约层下沉为生产子步骤
2. 4.1 produce-chapter 硬前置契约 gate
3. 4.3 降级门 + 清 debt_marker
4. 4.4 brief 改读契约表（撤正文 context）
5. 4.5 连贯门 + jury 连贯维度

## 6. 卡点（需作者裁定）

卷级三表内容（设定层，非代码层）：
- **章节功能分工表**：第N章 = 开篇/承接/转折/收束？（修 P0-1）
- **视角信息分配表**：谁在第N章知道什么？（修 P0-2）
- **未来回环分布表**：2063档案/许望舒/衡光锚点落哪章？（修 P0-3）

这三张表是作者设定权，代码层只做"读表注入 brief + 门校验"，不替作者写内容。
作者定完三表，4.2~4.5 代码接线即可开工。

## 7. 关联

- BFX-079（本根因登记，见 bugfix.md）
- BFX-078（context 注入正文原文，本根因的表层补丁，修复正解 = 4.4 撤正文 context）
- memory: ink-context-injection-raw-text-backfires（表层反例）
- memory: ink-contract-layer-rewire-root-cause（本根因，防再犯）
- 评审报告: D:\_Progs\.BetterCiv\09_工程脚本\ai_workbench\runs\
  AWT-20260715-171440-5aaf49\amy-review-synthesis.md
