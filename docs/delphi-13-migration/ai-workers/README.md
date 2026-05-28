# 四组 AI 并行工作分配

> 每个 Kiro 实例打开后,将对应的工作指令文件内容粘贴到首条消息中

| AI 代号 | 聚焦领域 | 项目 | 指令文件 |
|---|---|---|---|
| **Pixel** | Skia/CEF 图形渲染 | DeepSVG → DeepMoveC → DeepShine → DeepClip | `pixel-instructions.md` |
| **Stream** | LLM/流式网络 | Assayer → DeepCompare → DeepInsight → DeepInput | `stream-instructions.md` |
| **Coder** | IDE/编辑器 | DeepDev → DeepStory → DeepDevLite → DeepSync | `coder-instructions.md` |
| **Forge** | 配置/工具/多组件 | DeepConfig → DeepCharset → DeepLaunch → DeepRenew | `forge-instructions.md` |

## 冲突隔离规则

- 每个 AI 只能修改自己分配的项目目录
- 公共文件（`scripts/env/`、`docs/delphi-13-migration/`）只读,不修改
- DeepBase 目录任何 AI 都不能修改（由人类单独处理）
- 如需更新 COMPATIBILITY.md,写到自己项目的 migration-notes 中,由人类统一合并
