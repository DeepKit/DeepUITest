# InkFlow — 当前任务与议题清单

Date: 2026-07-02
Status: v3.27 多场景门禁 + UTF-8 byte 容量门禁开发完成；全量回归 531 passed, 4 warnings；第 3 章当前稿仍需按新门禁重跑后再人工 review

---

## 1. 当前结论

InkFlow 的 contract-first 主链路已经落地：confirmed 契约、章前 setup、outline hard gate、shot task card、draft eligibility、L4/L3 硬停、accepted-only export、book_run 编排和全程审计都已具备。

这次第 3 章问题不是契约完全没写清，而是生产环节把不同事件写成了同一个转运站场景，winner 又按高分重复稿晋级。现在已补两层硬拦：

- L4：按契约锚点检查正文开头是否落到对应场景，并检查相邻完成 shot 的开头重复。
- L3：检查整章 scene diversity，3 个以上 shot 至少要形成 3 个不同场景指纹，不能全落在一个场景桶。
- 容量：不再要求 AI 自己数“多少汉字”；prompt 只给 UTF-8 字符串大小要求，程序用 `len(text.encode("utf-8"))` 实算。

容量换算口径：中文 UTF-8 通常 1 个汉字约 3 bytes，含标点和少量换行后，**1KB 约等于 340 个中文字符**；本轮 gate 使用普通 titled shot `>= 1.2KB`，约 400 个中文字符，章末 titled shot `>= 1.5KB`。

详细完成记录见 `docs/history.md`；Bug 记录见 `docs/bugfix.md`（当前至 B94）。`TASKS.md` 只保留未完成任务。

---

## 2. 当前 P0 待办

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| P0 | C03-REWRITE-2 | 《白灯法则》v01.c03 按 B92-B94 新门禁重跑 | 待执行 | latest run L4/L3 passed；导出稿三个片段为不同场景；人工 review 后才可 accept |
| P0 | JURY-WINNER-ELIGIBILITY-1 | winner 选择前置资格过滤 | 待实现 | contract_scene / scene_diversity 相关硬规则在 `_select_winner()` 前淘汰候选，高分重复稿不能成为 winner |
| P0 | REPAIR-EXPAND-1 | 正确但太薄的候选进入扩写修复 | 待实现 | 正确场景稿因容量不足时优先 expand/repair，而不是被更顺滑的重复场景稿淘汰 |
| P0 | SCENE-FINGERPRINT-1 | shot contract 写入结构化场景指纹 | 待实现 | 每个 shot 有 location/time_jump/object/event anchors；gate 不只靠自然语言锚词推断 |
| P0 | AUDIT-VERIFY-1 | 真实《分流》库 v22+ 迁移与审计链验证 | 待执行 | `ink status "分流"` 正常；重跑章节后可查 setup→outline→draft→jury→gate→review 全链 |
| P0 | FAIL-ATTR-2 | 失败归因继续细化 | 部分完成 | `gate_false_positive` / `writer_drift` / `task_card_gap` 在真实样本中可稳定区分 |

---

## 3. 当前 P1 待办

| 优先级 | ID | 任务 | 当前状态 | 验收标准 |
|--------|----|------|----------|----------|
| P1 | CHAPTER-4-SETUP | 第 4 章生产前校准 | 等第 3 章重跑和人工 review | 吸收第 3 章返工结论后 `setup --chapter v01.c04 --force` |
| P1 | OBSERVABILITY-1 | 管线观测面 | 待设计 | 展示章节状态、gate 失败原因、评分分布、review 状态和 retry 归因 |
| P1 | JURY-V5-REAL | 分层裁判真实项目持续观测 | 持续 | 每章记录硬规则失败数、类型 gate 触发数、文学 9 维分布 |
| P1 | TRUTH-PROJECTION-1 | DB truth files 可读投影 | 待设计 | 可导出 project/volume/chapter/scene 级 truth projection，辅助人工校准 |

---

## 4. 当前验证命令

```powershell
cd D:\_Progs\02Business\Writer\inkflow
python -m py_compile src\inkflow\services\architect_gate.py src\inkflow\services\prompt_compiler.py
python -m pytest tests\test_architect_gate.py tests\test_prompt_compiler.py -q
python -m pytest -q
python -m inkflow.cli status "白灯法则"
```
