# ink 契约层重写 · 防绕过执行方案（SPW 基线落地）

> **纲领依据**：`A0031-SPW工程执行纪律与防绕过机制.md`（BetterCiv 工程开发线共同
> 约束）。本文件是 ink 线在该基线上的专属执行细节。
> **立项**：2026-07-15，作者裁定"契约唯一真相源；删污染数据；删违反代码重写不打
> 补丁"。
> **根因**：契约=数据表字段约束（`writing_*_contracts` 表 + DB CHECK），schema 忠实
> 建了，但 produce-chapter 完全不读契约表，改从大纲裸拼 brief 产稿，只在契约表插
> 空壳行满足 DB 约束。DB 约束管不到"整表被绕过"。

---

## 一、违反"契约唯一真相源"的代码（实证 6 处，待删）

| # | 文件:行 | 违反 | 处置 |
|---|---|---|---|
| V1 | `src/ink/source/brief_builder.py` 全文 | 影子真相源：大纲裸拼 brief，"brief即契约" | **整文件删** |
| V2 | `src/ink/cli.py:1551` 调 `build_chapter_brief` | produce-chapter 用影子 brief 产稿 | 删调用，改调契约层 |
| V3 | `src/ink/cli.py:1628-1653` `_ensure_scene_and_contract` | 建伪契约：跳审查+四层空+`hash=sha256(brief)` | **整函数删重写** |
| V4 | `brief_builder.py:24-95` 跨章 context 注入 | 正文当真相源（同构根） | 随 V1 删 |
| V5 | `src/ink/source/outline_to_contract.py` 零生产调用 | 契约转换器成死代码 | **保留**，重写后被调用 |
| V6 | `src/ink/jury/scores.py:14` `chapter_continuity` | 评正文连续感代偿契约约束 | 语义重写为契约合规 |

---

## 二、污染数据（待删）

| 库 | 表 | 行数 | 处置 |
|---|---|---|---|
| `baideng_prod.db` | writing_scene_contracts / scene_contract_clauses / scene_revisions / chapter_generation_rounds / chapter_candidate_branches / candidate_branch_versions / human_decisions | 3/0/9/3/9/9/2 | 清空（保留表结构） |
| `baideng_bfx074_diag.db` | 同上一组 | 1/0/3/1/3/3/1 | 清空 |
| `baideng.db` | 0 表空壳 | — | 删文件或重建 |
| — | writing_meta_contracts（0 行）+ schema | — | **保留**，表结构正确 |

---

## 三、重写方案 · SPW 五条硬约束落地到 ink

### H1 唯一受控入口（物理断路）
- 新建 `src/ink/contract/brief_compiler.py`：`compile_brief(scene_contract_id) -> str`
  从 `writing_scene_contract_clauses` 四层 clause 编译出 brief。**brief 是契约的产
  物，不是大纲的产物**。
- 产稿函数签名改为 `generate_scene(scene_contract_id: int)`，内部调
  `compile_brief`。**不接受裸 brief 文本入参**——裸 str 入参在签名层就排除。
- 删 `build_chapter_brief` / `build_brief_from_outline`（V1）。

### H2 DB 层约束焊死
- `writing_scene_contracts` 加触发器：status 置 `active` 时，必须存在 ≥4 层且每层
  ≥1 条 `writing_scene_contract_clauses` 记录，否则 DB 拒绝激活。
- `writing_scene_contracts.source_bundle_hash` 改由 confirm 服务在置 active 时生
  成，禁止代码自行 `sha256(brief)` 赋值（删 V3）。
- `writing_scene_contracts.contract_hash` 同理，confirm 时由 DB 侧生成。

### H3 反事实测试集（8 条，进 CI 必需门）
1. 删契约 clause → `compile_brief` 必抛异常，不得降级。
2. 插空壳契约（clause 全空）→ 置 active 必被触发器拒绝。
3. 裸 str 入参调 `generate_scene` → 类型非法报错。
4. 改一条 clause → 编译出的 brief 必随之变化。
5. 绕过 `compile_brief` 直接读大纲拼 brief → 无该函数可调（V1 已删），测试确认无
   旁路 import。
6. 删任一门禁（触发器/读取门）→ mutation test 报警。
7. 出现"直接拼数据不读契约表"代码模式 → 静态扫描命中。
8. 出现"死线收口/临时跳过/简化实现"注释 → 静态扫描高风险标记。

### H4 Pre-commit 静态扫描
- AST 扫"读大纲 markdown → 拼产稿输入"模式（即 brief_builder 类旁路）。
- 正则扫高风险注释：`死线收口|临时跳过|简化实现|skips? (the )?review|deadline`。
- 命中 → 高风险标记，需人工仲裁。

### H5 异构双塔对账
- 塔 A：主编码 agent（本会话 / 编码 subagent）。
- 塔 B：异构模型（Sol 或 Kimi，与 A 不同家族），adversarial prompt"仅找代码如何违
  背 design.md + 本文件；找不到=失职；只出 PASS/FAIL+证据，不生成不改不提建议"。
- 塔 B 发现的违规 → 落成 H2/H3/H4 资产 → CI 硬门裁决。
- ink 产稿封版前必过塔 B + H1-H4，**两者皆过才封版**。

---

## 四、执行顺序

1. **删污染数据**（第二节）——止血。
2. **删违反代码**（V1/V2/V3/V4）——拆影子架构。
3. **建 H1**（brief_compiler + 改签名）+ **H2**（DB 触发器）——契约层接线+焊死。
4. **建 H3+H4**（反事实测试 + 静态扫描）——CI 门。
5. **纵向验证 1 章**——全链路跑通，确认契约约束生效、同构消除。
6. **建 H5**（异构双塔流水线）——补盲区。
7. **清 memory**——标 `brief即契约/context注入正文` 等旧记忆为 superseded。

---

## 五、待作者裁定

1. 第 1/2 章已封版正文（伪链路产物）——删除还是保留参考？
2. 卷级三表内容（章节功能分工/视角信息分配/未来回环分布）——设定权，代码只读表注入。

---

**版本**：v1.0 · **纲领**：A0031 · **批准**：作者裁定 2026-07-15。
