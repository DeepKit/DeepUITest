# InkFlow v2 当前任务队列

> **状态**：Pre-M0-M6 baseline、非 shot 级 resume baseline、真实 LLM provider 配置入口、manual LLM 验收记录、参数化 setup、CLI JSON/dry-run 已完成本地验证。已完成任务已归档到 `history.md`，修复记录见 `bugfix.md`。
> **最后更新**：2026-07-06

---

## 当前开发原则

- `tasks.md` 只保留未完成任务和下一步开发队列。
- 已完成里程碑、决策和验收证据移入 `history.md`。
- 开发中发现的缺陷、原因、修复和防回归测试记录到 `bugfix.md`。
- 默认本地验收命令：`cd ink && python -m pytest`。

---

## P0 当前任务

- 当前无未完成 P0。下一批开发从 P1 产品化任务中按优先级推进。

## P1 产品化任务

- [ ] 增加阈值调参记录：shot/chapter/book quality floor、reader pull、blind review、soft gate N 的运行数据回放。

## P2 后续架构增强

- [ ] 为未来 PostgreSQL/RLS 迁移补数据库适配层边界说明和最小兼容测试。
- [ ] 将测试 fixture/builder 从各测试文件中抽到共享工厂，减少重复插入样板。
- [ ] 增加性能基线测试：mock LLM 下单 shot、6 章 smoke、CLI 一章流程的耗时上限。
