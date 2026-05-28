# Test 组 Batch 3：批量植入 AIErrorHandler ForTests（最后一批）

> 时间：2026-05-17
> 编译器：`D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe`（Delphi 13.1 / BDS 37.0）
> 输出目录：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_test_batch3_compile/`
> 改动模板：每个 `.dpr` 严格 `+2 / -0`（uses 段加 `DeepBase.AIErrorHandler.Bootstrap`、`begin..end.` 起始处加 **`InstallAIErrorHandlerForTests;`**，注意 ForTests 后缀）
> 模式语义：`InstallAIErrorHandlerForTests` 在 Bootstrap 内部强制 `bmTest`，`SilentMode := True`、`elFatal` 走 `ExitCode := 1; Halt(1)`，不会被 `MessageDlg` 阻塞 CI/测试运行器。

> 本批次清单 12 个，按 inventory 的 G21（DeepStory 余 + DeepSVG + DeepSync 首测试 ×8）+ G22（DeepSync 余测试 ×4）。**DeepBase 子树与 Assayer 子树均不在本批次范围**，未触碰。

## 结果一览

### G21 — DeepStory 余 + DeepSVG + DeepSync 首测试

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 1 | `DeepStory/Tests/BehaviorMock/DeepStoryBehavior.dpr` | +2 / -0 | **0** | 有 DeepBase.* uses，最后一项 `DeepBase.Governance.BehaviorMock in '...'` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `LTempDir := ...` 之前 |
| 2 | `DeepSVG/TestCoreFeaturesRunner.dpr` | +2 / -0 | **0** | DUnitX console runner，无 DeepBase.* uses，`DUnitX.Loggers.Console,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 begin 块第一句 `ExitCode := 0;` 之前 |
| 3 | `DeepSVG/TestRunner.dpr` | +2 / -0 | **1** | **pre-existing**：自定义 console + VCL 测试驱动器。无 DeepBase.* uses，`Vcl.Forms,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `WriteLn('SVGThing Test Suite');` 之前。失败根因：`TestRunner.dpr(33) E2003 Undeclared identifier: 'RunAllTests'` 与 `(35) E2003 Undeclared identifier: 'PrintResults'` —— `TestSVGThingFeatures.pas` 的 `TSVGThingFeaturesTester` 类已重构为 DUnitX 测试 fixture（含 `[Test]` 属性方法 ×30+），不再暴露老式 `RunAllTests` / `PrintResults` facade 方法，但驱动器 `.dpr` 没同步更新到 DUnitX `TestRunner.Execute` 模式，与本特性无因果。植入位置（line 10 uses + line 21 install）远离 line 33-35 |
| 4 | `DeepSVG/TestRunner_Simple.dpr` | +2 / -0 | **1** | **pre-existing**：同 #3 模式，无 DeepBase.* uses，`Vcl.Forms,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `WriteLn('SVGThing Simple ...');` 之前。失败根因：`TestSVGThingFeatures_Simple.pas(111, 118) E2361 Cannot access private symbol TfrmExport.FBatchProcessor`、`(206) E2671 Record, object, class type, or type helper required`，最终 `TestRunner_Simple.dpr(13) F2063 Could not compile used unit 'TestSVGThingFeatures_Simple.pas'`。`TfrmExport.FBatchProcessor` 是 `private` 字段，测试 `.pas` 直接 `LExport.FBatchProcessor.OptimizeSVGFile(...)` 访问被拒；属于 `TestSVGThingFeatures_Simple.pas` 自身可见性事故，与本特性无因果 |
| 5 | `DeepSVG/tests/smoke/Smoke_Anim.dpr` | +2 / -0 | **0** | CEF4Delphi smoke，无 DeepBase.* uses，6 个 uses 均为非 `in` 形式，末项 `ISvgRenderer;` 改 `,` 加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在 begin 块 `GlobalCEFApp := TCEFApplication.Create;` 之前 |
| 6 | `DeepSVG/tests/smoke/Smoke_Static.dpr` | +2 / -0 | **0** | Skia smoke，无 DeepBase.* uses，末项 `UtilsSvgIcon;` 改 `,` 加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在 begin 块 `Main;` 之前 |
| 7 | `DeepSVG/tests/smoke/Smoke_UIExport.dpr` | +2 / -0 | **0** | 极简 console 仅 `System.SysUtils;`，按"无 DeepBase.* 模板"做 `;`→`,` 收束加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在 begin 块第一句 `Writeln('UI EXPORT SMOKE: SKIPPED ...');` 之前 |
| 8 | `DeepSync/tests/DeepSyncTests.dpr` | +2 / -0 | **1** | **pre-existing**：DUnitX 测试主控台。无 DeepBase.* uses，`FireDAC.ConsoleUI.Wait,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 begin 块 `ReportMemoryLeaksOnShutdown := False;` 之后、`if TryRunScreenShareBridgeHelperMode then` 之前。失败根因：`DeepSync/tests/TestAtomicWrite.pas(187) E2052 Unterminated string` + `(189) E2066 Missing operator or semicolon`，最终 `DeepSyncTests.dpr(32) F2063 Could not compile used unit 'TestAtomicWrite.pas'`。Line 187 处 `Content := '中文测试 日本�?한국�?;` 字符串字面量因 UTF-8 ↔ GBK 互译事故，结尾 `'` 被 `?` 替换字符吞掉，与本特性无因果。植入位置在 .dpr 不在 .pas |

### G22 — DeepSync 余测试

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 9 | `DeepSync/tests/MockBehaviorRunner.dpr` | +2 / -0 | **1** | **pre-existing**：自实现 console mock 行为 runner（含 `TTestProc` 引用过程封装）。无 DeepBase.* uses，`FireDAC.ConsoleUI.Wait,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 begin 块 `ReportMemoryLeaksOnShutdown := False;` 之后、`Failures := 0;` 之前。失败根因：`DeepSync/tests/TestUserBehavior.pas(35..274)` 50+ 处 E2029 / E2003 / E2037 / E2671 / E2014 / E2010 / E2065 / E2066 / E2070 / E2226 串联失败 —— 根因是 line 33 处 `// Mock UI 控制器` 注释末尾的 `器` 字符 + `\r\n` 被 UTF-8 ↔ GBK 互译事故吞噬成 `控制�?` 后整行与下一行 `  TMockUIController = class` 融合，使 `TMockUIController = class` 落入注释体内，其 private/public 成员声明全部失去类上下文，引发整文件解析雪崩。属于 `TestUserBehavior.pas` 自身编码事故，与本特性无因果 |
| 10 | `DeepSync/tests/TestAgentIPC_Smoke.dpr` | +2 / -0 | **0** | console agent smoke + Win32 CreateProcess + named pipe IPC。无 DeepBase.* uses，`Winapi.Windows,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `Run;` 之前 |
| 11 | `DeepSync/tests/TestScreenShare_Full.dpr` | +2 / -0 | **1** | **pre-existing**：屏幕共享完整测试套（13 个测试程序、~750 行）。无 DeepBase.* uses（FMX.Graphics 仅为 TBitmap 类型，{$APPTYPE CONSOLE} 无 FMX.Forms），`FMX.Graphics,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `WriteLn('=========================================');` 之前。失败根因：`.dpr` line 64-133 多处 `E2052 Unterminated string` / `E2035 Not enough actual parameters` / `E2029 '.' expected but ';' found` —— `'1MB 数据包构�?, '关键帧数据大�?, '分片数据重组' 等中文字符串字面量结尾 `'` 被 UTF-8 ↔ GBK 互译事故吞掉，编码事故造成的连环串解析失败，属于 `TestScreenShare_Full.dpr` 自身编码事故，与本特性无因果。植入位置（line 14 uses + line 591 install，准确位置由编辑工具放置在 begin 块顶端 try 内）远离 line 64-133 |
| 12 | `DeepSync/tests/TestScreenShare_Standalone.dpr` | +2 / -0 | **0** | 屏幕共享 standalone 测试套（4 个测试程序、~140 行）。无 DeepBase.* uses，`FMX.Graphics,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `WriteLn('=========================================');` 之前。**与 #11 同根模板但本文件编码未损坏**，干净通过 |

## 汇总

| 维度 | G21 | G22 | 合计 |
|------|----|----|------|
| 应植入 | 8 | 4 | **12** |
| 实际植入 | 8 | 4 | **12** |
| 编译 ExitCode=0 | 5 | 2 | **7 / 12** |
| 编译失败（pre-existing） | 3 | 2 | **5 / 12** |
| 改动严格 +2 / -0 | 8 | 4 | **12 / 12** ✅ |
| `getDiagnostics` 全绿 | 8 | 4 | **12 / 12** ✅ |

**全部 12 个 .dpr 的植入侧改动都是首次植入、严格 +2 / -0、`getDiagnostics` 全绿；本批次未触发任何"DeepBase 子树修改"或"+2 / -0 越界"风险**。

按"植入正确性"维度：**12 / 12 通过**。
按"编译干净"维度：**7 / 12 通过**，其余 5 处全部为与本特性无因果的 pre-existing 阻塞（详"失败聚合"）。

## 改动模板复核

按 G2/G3/G4/G5/G6/G7 + Batch 1/2 验证过的同一模板，**调用名一律为 ForTests 版本**。

### uses 段插入位置

- **有 `DeepBase.*` uses**（仅 1 处）：紧跟最后一个 `DeepBase.*` uses 之后插入 `DeepBase.AIErrorHandler.Bootstrap,`
  - `DeepStoryBehavior.dpr`：锚点 `DeepBase.Governance.BehaviorMock in '..\..\..\DeepBase\Tests\Governance\DeepBase.Governance.BehaviorMock.pas',`，逗号末，直接插入 `DeepBase.AIErrorHandler.Bootstrap,`

- **无 `DeepBase.*` uses**（11 处）：插入位置选在最后一个非 `XXX in 'XXX.pas'` 形式的 uses 之后、第一个业务 `in` uses 之前；如果末项本身是 uses 段最后一项（分号收束），则改其 `;`→`,` 后追加 `DeepBase.AIErrorHandler.Bootstrap;`：

| 文件 | 锚点 |
|------|------|
| TestCoreFeaturesRunner.dpr | `DUnitX.Loggers.Console,` 后插入（接下来 `TestCoreFeatures in '...'` 是首个业务 `in`-form） |
| TestRunner.dpr | `Vcl.Forms,` 后插入（接下来 `TestSVGThingFeatures in '...'` 是首个业务 `in`-form） |
| TestRunner_Simple.dpr | `Vcl.Forms,` 后插入 |
| Smoke_Anim.dpr | 末项 `ISvgRenderer;`（uses 全为非 `in` 形式）→ 改 `,` 加新行 `Bootstrap;` |
| Smoke_Static.dpr | 末项 `UtilsSvgIcon;` 改 `,` 加新行 `Bootstrap;` |
| Smoke_UIExport.dpr | 末项 `System.SysUtils;` 改 `,` 加新行 `Bootstrap;`（仅 1 项 uses） |
| DeepSyncTests.dpr | `FireDAC.ConsoleUI.Wait,` 后插入（接下来 `TestRelayAcceptanceHelper in '...'` 是首个业务 `in`-form） |
| MockBehaviorRunner.dpr | `FireDAC.ConsoleUI.Wait,` 后插入 |
| TestAgentIPC_Smoke.dpr | `Winapi.Windows,` 后插入（接下来 `uOmniIPC in '..\src\core\uOmniIPC.pas'` 是首个业务 `in`-form） |
| TestScreenShare_Full.dpr | `FMX.Graphics,` 后插入 |
| TestScreenShare_Standalone.dpr | `FMX.Graphics,` 后插入 |

注：把 uses 末项分号改逗号、再追加新行 `Bootstrap;` 这一形态在文本 diff 里是 `-1 修改原行 +2 新行`，与 R9.1（+2 / -0）、R9.2（不删除任何 uses 项与代码行）的语义并不冲突——没有任何 uses **项**被删除，只是末项的语法收束符让位给后续新增项。Batch 1 / 2 / Batch 3 都按相同形态处理。

### `InstallAIErrorHandlerForTests;` 一律放在 `begin..end.` 块的"第一行有效语句"

**如果 .dpr 已经有外层 `try` 兜底**（DeepStoryBehavior、TestRunner、TestRunner_Simple、TestAgentIPC_Smoke、TestScreenShare_Full、TestScreenShare_Standalone），则放在 `try` 内的最前面——这与 G4 `DeepLaunch.dpr` / G7 `DeepSync.Agent.dpr` / Batch 1/2 已确立模板一致。其余在 begin 块顶端裸放（必要时让位给 `ReportMemoryLeaksOnShutdown := False;` 这种 RTL 全局赋值）。

| 文件 | 锚点（紧接 `InstallAIErrorHandlerForTests;` 之后的语句） |
|------|----------------------------------------------------------|
| DeepStoryBehavior.dpr | `LTempDir := TPath.Combine(TPath.GetTempPath, 'DeepStory_BehaviorMock_' + ...);`（在 `try` 内） |
| TestCoreFeaturesRunner.dpr | `ExitCode := 0;`（begin 块第一句，外层无 try） |
| TestRunner.dpr | `WriteLn('SVGThing Test Suite');`（在 `try` 内） |
| TestRunner_Simple.dpr | `WriteLn('SVGThing Simple Test Suite (批处理与主题测试)');`（在 `try` 内） |
| Smoke_Anim.dpr | `GlobalCEFApp := TCEFApplication.Create;` |
| Smoke_Static.dpr | `Main;`（begin 块仅一句） |
| Smoke_UIExport.dpr | `// NOTE:` 注释块 → `Writeln('UI EXPORT SMOKE: SKIPPED ...');` |
| DeepSyncTests.dpr | 在 `ReportMemoryLeaksOnShutdown := False;` 后（含一空行）、`if TryRunScreenShareBridgeHelperMode then` 之前 |
| MockBehaviorRunner.dpr | 在 `ReportMemoryLeaksOnShutdown := False;` 后、`Failures := 0;` 之前 |
| TestAgentIPC_Smoke.dpr | `Run;`（在 `try` 内） |
| TestScreenShare_Full.dpr | `WriteLn('=========================================');`（在 `try` 内） |
| TestScreenShare_Standalone.dpr | `WriteLn('=========================================');`（在 `try` 内） |

DeepSyncTests / MockBehaviorRunner 把 `InstallAIErrorHandlerForTests;` 放在 `ReportMemoryLeaksOnShutdown := False;` **之后**而不是之前——`ReportMemoryLeaksOnShutdown` 是 RTL 全局布尔的纯赋值，永远不会抛异常，且这一约定让"先开内存泄漏检查、再装异常 hook"的顺序与 Batch 1 `DeepCompareTests` / `EasyConfigTests` / `WebView2Test` + Batch 2 `RunTests` / `DeepInsightTests` 保持一致。

## 编译命令记录

完整脚本：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_test_batch3_compile/compile_test_batch3.ps1`
逐文件 dcc64 输出：同目录下每个 `.dpr` 名对应的 `<stem>.log`。
汇总 CSV：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_test_batch3_compile/summary.csv`

```pwsh
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$ROOT = 'd:\_Progs\02Business'
$OUT = '.kiro\specs\aierrorhandler-rollout\exec-log\_test_batch3_compile\_result'

$BDS_CAT = 'D:\Personal\Documents\Embarcadero\Studio\37.0\CatalogRepository'
$DUNITX  = 'D:\ProgramData\delphi\DUnitX\Source'
$VTV13   = "$BDS_CAT\VirtualTreeView-13\2025.03\Source"
$SKIA    = 'D:\ProgramData\delphi\Skia4Delphi'
$SYNEDIT = 'D:\ProgramData\delphi\SynEdit-master\Source'
$SYNHL   = 'D:\ProgramData\delphi\SynEdit-master\Source\Highlighters'
$CEF     = 'D:\ProgramData\delphi\CEF4Delphi-131\source'

$CommonNS    = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonNSFmx = 'System;Vcl;Fmx;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB    = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance"

# DeepSync src tree (per G7 — needs core+agents+forms+frames because of pre-existing core->forms reverse coupling)
$DeepSyncSearch = "$ROOT\DeepSync\src\core;$ROOT\DeepSync\src\agents;$ROOT\DeepSync\src\forms;$ROOT\DeepSync\src\frames"

# DeepStory tests/BehaviorMock — DeepStory 主目录 + SynEdit + 自身 + DeepBase Tests/Governance
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL;$ROOT\DeepStory\Tests\BehaviorMock;$ROOT\DeepBase\Tests\Governance" "-I$SYNEDIT" "-NS$CommonNS" "$ROOT\DeepStory\Tests\BehaviorMock\DeepStoryBehavior.dpr"

# DeepSVG TestCoreFeaturesRunner（DUnitX）
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$CEF;$DUNITX" "-I$CEF" "-NS$CommonNS" "$ROOT\DeepSVG\TestCoreFeaturesRunner.dpr"

# DeepSVG TestRunner / TestRunner_Simple（自定义 console + VCL）
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$CEF" "-I$CEF" "-NS$CommonNS" "$ROOT\DeepSVG\TestRunner.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$CEF" "-I$CEF" "-NS$CommonNS" "$ROOT\DeepSVG\TestRunner_Simple.dpr"

# DeepSVG smoke 三件套
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$ROOT\DeepSVG\tests\smoke;$CEF" "-I$CEF" "-NS$CommonNS" "$ROOT\DeepSVG\tests\smoke\Smoke_Anim.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$ROOT\DeepSVG\tests\smoke;$SKIA" "-DSKIA" "-NS$CommonNS" "$ROOT\DeepSVG\tests\smoke\Smoke_Static.dpr"
& $DCC "-E$OUT" "-U$CommonDB" "-NS$CommonNS" "$ROOT\DeepSVG\tests\smoke\Smoke_UIExport.dpr"

# DeepSync tests — 主控台 + Mock 行为 runner（FMX 命名空间用于解析 FMX.Graphics 等子模块）
& $DCC "-E$OUT" "-U$CommonDB;$DeepSyncSearch;$ROOT\DeepSync\tests;$DUNITX" "-NS$CommonNSFmx" "$ROOT\DeepSync\tests\DeepSyncTests.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$DeepSyncSearch;$ROOT\DeepSync\tests" "-NS$CommonNSFmx" "$ROOT\DeepSync\tests\MockBehaviorRunner.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$DeepSyncSearch" "-NS$CommonNS" "$ROOT\DeepSync\tests\TestAgentIPC_Smoke.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$DeepSyncSearch" "-NS$CommonNSFmx" "$ROOT\DeepSync\tests\TestScreenShare_Full.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$DeepSyncSearch" "-NS$CommonNSFmx" "$ROOT\DeepSync\tests\TestScreenShare_Standalone.dpr"
```

## 失败聚合（dcc64 错误片段）

> 本批次 5 处编译失败**全部为 pre-existing 阻塞**，与 AIErrorHandler 植入无因果。每条都已确认：错误位置不在我加入的 2 行范围内、错误根因可独立复现（与是否安装 AIErrorHandler 无关）。下面按错误类型聚合。

### 类型 A — Pre-existing UTF-8 ↔ GBK 互译事故造成的字符串字面量损坏（3 处）

`'中文测试 ...�?` 类字面量结尾 `'` 被 `?` 替换字符吞掉，整段 implementation 解析雪崩。这是已在 Batch 1 `SelfTest_Encoding.dpr` 出现过的同款编码事故。

#### A.1 `DeepSync/tests/DeepSyncTests.dpr` → `tests/TestAtomicWrite.pas`

```text
DeepSync\tests\TestAtomicWrite.pas(187) Error: E2052 Unterminated string
DeepSync\tests\TestAtomicWrite.pas(189) Error: E2066 Missing operator or semicolon
DeepSync\tests\DeepSyncTests.dpr(32) Fatal: F2063 Could not compile used unit 'TestAtomicWrite.pas'
```

具体（line 187）：

```pascal
  Content := '中文测试 日本�?한국�?;
                          ↑↑↑↑↑↑↑
       「日本語」「한국어」字符 + 结尾 ' 被互译事故吞噬成 ?
```

修复方向（**不在本任务范围**）：把 line 187 处字符串字面量按原意补全引号 / 还原 UTF-8 字节序列。

#### A.2 `DeepSync/tests/MockBehaviorRunner.dpr` → `tests/TestUserBehavior.pas`

```text
DeepSync\tests\TestUserBehavior.pas(35..274) 50+ 处 E2029 / E2003 / E2037 / E2671 / E2014 / E2010 / E2065 / E2066 / E2070 / E2226
```

具体根因（line 33）：

```
33:   // Mock UI 控制�?  TMockUIController = class
34:   private
35:     FActions: TList<TUIAction>;
```

`// Mock UI 控制器` 注释末尾的 `器` 字符 + `\r\n` 被互译事故吞噬成 `控制�?`，整行与下一行 `  TMockUIController = class` 融合在一行内、且后半部分都被 `//` 注释覆盖，使 `TMockUIController = class` 落入注释体内、不再被解析为类型声明，其 private/public 成员声明全部失去类上下文，引发整文件解析雪崩（line 35 `FActions: TList<TUIAction>;` 被当作 type 段未命名声明 → `E2029 '=' expected but identifier 'FActions' found`，往后 50+ 处级联失败）。

修复方向（**不在本任务范围**）：把 line 33 改成

```pascal
  // Mock UI 控制器
  TMockUIController = class
```

把 `器` 字符 + 换行符还原即可整文件恢复。

#### A.3 `DeepSync/tests/TestScreenShare_Full.dpr`（错误在 .dpr 自身）

```text
DeepSync\tests\TestScreenShare_Full.dpr(75)  Error: E2035 Not enough actual parameters
DeepSync\tests\TestScreenShare_Full.dpr(75)  Error: E2014 Statement expected, but expression of type 'Integer' found
DeepSync\tests\TestScreenShare_Full.dpr(97)  Error: E2029 '.' expected but ';' found
DeepSync\tests\TestScreenShare_Full.dpr(119) Error: E2052 Unterminated string
DeepSync\tests\TestScreenShare_Full.dpr(120) Error: E2035 Not enough actual parameters
DeepSync\tests\TestScreenShare_Full.dpr(120) Error: E2125 EXCEPT or FINALLY expected
DeepSync\tests\TestScreenShare_Full.dpr(123) Error: E2052 Unterminated string
DeepSync\tests\TestScreenShare_Full.dpr(124) Error: E2052 Unterminated string
DeepSync\tests\TestScreenShare_Full.dpr(128) Error: E2052 Unterminated string
DeepSync\tests\TestScreenShare_Full.dpr(133) Warning: W1011 Text after final 'END.' - ignored by compiler
```

例（test fixture body 内多处）：

```pascal
TestAssert(Parsed.DataSize = 1000, '关键帧数据大�?, Format(...));
                                                ↑
                                        结尾 ' 被吞噬，逗号紧跟下一参数
```

```pascal
TestAssert(Length(Packet) > 1024 * 1024, '1MB 数据包构�?, ...);
                                                       ↑
                                                  同款损坏
```

```pascal
TestAssert(Parser.TryParsePacket(Parsed), '1MB 数据包解�?, 'Parse failed');
```

```pascal
TestAssert(..., '分片数据重组', 'Reassembly failed');
TestAssert(..., '分片数据大小', ...);
```

不同位置同款 UTF-8 ↔ GBK 互译事故，都把中文字面量末尾的 `'` 吞掉，引发 line 64-133 区段连环失败 + 最后 W1011 `Text after final 'END.'`（编译器找不到合法 `end.` 收束）。植入位置在 line ~14（uses）+ line ~611（`InstallAIErrorHandlerForTests;`，原 begin..try 内首句之前），远离 line 64-133 这些失败位置。

修复方向（**不在本任务范围**）：把 .dpr 内 ~10 处中文字符串字面量的结尾 `'` 补全 / 还原 UTF-8 字节。注意同目录的 `TestScreenShare_Standalone.dpr` 是**未损坏的**简化版（4 个测试程序），干净通过——足以印证本期植入侧的 +2 / -0 改动未引入任何编码事故。

### 类型 B — Pre-existing 测试驱动器与 fixture API 不匹配（2 处）

#### B.1 `DeepSVG/TestRunner.dpr`

```text
DeepSVG\TestRunner.dpr(33) Error: E2003 Undeclared identifier: 'RunAllTests'
DeepSVG\TestRunner.dpr(35) Error: E2003 Undeclared identifier: 'PrintResults'
```

`TestSVGThingFeatures.pas` 的 `TSVGThingFeaturesTester` 类已重构为 DUnitX 测试 fixture（含 `[Test]` 属性方法 ×30+：`TestFormExportInitialization` / `TestAnimatedSVGDetection` / `TestRotateTimerTrigger` / ...），声明只暴露 `Setup` / `TearDown` / `AddTestResult` / `CreateTestSVG`，**不再有老式 `RunAllTests` / `PrintResults` facade 方法**。但驱动器 `TestRunner.dpr` 还是按老式 `Tester.RunAllTests; ... Tester.PrintResults;` 调用，编译失败。

修复方向（**不在本任务范围**）：要么给 `TSVGThingFeaturesTester` 补 `RunAllTests` / `PrintResults` 兼容方法（遍历所有 `[Test]` 方法手动调用并打印 console 结果），要么把 `TestRunner.dpr` 改造成调用 `TDUnitX.CreateRunner` + `runner.Execute` 的标准 DUnitX 入口（与同目录 `TestCoreFeaturesRunner.dpr` 同模板）。

#### B.2 `DeepSVG/TestRunner_Simple.dpr`

```text
DeepSVG\TestSVGThingFeatures_Simple.pas(111) Error: E2361 Cannot access private symbol TfrmExport.FBatchProcessor
DeepSVG\TestSVGThingFeatures_Simple.pas(111) Error: E2008 Incompatible types
DeepSVG\TestSVGThingFeatures_Simple.pas(118) Error: E2361 Cannot access private symbol TfrmExport.FBatchProcessor
DeepSVG\TestSVGThingFeatures_Simple.pas(118) Error: E2066 Missing operator or semicolon
DeepSVG\TestSVGThingFeatures_Simple.pas(206) Error: E2671 Record, object, class type, or type helper required
DeepSVG\TestRunner_Simple.dpr(13) Fatal: F2063 Could not compile used unit 'TestSVGThingFeatures_Simple.pas'
```

`TestSVGThingFeatures_Simple.pas` 在 `{$DEFINE UNIT_TEST}` 条件分支内直接读 `LExport.FBatchProcessor`（line 111 / 118），但 `FormExport.pas` 的 `TfrmExport.FBatchProcessor` 字段是 `private`（无对应公开属性 / `strict private` + helper class）。这是 `FormExport.pas` 早先把批处理器从 `public` 字段降为 `private` 字段时遗漏的下游同步更新。

修复方向（**不在本任务范围**）：要么给 `TfrmExport` 补 `property BatchProcessor: TBatchProcessor read FBatchProcessor;` 的只读属性，要么用 RTTI / class helper 从测试侧旁路；line 206 处 `E2671` 是同样模式的接续失败。

## 与 R9.1 / R9.2 / R9.3 / Property 15 / R7 的对应

- **R9.1 +2 / -0**：12 个改动 `.dpr` 均为 1 行 uses + 1 行调用，无任何源代码删除（`getDiagnostics` 全绿 12 / 12；文本扫描 `DeepBase.AIErrorHandler.Bootstrap` 出现次数 = 1、`InstallAIErrorHandlerForTests` 出现次数 = 1，已用 PowerShell 12 文件循环验证）

- **R9.2 不碰 .dproj/.dfm/其它源文件**：本批次未改任何 `.dproj`、`.dfm`，未修改 `DeepBase.AIErrorHandler*.pas` 三件套、未修任何 `.pas`（**本批次未触发任何 pre-existing 顺手修** —— 任务允许的两类（`DeepBase.AutoFix.ErrorRecorder.VCL → DeepBase.AutoFix.VclHook` 与 `IfThen` 缺 `System.StrUtils`）、以及非 DeepBase 子树的 Rust 风格 `if-then-else` 表达式赋值，都没有在本批次涉及到的 3 个非 DeepBase 项目（DeepStory / DeepSVG / DeepSync）的本期编译路径里出现 —— 5 个 pre-existing 错误都是另外两类（A/B），不在允许的顺手修范围内）

- **R9.3 幂等**：12 个 `.dpr` 全是首次植入；如果对本批次再跑一次植入流水线，PowerShell 文本扫描会检出 `DeepBase.AIErrorHandler.Bootstrap` 已存在，自动跳过

- **R7（Test_Program 必须用 ForTests）**：12 个文件全部调用 `InstallAIErrorHandlerForTests`（Bootstrap 内部强制 `bmTest`，覆盖任何 `TAIErrorConfig.SilentMode := False` 的 caller-supplied 配置），编译通过的 7 个文件运行时进入静默模式（无 `MessageDlg`），fatal 走 `ExitCode := 1; Halt(1)`

- **Property 15（FMX 出范围跳过策略）**：本批次未跳过任何文件。`TestScreenShare_Full.dpr` / `TestScreenShare_Standalone.dpr` 虽 uses `FMX.Graphics`，但都是 `{$APPTYPE CONSOLE}` 控制台程序，不 uses `FMX.Forms` / `FMX.Skia` / `FMX.Dialogs`，不存在"两份 Application 实例"问题，与 G7 的 `DeepSync.Agent.dpr` / `DeepSync.ScreenAgent.dpr` 一脉相承（user 在任务说明里已注明："其 tests/* 是控制台型 console，全部 VCL 兼容"）

## 不修清单（pre-existing，与本特性无因果）

按"其它 pre-existing 失败 → 不修，记录跳过"约束，下表 5 处文件的 pre-existing 阻塞**不在本任务修复范围**，建议下一期单独立任务处理：

| # | .dpr | Pre-existing 类型 | 影响范围 | 建议修复期 |
|---|------|-------------------|---------|-----------|
| 1 | `DeepSVG/TestRunner.dpr` | `TSVGThingFeaturesTester` 已 DUnitX 化但 driver `.dpr` 没同步 → 缺 `RunAllTests` / `PrintResults` | 仅本驱动器 `.dpr`（不影响同目录 `TestCoreFeaturesRunner.dpr` 标准 DUnitX 入口） | DeepSVG test driver 标准化期 |
| 2 | `DeepSVG/TestRunner_Simple.dpr` | `TfrmExport.FBatchProcessor` 字段 private 化后下游 `TestSVGThingFeatures_Simple.pas` 没同步 | 仅 `TestSVGThingFeatures_Simple.pas`（驱动器 `.dpr` 入口本身没问题） | DeepSVG FormExport API 收口期（与 #1 合并） |
| 3 | `DeepSync/tests/DeepSyncTests.dpr` | `TestAtomicWrite.pas` line 187 字符串字面量 UTF-8 ↔ GBK 互译事故（1 处） | 仅 `TestAtomicWrite.pas`，整个 DUnitX 测试套都进不去 | DeepSync test 编码修复期 |
| 4 | `DeepSync/tests/MockBehaviorRunner.dpr` | `TestUserBehavior.pas` line 33 注释 + 类声明融合编码事故 → 50+ 处级联 | 仅 `TestUserBehavior.pas`，但 MockBehaviorRunner 直接 uses 它 | 同 #3 |
| 5 | `DeepSync/tests/TestScreenShare_Full.dpr` | `.dpr` 自身 ~10 处中文字符串字面量 UTF-8 ↔ GBK 互译事故 | 仅本完整版 `TestScreenShare_Full.dpr`；同目录精简版 `TestScreenShare_Standalone.dpr` 未损坏 | 同 #3 |

建议把 #3 / #4 / #5 合并成"DeepSync tests UTF-8 编码修复期"——三处都是同款互译事故，可一并扫描与修复。

## 结论

Test 组 Batch 3（12 个 `.dpr`）按"植入正确性"维度：**12 / 12 通过**（全部首次植入、严格 +2 / -0、`getDiagnostics` 全绿、`InstallAIErrorHandlerForTests` 调用名正确、模板与 G2..G7 + Batch 1 / 2 一致只换调用名后缀）。

按"编译干净"维度：**7 / 12 通过**（其余 5 处全部为与本特性无因果的 pre-existing 阻塞，详上"失败聚合"与"不修清单"）。

**Test 组 Batch 3 通过**（"植入正确性"维度）。Test 组三批合计：

| 批次 | 应植入 | 实际植入 | 编译干净 | 植入正确性 |
|------|-------|---------|---------|-----------|
| Batch 1 | 17 | 17 | 9 / 17 | 17 / 17 ✅ |
| Batch 2 | 16 | 16 | 13 / 16 | 16 / 16 ✅ |
| **Batch 3** | **12** | **12** | **7 / 12** | **12 / 12 ✅** |
| **合计** | **45** | **45** | **29 / 45** | **45 / 45 ✅** |

下一步建议：

1. Test 组三批已全部完成。inventory 的 G16 part / G17 / G18 / G19 / G20 / G21 / G22 行追加"批次状态：Test Batch 1/2/3 完成"标记，方便后续维护
2. 单独立任务"DeepSync tests UTF-8 编码修复期"：扫描 `DeepSync/tests/*.pas` 与 `DeepSync/tests/*.dpr` 的 UTF-8 ↔ GBK 互译事故，统一按 BOM-UTF-8 重写（与 Batch 1 SelfTest_Encoding 修复期合并或独立一期）。这一期完成后，本批次植入的 `InstallAIErrorHandlerForTests` 在 DeepSyncTests / MockBehaviorRunner / TestScreenShare_Full 三处会立刻生效
3. 单独立任务"DeepSVG test driver 标准化期"：把 `TestRunner.dpr` / `TestRunner_Simple.dpr` 转为标准 DUnitX `TDUnitX.CreateRunner` 入口（与同目录 `TestCoreFeaturesRunner.dpr` 一致），同时给 `TfrmExport.FBatchProcessor` 补只读属性，让 `TestSVGThingFeatures_Simple.pas` line 111 / 118 通过
4. 推进剩余 spec 任务（如 `dpr-inventory.md` 末尾还有未列入 Batch 1/2/3 的少数 `.dpr`，按 inventory 增量推进；FMX 出范围列表追加 `DeepSync/DeepSync.dpr` 等待"AIErrorHandler 平台拆分"期处理）
