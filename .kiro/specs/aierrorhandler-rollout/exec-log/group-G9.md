# G9 组 (Tool_Program)：DeepBase 辅助工具 + 嵌入子项目 — AIErrorHandler 植入

> 时间：2026-05-18
> 编译器：`D:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe`（Delphi 13.1）
> 输出目录：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g9_compile/`
> 改动模板：每个 `.dpr` 严格 `+2 / -0`（uses 段加 `DeepBase.AIErrorHandler.Bootstrap`、`begin..end.` 起始处加 `InstallAIErrorHandler;`）
> 对应 spec 任务：tasks.md 任务 12 / inventory G9

## 结果一览

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 1 | `DeepBase/Tools/LogAnalyzer/LogAnalyzer.dpr` | +2 / -0 | **1** | **pre-existing**：`LogAnalyzer.MainForm.pas:186/349/560` 多处 `E2052 Unterminated string`（中文字符串未正确闭合，文件本身坏）；与 AIErrorHandler 改动无关 |
| 2 | `DeepBase/Tools/SeedTool/SeedTool.dpr` | +2 / -0 | **0** | VCL，clean |
| 3 | `DeepBase/DeepFlow/Source/DeepFlow.dpr` | **skipped** | N/A | **FMX 入口**（`uses System.StartUpCopy, FMX.Forms`），按 design.md "决策与权衡"出范围；inventory 误归类为 VCL（与 G4/G7/G8 的 FMX 误归类同质），登记到 inventory 末尾"补充 FMX 出范围"小节 |
| 4 | `DeepBase/doQry/prjDoQry.dpr` | +2 / -0 | **1** | **pre-existing**：`uDoQryLegacy.pas(8) Fatal: F2613 Unit 'ADODB' not found.` —— `ADODB` 在 `Data.Win.ADODB` 命名空间，需要在 dcc64 -NS 加 `Data.Win` 才能解析；与 AIErrorHandler 改动无关 |
| 5 | `DeepInsight/tools/DeepBasePathValidator.dpr` | +2 / -0 | **1** | **pre-existing 重要**：`DeepBase.Initialize` 等多处被解析为"unit name not found"，因为 `DeepBase` 同时是 `DeepBase.Manager` 单元里的全局函数 + `DeepBase.*` 命名空间前缀，dcc64 在两者之间产生歧义。**反向校验**：临时去掉本任务两行新增、用同一 dcc64 命令编译，仍然报相同错误 → 确认与 AIErrorHandler 改动无关 |
| 6 | `DeepSync/tools/BuildRunner.dpr` | +2 / -0 | **0** | 控制台，clean |

## 汇总

| 维度 | 计数 |
|------|------|
| 应植入（inventory G9） | 6 |
| 实际植入 | 5 |
| 跳过（FMX） | 1（DeepFlow） |
| 编译 ExitCode=0 | **2** / 5 |
| 编译失败（pre-existing） | **3** / 5（LogAnalyzer / prjDoQry / DeepBasePathValidator） |
| 改动严格 +2 / -0 | **5 / 5** ✅ |

## 改动模板复核（与 G2..G8 一致）

- **VCL Application（已有 `Vcl.Forms`）**：紧邻 `Vcl.Forms,` 之后插入 `DeepBase.AIErrorHandler.Bootstrap in '..\..\Core\DeepBase.AIErrorHandler.Bootstrap.pas',`
  - LogAnalyzer：锚点 `Vcl.Forms,`（byte-inject，文件含 GBK 中文 mojibake `日志分析�?`）
  - SeedTool：锚点 `Vcl.Forms,`（byte-inject，文件含 GBK 中文 `���۸Ĳ��ֹ���`）
  - prjDoQry：锚点 `Vcl.Forms,`（strReplace 即可，clean UTF-8）
- **纯控制台**：紧邻 `System.SysUtils,` 之后插入 `DeepBase.AIErrorHandler.Bootstrap,`（裸名，Bootstrap 路径靠 dcc64 -U DeepBase\Core 解析，无需 `in 'path'` 子句）
  - DeepBasePathValidator：与既有 `DeepBase.Manager,` 同一裸名风格
  - BuildRunner：单独成行 `DeepBase.AIErrorHandler.Bootstrap;` 紧邻 `Winapi.ShellAPI,`
- `InstallAIErrorHandler;` 一律放在 `begin` 之后**首条**语句

## 编码注意事项

- `LogAnalyzer.dpr` 与 `SeedTool.dpr` 头部 `Application.Title` 的中文字符串是 GBK / 部分丢失编码，UTF-8 文本工具会重写整文件触发 byte-level diff。本次用 `_g8_compile/_inject.ps1` 字节级插入，git numstat 严格 `+2 / -0`。
- 其他 3 个文件（prjDoQry / DeepBasePathValidator / BuildRunner）clean UTF-8，strReplace 即可。

## 留给同事 / 后续 spec 的事

- `LogAnalyzer.MainForm.pas` 多个中文字符串行被 GBK→UTF-8 转换截断 → 文件源码坏，需要从备份恢复或重新编辑
- `prjDoQry.dpr` -NS 添加 `Data.Win` 即可（compile_all.bat 里 DeepCompare 这条已经这么做）
- `DeepBasePathValidator.dpr` 把 `if not DeepBase.Initialize then` 改成 `var LMgr := DeepBase; if not LMgr.Initialize then ...`，避免 `DeepBase.X` 命名歧义
- 都不属本 spec 范畴
