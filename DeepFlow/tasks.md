# DeepFlow 开发任务清单

> 更新日期: 2026-08-07
>
> 当前状态: **DeepFlow v1.0 核心完成 + 正名术语纠正完成 + 类型标识符重命名完成**

---

## 进行中

### 工单 WO-20260806-0001-luoji: 文档/代码项目名统一

> 法源: ADR-002 | 执行: 2026-08-06 已全部完成
> 此工单所有子任务已交付，待 complete 正式归档。

| # | 子任务 | 状态 | 完成 |
|---|--------|------|------|
| R1 | 文档正文项目名统一 (73篇 .md) | 已完成 | f7a9b2f2 |
| R2 | 修复03.07自指错误 | 已完成 | f7a9b2f2 |
| R3 | 代码unit名同步改名 (68个.pas) | 已完成 | 77b750c6 |
| R4 | uses引用同步改名 (127处) | 已完成 | 77b750c6 |
| R5 | schema URI与URL纠正 | 已完成 | f7a9b2f2 |
| R6 | 组件名中英并列 | 已完成 | f7a9b2f2 |
| R7 | 术语表扩写为权威基准 | 已完成 | f7a9b2f2 |
| R8 | ADR备案 | 已完成 | f7a9b2f2 |

---

## 待办 (ADR-002 遗留项 & 后续)

### TASK-0102: .pas 既有 UTF-8 损坏修复
- **范围**: 41个 .pas 文件, 其中24个阻碍编译
- **描述**: 入库时即存在的 UTF-8 损坏 (中文/全角字符第三字节 0x3f, 部分闭合引号塌缩), 需按上下文语义逐字还原
- **复杂度**: High (大量手工)
- **状态**: pending

### TASK-0103: 外部 DeepBase.* 依赖配置
- **范围**: 21处 `DeepBase.*` not found
- **描述**: 配 .dpr/.dproj 工程文件时统一处理外部依赖路径
- **复杂度**: Medium
- **状态**: pending

### TASK-0104: 编辑器 favicon 与清理
- **范围**: Editor/index.html + 冗余 prompts
- **描述**: 清理 code_review/qa_assistant/system_default 3个冗余prompt, Editor 加 favicon
- **复杂度**: Low
- **状态**: 已完成 (3902526a)

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
| 冗余清理 | 3个冗余prompt删除 + Editor favicon | 已完成 |
| 类型标识符重命名 | 25个文件 477处 TUniFlowXxx→TDeepFlowXxx, 零残留 | 已完成 (本分支) |

---

## 未来路线图 (待决策)

### .pas UTF-8 损坏修复
- 41个文件，24个阻碍编译，需逐字语义还原

### 外部依赖配置
- 21处 DeepBase.* not found，需配工程文件

---

## 相关文档

- `hiDeepStory.md` - 开发历史详细记录
- `bugfix.md` - Bug 修复详细记录
- `ADR/ADR-002-术语纠正与unit改名.md` - 正名决策记录
- `tools/verify-term-rename.py` - 术语一致性检查脚本
- `docs/zh/` - 中文文档

---

## 优先级说明

- **TASK-01xx**: 正名遗留项
- **P0**: 紧急阻塞性问题
- **P1**: MVP 必需
- **P2**: 完整功能
- **P3**: 维护优化