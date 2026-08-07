# DeepFlow 开发任务清单

> 更新日期：2026-08-07
>
> 当前状态：**DeepFlow v1.0 核心完成 + 正名术语纠正完成 + 类型标识符重命名完成**

---

## 待办 (TASK-0102 & TASK-0103)

### TASK-0102: .pas UTF-8 损坏修复 (P0)
- **范围**: 41 个 .pas 文件，其中 24 个阻碍编译
- **描述**: 
  - 入库时即存在的 UTF-8 损坏（中文/全角字符第三字节 0x3f，部分闭合引号塌缩）
  - worktree diff HEAD 已发现 39 个文件的损坏点：`值？`,冒号缺失，行末字符塌缩等
  - 需像 simple_qa.workflow.json 一样按上下文语义逐字还原
- **复杂度**: High (大量手工)
- **状态**: pending (已在 bugfix.md 记录为 BUG-2026-007)

### TASK-0103: 外部 DeepBase.*依赖配置
- **范围**: 21 处 `DeepBase.*` not found
- **描述**: 配 .dpr/.dproj 工程文件时统一处理外部依赖路径
- **复杂度**: Medium
- **状态**: pending

---

## 已完成里程碑

### 核心开发里程碑 (2024-12 ~ 2025-12)

| 里程碑 | 内容 | 状态 |
|--------|------|------|
| M1 | 核心框架 (Phase 1-3) | 已完成 |
| M2 | 完整流程 (Phase 4-6) | 已完成 |
| M3 | 生产就绪 (Phase 7-8) | 已完成 |
| P2 | 可选增强 (Audit/Metrics/Skills/Editor) | 已完成 |
| P3 | 维护任务 (SQLite/WebSocket/CI/Docs) | 已完成 |
| P4-A | DeepBase 集成 | 已完成 |
| P4-B | 中文文档 | 已完成 |
| P4-C | Event Sourcing | 已完成 |
| P4-D | 分析与可视化 | 已完成 |
| P4-E | 性能优化 | 已完成 |
| P4-F | 多租户支持 | 已完成 |
| P4-G | 插件系统 | 已完成 |
| P5-A | 生产加固 | 已完成 |
| P5-B | 功能增强 | 已完成 |
| P5-C | 平台集成 | 已完成 |
| P6-A | 云原生支持 | 已完成 |
| P6-B | AI 增强 | 已完成 |

### DeepFlow 正名 (2026-08-06)

| 任务 | 内容 | 状态 |
|------|------|------|
| 文档正名 | 73 篇 .md UniFlow 转 DeepFlow, 两层命名 UpFlow/deepFlow | 已完成 |
| 代码 unit 改名 | 68 个 .pas unit/program/uses 全改 DeepFlow.* | 已完成 |
| schema URI 纠正 | $id uniflow:// 转 deepflow://, author/URL 同步 | 已完成 |
| 03.07 自指修复 | 标题/对比表/命名约定修正 | 已完成 |
| 术语表扩写 | 02.07 补 UpFlow/deepFlow 条目 | 已完成 |
| ADR 备案 | ADR-002 已批准 | 已完成 |
| 冗余清理 | 3 个冗余 prompt 删除 + Editor favicon | 已完成 |
| 类型标识符重命名 | 25 个文件 477 处 TUniFlowXxx→TDeepFlowXxx, 零残留 | 已完成 (commit fb6fbadf) |

---

## 相关文档

- `history.md` - 开发历史详细记录
- `bugfix.md` - Bug 修复详细记录
- `ADR/ADR-002-术语纠正与 unit 改名.md` - 正名决策记录
- `tools/verify-term-rename.py` - 术语一致性检查脚本
- `docs/zh/` - 中文文档

---

## 优先级说明

- **TASK-01xx**: 正名遗留项
- **P0**: 紧急阻塞性问题
- **P1**: MVP 必需
- **P2**: 完整功能
- **P3**: 维护优化
