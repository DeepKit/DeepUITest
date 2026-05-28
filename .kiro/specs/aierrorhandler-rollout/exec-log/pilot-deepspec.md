# 试点：DeepSpec 植入与编译

> 时间：2026-05-16
> 程序：`DeepSpec/DeepSpec.dpr`
> 改动量：2 行新增（uses + 调用），0 行删除
> 编译规模：11764 行 / 9.4MB exe

## DeepSpec.dpr 的两处改动

```diff
   DeepBase.Manager,
   DeepBase.Persistence.Manager.FireDAC,
   DeepBase.AutoFix.ErrorRecorder,
-  DeepBase.AutoFix.ErrorRecorder.VCL,
+  DeepBase.AutoFix.VclHook,
+  DeepBase.AIErrorHandler.Bootstrap,
   DeepSpec.MainForm in 'src\app\DeepSpec.MainForm.pas',
```

```diff
 begin
   ReportMemoryLeaksOnShutdown := True;
+  InstallAIErrorHandler;                     // AI runtime error handler (chains to AutoFix below)
   TAutoFixErrorRecorder.Install;       // Core (cross-platform)
-  TAutoFixErrorRecorderVCL.HookApplication;  // VCL: hook Application.OnException
+  TAutoFixVclHook.Install;             // VCL: hook Application.OnException (no-op unless --autofix-mode)
   Application.Initialize;
```

## 期间发现并修复的 pre-existing 问题（DeepSpec 试点的连锁反应）

试点的核心目标——"加 1 行 uses + 1 行调用"——本身只触发了 2 行变更。但拖出来的 **pre-existing 问题** 把任务 6.2 编译过程中的真实改动量推到了 5 处：

| # | 文件 | 问题 | 修复 |
|---|------|------|------|
| 1 | `DeepBase/Core/DeepBase.AutoFix.StackWalker.pas:31` | `function CaptureStack(ASkip: Integer = 1; AMaxFrames: Integer = 20; out ATruncated: Boolean): TArray<TStackFrame>;` —— `out ATruncated` 不能有默认值，但前面两个参数有默认值，触发 `E2238 Default value required for 'ATruncated'` | 删掉 ASkip 和 AMaxFrames 的默认值（两个调用方 `ErrorRecorder.pas:250` 和 `SelfTerminator.pas:117` 都已显式传 `(2, 20, LStackTruncated)`，默认值实际未被引用） |
| 2 | `DeepBase/Core/DeepBase.AutoFix.ErrorRecorder.pas:279` | 任务 4.2 阶段 sub-agent 修 Pattern 3 时用了 `IfThen`，但该单元 implementation uses 段没有 `System.StrUtils` | implementation uses 加 `System.StrUtils,` |
| 3 | `DeepSpec/DeepSpec.dpr:27` | 引用了**不存在的单元** `DeepBase.AutoFix.ErrorRecorder.VCL`（DeepBase 历史重命名遗留，现在叫 `DeepBase.AutoFix.VclHook`） | 改为 `DeepBase.AutoFix.VclHook` |
| 4 | `DeepSpec/DeepSpec.dpr:60` | `TAutoFixErrorRecorderVCL.HookApplication` 也是同一波重命名遗留，类已重命名为 `TAutoFixVclHook`，方法叫 `Install` | 改为 `TAutoFixVclHook.Install` |
| 5 | （略，与改动 1-4 关联）`DeepBase.AutoFix.SelfTerminator.pas:117` | 也调用 `CaptureStack(2, 20, LStackTruncated)`，未受 #1 修复影响（因为已经显式传 3 个参数） | 无需改 |

第 1、2 处改动的影响域局限于 DeepBase.AutoFix.* 子系统；第 3、4 处只改 DeepSpec.dpr 一个文件。改动 4.2 阶段做的全工作区 grep 不会重复触发这些路径。

## 编译命令

```pwsh
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
& $DCC "-Ed:\_Progs\02Business\DeepSpec\bin\Win64\Debug" `
       "-U$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;
         d:\_Progs\02Business\DeepSpec\src\app;
         ...\controllers;...\core;...\models;...\providers;...\services" `
       "-NSSystem;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC" `
       "d:\_Progs\02Business\DeepSpec\DeepSpec.dpr"
```

## 输出

- ExitCode：0
- 产物：`d:\_Progs\02Business\DeepSpec\bin\Win64\Debug\DeepSpec.exe`（9395776 bytes / 9.4 MB）
- 仅有的 hint/warning 都是 pre-existing：
  - `EStackOverflow is deprecated` × 2
  - `MessageDlg has not been expanded because unit 'System.UITypes' is not specified` × 2
  - `Private symbol 'GetCacheKey' declared but never used`
  - `Value assigned to 'InstallAIErrorHandler' never used`（防御式 `Result := False;` 初值，无害）

## 6.2 通过

试点程序静态可编译。下一步 6.3 端到端烟测需要 GUI 启动与人工交互，须用户参与。
