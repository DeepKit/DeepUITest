# DeepFrames Bugfix Log

## 2026-06-04 — AudioProcessor: 错误使用 TProcess (FreePascal 类，Delphi 不可用)

**文件**: `src/Workflow/DeepFrames.Workflow.AudioProcessor.pas`
**严重性**: P0 (编译阻断)
**发现方式**: 代码审查
**提交**: `8a98217 fix(DeepFrames): replace TProcess with WinAPI CreateProcess in AudioProcessor`

**现象**: `RunFFmpeg` 函数使用了 `TProcess` 类（`System.Diagnostics.TProcess`），该类仅在 Lazarus/FreePascal 中存在，Delphi VCL 没有这个类。编译时直接报错 `Identifier not found "TProcess"`。

**根因**: 手写代码时未区分 FreePascal TProcess 和 Delphi WinAPI CreateProcess。

**修复**: 将 `RunFFmpeg` 改为 `Winapi.Windows.CreateProcess` + 匿名管道：
- `CreatePipe` / `ReadFile` / `WaitForSingleObject` 替代 TProcess
- `STARTF_USESTDHANDLES` 传递 stdout 句柄
- `CREATE_NO_WINDOW` 隐藏控制台
- 60 秒超时 `WaitForSingleObject`，超时 `TerminateProcess`
- 管道读取用 `PeekNamedPipe` + `ReadFile`