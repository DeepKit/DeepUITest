# DeepFrames Bugfix Log

## 2026-06-04 — AudioProcessor: 错误使用 TProcess (FreePascal 类，Delphi 不可用)

**文件**: `src/Workflow/DeepFrames.Workflow.AudioProcessor.pas:143`
**严重性**: P0 (编译阻断)
**发现方式**: 代码审查

**现象**: `RunFFmpeg` 函数使用了 `TProcess` 类（`System.Diagnostics.TProcess`），该类仅在 Lazarus/FreePascal 中存在，Delphi VCL 没有这个类。编译时直接报错 `Identifier not found "TProcess"`。

**根因**: 手写代码时未区分 FreePascal TProcess 和 Delphi WinAPI CreateProcess。

**修复**: 将 `RunFFmpeg` 中的 `TProcess` 调用改为 `Winapi.Windows.CreateProcess` + 匿名管道（`CreatePipe` / `ReadFile` / `WaitForSingleObject`）：
- 创建管道捕获 stdout/stderr
- `STARTF_USESTDHANDLES` 将写端句柄传给子进程
- `CREATE_NO_WINDOW` 隐藏控制台窗口
- 60 秒超时通过 `WaitForSingleObject` 实现
- 超时后 `TerminateProcess` 强制结束
- 管道读取用 `PeekNamedPipe` + `ReadFile`

**提交**: `fix(DeepFrames): replace TProcess with WinAPI CreateProcess in AudioProcessor`