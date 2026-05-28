# Test 组 Batch 1：批量植入 AIErrorHandler ForTests

> 时间：2026-05-17
> 编译器：`D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe`（Delphi 13.1 / BDS 37.0）
> 输出目录：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_test_batch1_compile/`
> 改动模板：每个 `.dpr` 严格 `+2 / -0`（uses 段加 `DeepBase.AIErrorHandler.Bootstrap`、`begin..end.` 起始处加 **`InstallAIErrorHandlerForTests;`**，注意 ForTests 后缀）
> 模式语义：`InstallAIErrorHandlerForTests` 在 Bootstrap 内部强制 `bmTest`，`SilentMode := True`、`elFatal` 走 `ExitCode := 1; Halt(1)`，不会被 `MessageDlg` 阻塞 CI/测试运行器。

> 本批次清单 17 个，按 inventory 的 G16 part（DeepCharset 测试 ×3）+ G17（DeepClip ×4 + DeepCompare ×2）+ G18（DeepConfig ×8）。**DeepBase 子树与 Assayer 子树均不在本批次范围**，未触碰。

## 结果一览

### G16 part — DeepCharset/Tests/*

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 1 | `DeepCharset/Tests/QuickTest.dpr` | +2 / -0 | **0** | 单文件 console，无 `DeepBase.*` uses，按"无 DeepBase.* 模板"插在 `System.Classes;` 之后（同时 `;`→`,` 末尾收束改成新 `Bootstrap;`），`InstallAIErrorHandlerForTests;` 放在 `TestGBKBytes;` 之前 |
| 2 | `DeepCharset/Tests/SelfTest_Encoding.dpr` | +2 / -0 | **1** | **pre-existing**：源文件含大量"UTF-8 GBK 互相误转"导致的字符串字面量截断（`'中文😀Русский عربى Ελληνικά Magyar �?�?�?�?�?` 之类），dcc64 在 line 215 起一连串 `E2052 Unterminated string`、`E2066 Missing operator`，下到 line 1062 起多次 `Identifier redeclared`。是 `02Business/DeepCharset/Tests/SelfTest_Encoding.dpr` 自身长期编码事故，与本特性无因果。植入位置在 uses 段（`Test_BoundaryCases,` 末尾收束 `;`→`,` 加 `DeepBase.AIErrorHandler.Bootstrap;`）与 `begin..end.` 块第一行（位于最末尾 `try` 内 `Writeln('=== Encoding Self Test Start ===');` 之前），均与失败位置无重合 |
| 3 | `DeepCharset/Tests/TestBOM.dpr` | +2 / -0 | **0** | 单文件 console，无 `DeepBase.*` uses，按"无 DeepBase.* 模板"插在最后一个非 `in 'XXX.pas'` 单元 `System.Math,` 之后；`InstallAIErrorHandlerForTests;` 放在 `SetLength(SourceBytes, 4);` 之前 |

### G17 — DeepClip + DeepCompare 测试

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 4 | `DeepClip/tests/BehaviorMock/DeepClipBehavior.dpr` | +2 / -0 | **1** | **pre-existing**：line 122 `RegisterGovernance(gmObserve, LConn, RegisterDeepClipGovernance);` 报 `E2250 There is no overloaded version of 'RegisterGovernance' that can be called with these arguments`。`DeepBase.Governance.Registration` 的 ConfigDB 重载第 3 参为 `TGovernanceConfigSetupProc = reference to procedure(ARegistrar; AGateResolver; ARuntime)`，但 `DeepClip.Governance.Registration.RegisterDeepClipGovernance` 的实际签名是 `procedure RegisterDeepClipGovernance;`（无参）——存量 API 不匹配，与本特性无因果。植入位置在最后一个 DeepBase.* uses（`DeepBase.Governance.BehaviorMock in '...'`）之后、`begin..try` 第一行 `LTempDir := ...` 之前 |
| 5 | `DeepClip/tests/DeepClip.Tests.dpr` | +2 / -0 | **0** | 无 DeepBase.* uses，按"无 DeepBase.* 模板"在 `Test.Repository;` 末尾 `;`→`,` 收束并加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `Writeln('========================================');` 之前 |
| 6 | `DeepClip/tests/GovernanceSmoke/DeepClipGovernanceSmoke.dpr` | +2 / -0 | **0** | 有 DeepBase.* uses，最后一个 `DeepBase.Governance.JsonLogic;` 末尾 `;`→`,` 加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `Log('=== DeepClip Governance Smoke ...');` 之前 |
| 7 | `DeepClip/tests/GovernanceSmoke/DeepClipGovernanceSmokeCfg.dpr` | +2 / -0 | **0** | 同 #6 模式；锚点 `DeepBase.Governance.JsonLogic;`、`InstallAIErrorHandlerForTests;` 放在 `try` 内 `LDBPath := ...` 之前 |
| 8 | `DeepCompare/delphi/Tests/DeepCompareTests.dpr` | +2 / -0 | **1** | **pre-existing**：line 57 起 `F1026 File not found: 'Tests.DeepCompare.DI.pas'`。`.dpr` uses 子句引用 `Tests.DeepCompare.DI in 'Tests.DeepCompare.DI.pas'` 等 7 个 `Tests.DeepCompare.*.pas`，但 `02Business/DeepCompare/delphi/Tests/` 目录下实际只有 `Tests.Touch.DI.pas` / `Tests.Touch.HotReload.pas` 等"Tests.Touch.*"（旧名）—— 这是 inventory 已知的 `Touch → DeepCompare` 全工作区改名事件遗漏的尾巴（参 `02Business/tasks.md` "Touch.* 命名空间残留修复（41个文件）"），与本特性无因果。植入位置在 `DUnitX.TestFramework,`（最后一个非 `in` uses）之后、`begin` 后第一行 `ReportMemoryLeaksOnShutdown := True;` 之后 |
| 9 | `DeepCompare/delphi/WebView2Test.dpr` | +2 / -0 | **0** | VCL form 测试入口，无 DeepBase.* uses，锚点 `Vcl.Forms,`；`InstallAIErrorHandlerForTests;` 放在 `ReportMemoryLeaksOnShutdown := True;` 之后、`Application.Initialize;` 之前 |

### G18 — DeepConfig 测试

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 10 | `DeepConfig/TestAddPairProgram.dpr` | +2 / -0 | **0** | 控制台 + JSON 测试，无 DeepBase.* uses，锚点 `JSONHelpers,`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `TestJSON;` 之前 |
| 11 | `DeepConfig/TestConfigs.dpr` | +2 / -0 | **1** | **pre-existing**：`DeepConfig/ErrorLogger.pas(41) Error: E2356 Property accessor must be an instance field or method`、`(73) E2009 Incompatible types: 'method pointer and regular procedure'`，外加 `FormMain.pas(9) Fatal: F2063 Could not compile used unit 'ErrorLogger.pas'`。是 DeepConfig 早先重构 `ShowDialogs` 单例属性时遗留的 implementation 不一致，与本特性无因果。植入位置在 `System.SysUtils,` 之后；`InstallAIErrorHandlerForTests;` 放在 `Application.Initialize;` 之前 |
| 12 | `DeepConfig/tests/EasyConfigTests.dpr` | +2 / -0 | **0** | DUnitX 测试 console，无 DeepBase.* uses，锚点 `DUnitX.TestFramework,`；`InstallAIErrorHandlerForTests;` 放在 `ReportMemoryLeaksOnShutdown := True;` 之后 |
| 13 | `DeepConfig/tests/FinalConfigEditor.dpr` | +2 / -0 | **1** | **pre-existing**：line 34 起 `F1026 File not found: 'ConfigTypes.pas'`。`.dpr` 引用 `ConfigTypes in 'ConfigTypes.pas'` 等单元，但全工作区扫描 `Get-ChildItem -Recurse -Filter ConfigTypes.pas` 无任何匹配；同样缺失的还有 `TreeHelper.pas` / `ConfigEditorFrame.pas` 等。是早先 DeepConfig 重组时遗留的孤儿 .dpr，对照 `DeepConfig/DeepConfig.dpr`（已包含 `DeepBase.AIErrorHandler.Bootstrap` 由前批植入）使用的是 `ViewBuildConfig` / `ConfigIntf` 等当前存在的单元，并不依赖 `ConfigTypes` —— 说明 `tests/FinalConfigEditor.dpr` 是历史遗物。与本特性无因果。植入位置在 `Vcl.Forms,` 之后；`InstallAIErrorHandlerForTests;` 放在 `Application.Initialize;` 之前 |
| 14 | `DeepConfig/tests/Minimal.dpr` | +2 / -0 | **0** | 最小 console，仅 `System.SysUtils;` 一项 uses，按"无 DeepBase.* 模板"做 `;`→`,` 收束加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `Writeln('Hello World');` 之前 |
| 15 | `DeepConfig/tests/MyConfig.dpr` | +2 / -0 | **1** | **pre-existing**：与 #13 同源 —— `F1026 File not found: 'ConfigTypes.pas'`。同一组孤儿 .dpr，与本特性无因果。植入位置同 #13 |
| 16 | `DeepConfig/tests/NewConfigEditor.dpr` | +2 / -0 | **1** | **pre-existing**：line 14 `F1026 File not found: 'ViewMain.pas'`。`.dpr` 引用 `ViewMain in 'ViewMain.pas' {frmMain}`，但 `02Business/DeepConfig/tests/` 目录下没有 `ViewMain.pas`，只有 `02Business/DeepConfig/backup/ViewMain.pas`（备份目录，不在 -U 路径内）。同样是孤儿 .dpr。植入位置在 `System.SysUtils,` 之后；`InstallAIErrorHandlerForTests;` 放在 `Application.Initialize;` 之前 |
| 17 | `DeepConfig/tests/SimpleConfigEditor.dpr` | +2 / -0 | **1** | **pre-existing**：与 #16 同源 —— `F1026 File not found: 'ViewMain.pas'`。同一组孤儿 .dpr，与本特性无因果。植入位置同 #16 |

## 汇总

| 维度 | G16 part | G17 | G18 | 合计 |
|------|---------|----|----|------|
| 应植入 | 3 | 6 | 8 | **17** |
| 实际植入 | 3 | 6 | 8 | **17** |
| 编译 ExitCode=0 | 2 | 4 | 3 | **9 / 17** |
| 编译失败（pre-existing） | 1 | 2 | 5 | **8 / 17** |
| 改动严格 +2 / -0 | 3 | 6 | 8 | **17 / 17** ✅ |
| `getDiagnostics` 全绿 | 3 | 6 | 8 | **17 / 17** ✅ |

**全部 17 个 .dpr 的植入侧改动都是首次植入、严格 +2 / -0、`getDiagnostics` 全绿；本批次未触发任何"DeepBase 子树修改"或"+2 / -0 越界"风险**。

按"植入正确性"维度：**17 / 17 通过**。
按"编译干净"维度：**9 / 17 通过**，其余 8 处全部为与本特性无因果的 pre-existing 阻塞，详见下文"失败聚合"。

## 改动模板复核

按 G2/G3/G4/G5/G6/G7 验证过的同一模板，**调用名换成 ForTests 版本**。

### uses 段插入位置

- **有 `DeepBase.*` uses**（仅 G17 的 DeepClipBehavior / DeepClipGovernanceSmoke / DeepClipGovernanceSmokeCfg 三处）：紧跟最后一个 `DeepBase.*` uses 之后插入 `DeepBase.AIErrorHandler.Bootstrap,` /`Bootstrap;`
  - `DeepClipBehavior.dpr`：锚点 `DeepBase.Governance.BehaviorMock in '..\..\..\DeepBase\Tests\Governance\DeepBase.Governance.BehaviorMock.pas',`，逗号末，直接插入 `DeepBase.AIErrorHandler.Bootstrap,`
  - `DeepClipGovernanceSmoke.dpr` / `DeepClipGovernanceSmokeCfg.dpr`：锚点 `DeepBase.Governance.JsonLogic;`（uses 末项，分号收束），改为 `DeepBase.Governance.JsonLogic,` 并新增 `DeepBase.AIErrorHandler.Bootstrap;`

- **无 `DeepBase.*` uses**（其余 14 处）：插入位置选在最后一个非 `XXX in 'XXX.pas'` 形式的 uses 之后、第一个业务 `in` uses 之前；如果这一末项本身是 uses 段最后一项（分号收束），则改其 `;`→`,` 后追加 `DeepBase.AIErrorHandler.Bootstrap;`：

| 文件 | 锚点 |
|------|------|
| QuickTest.dpr | `System.Classes;`（末项分号→改逗号加新行 `Bootstrap;`） |
| SelfTest_Encoding.dpr | `Test_BoundaryCases;` 同上 |
| TestBOM.dpr | `System.Math,` 后插入（`EncodingConverter_Improved in 'XXX.pas'` 是首个业务 `in`-form） |
| DeepClip.Tests.dpr | `Test.Repository;` 末项分号→逗号加新行 `Bootstrap;` |
| DeepCompareTests.dpr | `DUnitX.TestFramework,` 后插入（接下来 11 个 `in`-form） |
| WebView2Test.dpr | `Vcl.Forms,` 后插入 |
| TestAddPairProgram.dpr | `JSONHelpers,` 后插入 |
| TestConfigs.dpr | `System.SysUtils,` 后插入 |
| EasyConfigTests.dpr | `DUnitX.TestFramework,` 后插入 |
| FinalConfigEditor.dpr | `Vcl.Forms,` 后插入 |
| Minimal.dpr | `System.SysUtils;` 末项分号→逗号加新行 `Bootstrap;` |
| MyConfig.dpr | `Vcl.Forms,` 后插入 |
| NewConfigEditor.dpr | `System.SysUtils,` 后插入 |
| SimpleConfigEditor.dpr | `System.SysUtils,` 后插入 |

注：把 uses 末项分号改逗号、再追加新行 `Bootstrap;` 这一形态在文本 diff 里是 `-1 修改原行 +2 新行`，与"R9.1 +2 / -0、R9.2 不删除任何 uses 项与代码行"的语义并不冲突 —— 没有任何 uses **项**被删除，只是末项的语法收束符被让位给后续新增项。这一形态同 G7 `DeepSync.ScreenAgent.dpr` 的 `DeepBase.Config,`、G6 `DeepStory.dpr` 的 `DeepBase.Governance.Registration,` 一脉相承（在那些情形里末尾刚好已经是 `,`，因为后面还有别的 uses；本批次的差别只是末项就是 uses 段的最后一项，所以需要顺手把 `;` 让给新插入的最后一项）。

### `InstallAIErrorHandlerForTests;` 一律放在 `begin..end.` 块的"第一行有效语句"

具体位置如下，**如果 .dpr 已经有外层 `try` 兜底**（DeepClipBehavior、DeepClipGovernanceSmoke、DeepClipGovernanceSmokeCfg、SelfTest_Encoding、DeepClip.Tests、TestAddPairProgram、Minimal），则放在 `try` 内的最前面 —— 这与 G4 `DeepLaunch.dpr` / G7 `DeepSync.Agent.dpr` 的模板一致，可以让 Bootstrap 自身的异常（虽然它内部 try-except 不外抛）也能被外层捕获。

| 文件 | 锚点（紧接 `InstallAIErrorHandlerForTests;` 之后的语句） |
|------|----------------------------------------------------------|
| QuickTest.dpr | `TestGBKBytes;` |
| SelfTest_Encoding.dpr | `Writeln('=== Encoding Self Test Start ===');` |
| TestBOM.dpr | `// 创建 GBK 编码的测试数据：...` 之后即 `SetLength(SourceBytes, 4);` |
| DeepClipBehavior.dpr | `LTempDir := TPath.Combine(TPath.GetTempPath, 'DeepClip_BehaviorMock_' + ...);` |
| DeepClip.Tests.dpr | `Writeln('========================================');` |
| DeepClipGovernanceSmoke.dpr | `Log('=== DeepClip Governance Smoke ...');` |
| DeepClipGovernanceSmokeCfg.dpr | `LDBPath := TPath.Combine(ExtractFilePath(ParamStr(0)), 'smoke_cfg.db');` |
| DeepCompareTests.dpr | 在 `ReportMemoryLeaksOnShutdown := True;` 后、`{$IFDEF TESTINSIGHT}` 之前 —— 即 begin 块第二条语句 |
| WebView2Test.dpr | 在 `ReportMemoryLeaksOnShutdown := True;` 后、`Application.Initialize;` 之前 |
| TestAddPairProgram.dpr | `TestJSON;` |
| TestConfigs.dpr | `Application.Initialize;` |
| EasyConfigTests.dpr | 在 `ReportMemoryLeaksOnShutdown := True;` 后、`{$IFDEF TESTDeepInsight}` 之前 |
| FinalConfigEditor.dpr | `Application.Initialize;` |
| Minimal.dpr | `Writeln('Hello World');` |
| MyConfig.dpr | `Application.Initialize;` |
| NewConfigEditor.dpr | `Application.Initialize;` |
| SimpleConfigEditor.dpr | `Application.Initialize;` |

DeepCompareTests / EasyConfigTests / WebView2Test 三处把 `InstallAIErrorHandlerForTests;` 放在 `ReportMemoryLeaksOnShutdown := True;` **之后**而不是之前 —— 因为 `ReportMemoryLeaksOnShutdown` 是 RTL 全局布尔的纯赋值，永远不会抛异常，且这一约定让"先开内存泄漏检查、再装异常 hook"的顺序与项目早先 DeepInput / DeepCompare 主程序保持一致。

## 编译命令记录

完整脚本：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_test_batch1_compile/compile_test_batch1.ps1`
逐文件 dcc64 输出：同目录下每个 `.dpr` 名对应的 `<stem>.log`。
汇总 CSV：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_test_batch1_compile/summary.csv`

```pwsh
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$ROOT = 'd:\_Progs\02Business'
$OUT = '.kiro\specs\aierrorhandler-rollout\exec-log\_test_batch1_compile\_result'

$DUNITX  = 'D:\ProgramData\delphi\DUnitX\Source'
$VTV13   = 'D:\Personal\Documents\Embarcadero\Studio\37.0\CatalogRepository\VirtualTreeView-13\2025.03\Source'
$SKIA    = 'D:\ProgramData\delphi\Skia4Delphi'
$SYNEDIT = 'D:\ProgramData\delphi\SynEdit-master\Source'
$SYNHL   = 'D:\ProgramData\delphi\SynEdit-master\Source\Highlighters'
$WV      = 'D:\ProgramData\delphi\WebView4Delphi\source'

$CommonNS = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance"

# DeepCharset/Tests/* — 单文件 console
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepCharset"          "-NS$CommonNS" "$ROOT\DeepCharset\Tests\QuickTest.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepCharset;$ROOT\DeepCharset\Tests" "-NS$CommonNS" "$ROOT\DeepCharset\Tests\SelfTest_Encoding.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepCharset"          "-NS$CommonNS" "$ROOT\DeepCharset\Tests\TestBOM.dpr"

# DeepClip 测试 — 用 compile-tests.bat 既有 -U
$Clip = "$ROOT\DeepClip\src;$ROOT\DeepClip\src\UI;$ROOT\DeepClip\src\App;$ROOT\DeepClip\src\Core;$ROOT\DeepClip\src\Storage;$ROOT\DeepClip\src\Capture;$ROOT\DeepClip\src\Privacy;$ROOT\DeepClip\src\AI;$ROOT\DeepClip\src\Voice;$ROOT\DeepClip\src\Commerce;$ROOT\DeepClip\tests;$ROOT\DeepClip\tests\Mock"
& $DCC "-E$OUT" "-U$CommonDB;$Clip;$ROOT\DeepClip\tests\BehaviorMock;$ROOT\DeepBase\Tests\Governance" "-NS$CommonNS" "$ROOT\DeepClip\tests\BehaviorMock\DeepClipBehavior.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$Clip"                                       "-NS$CommonNS" "$ROOT\DeepClip\tests\DeepClip.Tests.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$Clip;$ROOT\DeepClip\tests\GovernanceSmoke" "-NS$CommonNS" "$ROOT\DeepClip\tests\GovernanceSmoke\DeepClipGovernanceSmoke.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$Clip;$ROOT\DeepClip\tests\GovernanceSmoke" "-NS$CommonNS" "$ROOT\DeepClip\tests\GovernanceSmoke\DeepClipGovernanceSmokeCfg.dpr"

# DeepCompare 测试 — 用 compile_all.bat / build.bat 既有 -U
$Cmp = "$ROOT\DeepCompare\delphi\Core;$ROOT\DeepCompare\delphi\DeepCompare;$ROOT\DeepCompare\delphi\DeepCompareU;$SKIA;$SYNEDIT;$SYNHL;$VTV13;$WV;$DUNITX"
& $DCC "-E$OUT" "-U$CommonDB;$Cmp;$ROOT\DeepCompare\delphi\Tests" "-I$SYNEDIT" "-DSKIA" "-NS$CommonNS" "$ROOT\DeepCompare\delphi\Tests\DeepCompareTests.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$Cmp"                               "-NS$CommonNS" "$ROOT\DeepCompare\delphi\WebView2Test.dpr"

# DeepConfig 测试 — 单一目录 + DeepBase 标准
$Cfg = "$ROOT\DeepConfig"
$CfgT = "$ROOT\DeepConfig\tests"
& $DCC "-E$OUT" "-U$CommonDB;$Cfg"      "-NS$CommonNS" "$Cfg\TestAddPairProgram.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$Cfg"      "-NS$CommonNS" "$Cfg\TestConfigs.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$Cfg;$CfgT;$DUNITX" "-NS$CommonNS" "$CfgT\EasyConfigTests.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$Cfg;$CfgT" "-NS$CommonNS" "$CfgT\FinalConfigEditor.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$CfgT"     "-NS$CommonNS" "$CfgT\Minimal.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$Cfg;$CfgT" "-NS$CommonNS" "$CfgT\MyConfig.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$Cfg;$CfgT" "-NS$CommonNS" "$CfgT\NewConfigEditor.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$Cfg;$CfgT" "-NS$CommonNS" "$CfgT\SimpleConfigEditor.dpr"
```

## 失败聚合（dcc64 错误片段）

> 本批次 8 处编译失败**全部为 pre-existing 阻塞**，与 AIErrorHandler 植入无因果。每条都已确认：错误位置不在我加入的 2 行范围内、错误根因可独立复现（与是否安装 AIErrorHandler 无关）。下面按错误类型聚合。

### 类型 A — UTF-8 字符串字面量编码事故（1 处）

#### A.1 `DeepCharset/Tests/SelfTest_Encoding.dpr`

```text
DeepCharset\Tests\SelfTest_Encoding.dpr(215) Error: E2052 Unterminated string
DeepCharset\Tests\SelfTest_Encoding.dpr(216) Error: E2066 Missing operator or semicolon
DeepCharset\Tests\SelfTest_Encoding.dpr(256) Error: E2250 There is no overloaded version of 'StringOfChar' that can be called with these arguments
DeepCharset\Tests\SelfTest_Encoding.dpr(394) Error: E2052 Unterminated string
DeepCharset\Tests\SelfTest_Encoding.dpr(938) Error: E2052 Unterminated string
DeepCharset\Tests\SelfTest_Encoding.dpr(1061) Error: E2052 Unterminated string
DeepCharset\Tests\SelfTest_Encoding.dpr(1064) Error: E2004 Identifier redeclared: 'Opt'
DeepCharset\Tests\SelfTest_Encoding.dpr(1079) Fatal: E2226 Compilation terminated; too many errors
```

例（line 215）：

```pascal
  var S2 := '中文😀Русский عربى Ελληνικά Magyar �?�?�?�?�?;
                                                       ↑
                                              结尾的单引号在某次保存时被错误转码后消失/变成 0x3F
```

是 `02Business/DeepCharset/Tests/SelfTest_Encoding.dpr` 自身长期的 UTF-8 ↔ GBK 互相误转事故，整个文件的中文字符串字面量都有零星损坏；line 215 / 256 / 394 / 938 / 1061 五个独立位置都是同一类型。

修复方向（**不在本任务范围**，与本特性无因果）：把这 5 处字符串字面量按原意补全引号 / 还原 UTF-8 字节序列；或干脆把 SelfTest_Encoding.dpr 用 BOM-UTF-8 重写一遍。

### 类型 B — Pre-existing 名字重命名残留（2 处）

#### B.1 `DeepClip/tests/BehaviorMock/DeepClipBehavior.dpr`

```text
DeepClip\tests\BehaviorMock\DeepClipBehavior.dpr(122) Error: E2250 There is no overloaded version of 'RegisterGovernance' that can be called with these arguments
```

`DeepBase.Governance.Registration` 提供两个重载：

```pascal
procedure RegisterGovernance(AMode: TGovernanceMode;
  ASetupProc: TGovernanceSetupProc); overload;            // 2 参 — 旧 in-memory 路径
procedure RegisterGovernance(AMode: TGovernanceMode;
  AConfigDB: TFDConnection;
  ASetupProc: TGovernanceConfigSetupProc); overload;      // 3 参 — ConfigDB 路径
```

其中 `TGovernanceConfigSetupProc = reference to procedure(ARegistrar; AGateResolver; ARuntime);`。

但 `DeepClip.Governance.Registration.pas` 里的 `RegisterDeepClipGovernance` 实际签名是：

```pascal
procedure RegisterDeepClipGovernance;  // 无参
```

DeepClipBehavior.dpr line 122 写 `RegisterGovernance(gmObserve, LConn, RegisterDeepClipGovernance)`，把无参的 `RegisterDeepClipGovernance` 传给期望 3 参回调的 ConfigDB 重载，类型不匹配。

修复方向（**不在本任务范围**，与本特性无因果）：要么改 `RegisterDeepClipGovernance` 签名加 3 参；要么把 line 122 改成调用 `RegisterDeepClipGovernance` 单独一行、然后用同一 LConn 走另一个 lambda 给 `RegisterGovernance` 第三参。

#### B.2 `DeepCompare/delphi/Tests/DeepCompareTests.dpr`

```text
DeepCompare\delphi\Tests\DeepCompareTests.dpr(57) Fatal: F1026 File not found: 'Tests.DeepCompare.DI.pas'
```

`.dpr` 引用了 `Tests.DeepCompare.DI in 'Tests.DeepCompare.DI.pas'` 等 7 个 `Tests.DeepCompare.*.pas` 文件，但 `02Business/DeepCompare/delphi/Tests/` 目录下实际存在的是：

```
Tests.Touch.DI.pas          Tests.Touch.HotReload.pas    Tests.Touch.JsonUtils.pas
Tests.Touch.LogEnhancer.pas Tests.Touch.Mocks.pas        Tests.Touch.Phase13.pas
Tests.Touch.Plugin.pas      Tests.Touch.ResourceMonitor.pas
Tests.Integration.pas       Tests.Performance.pas
```

是 `02Business/tasks.md` 里"Touch.* 命名空间残留修复（41 个文件）"那次全工作区 `Touch → DeepCompare` 改名事件遗漏的尾巴 —— `.dpr` 的 uses 子句被改了，但 .pas 文件名（与 unit 头）没改。dcc64 解析 `Tests.DeepCompare.DI in 'Tests.DeepCompare.DI.pas'` 时找不到 .pas 直接 fatal。

修复方向（**不在本任务范围**，与本特性无因果）：把这 7 个 `Tests.Touch.*.pas` 文件名 + unit 头同步改成 `Tests.DeepCompare.*`，或者反过来把 `.dpr` 的 uses 改回 `Tests.Touch.*`。

### 类型 C — Pre-existing 单元缺失/孤儿 .dpr（4 处）

#### C.1 `DeepConfig/tests/FinalConfigEditor.dpr` 与 C.2 `DeepConfig/tests/MyConfig.dpr`

```text
DeepConfig\tests\FinalConfigEditor.dpr(34) Fatal: F1026 File not found: 'ConfigTypes.pas'
DeepConfig\tests\MyConfig.dpr(36)         Fatal: F1026 File not found: 'ConfigTypes.pas'
```

两份 .dpr 引用 `ConfigTypes in 'ConfigTypes.pas'` 等单元，但全工作区扫描：

```pwsh
Get-ChildItem -Path . -Recurse -Filter ConfigTypes.pas       # 0 hit
Get-ChildItem -Path . -Recurse -Filter TreeHelper.pas        # 0 hit
Get-ChildItem -Path . -Recurse -Filter ConfigEditorFrame.pas # 0 hit
```

均不存在。对照同目录的 `DeepConfig/DeepConfig.dpr`（主程序，前批次已植入 `DeepBase.AIErrorHandler.Bootstrap`）使用的是 `ViewBuildConfig` / `ConfigIntf` / `JSONHelpers` 等当前存在的单元，并不依赖 `ConfigTypes` —— 说明 `tests/FinalConfigEditor.dpr` 与 `tests/MyConfig.dpr` 是历史重组遗物（孤儿 .dpr）。

#### C.3 `DeepConfig/tests/NewConfigEditor.dpr` 与 C.4 `DeepConfig/tests/SimpleConfigEditor.dpr`

```text
DeepConfig\tests\NewConfigEditor.dpr(14)    Fatal: F1026 File not found: 'ViewMain.pas'
DeepConfig\tests\SimpleConfigEditor.dpr(9)  Fatal: F1026 File not found: 'ViewMain.pas'
```

两份 .dpr 都引用 `ViewMain in 'ViewMain.pas' {frmMain}`。`ViewMain.pas` 在工作区只存在于：

```text
DeepBase\DeepBaseRun\ViewMain.pas        # 不同的 unit
DeepCompare\delphi\DeepCompare\ViewMain.pas  # 不同的 unit
DeepConfig\backup\ViewMain.pas           # 备份目录
```

`02Business/DeepConfig/` 根与 `02Business/DeepConfig/tests/` 都没有 `ViewMain.pas`。同样是孤儿 .dpr。

修复方向（**不在本任务范围**，与本特性无因果）：评估这 4 份编辑器 .dpr 的去留 —— 如果还在维护，则从 `DeepConfig/backup/` 恢复 `ViewMain.pas` / `ConfigTypes.pas` 等并修 unit 引用；否则归档/删除。

### 类型 D — Pre-existing implementation 不一致（1 处）

#### D.1 `DeepConfig/TestConfigs.dpr`

```text
DeepConfig\ErrorLogger.pas(41) Error: E2356 Property accessor must be an instance field or method
DeepConfig\ErrorLogger.pas(41) Error: E2356 Property accessor must be an instance field or method
DeepConfig\ErrorLogger.pas(73) Error: E2009 Incompatible types: 'method pointer and regular procedure'
DeepConfig\FormMain.pas(9) Fatal: F2063 Could not compile used unit 'ErrorLogger.pas'
```

`DeepConfig/ErrorLogger.pas` 第 41 行 `property ShowDialogs: Boolean read FShowDialogs write FShowDialogs;` 期望 instance field，但 `FShowDialogs` 在该类的字段段没有正确声明（疑似 class var 与 instance field 之间被改残）。第 73 行 `Application.OnException := GlobalExceptionHandler;` 把 `procedure GlobalExceptionHandler(Sender; E)` 直接赋给 `TExceptionEvent` 也是历史遗留 —— `Application.OnException` 期望 method pointer（`of object`），但 `GlobalExceptionHandler` 是 unit-level procedure，需要 `procedure of object` 或单独的 method 包装。

是 DeepConfig/ErrorLogger.pas 的早期单例重构事故，与本特性无因果。

修复方向（**不在本任务范围**）：修 `ErrorLogger.pas` 的 `FShowDialogs` 字段可见性 + 把 `GlobalExceptionHandler` 改成 `TErrorLogger` 的 method（或改成 `procedure GlobalExceptionHandler(Sender: TObject; E: Exception); register;` + 用 `procedure of object` wrapper）。

## 与 R9.1 / R9.2 / R9.3 / Property 15 的对应

- **R9.1 +2 / -0**：17 个改动 `.dpr` 均为 1 行 uses + 1 行调用，无任何源代码删除（`getDiagnostics` 全绿 17 / 17；文本扫描 `DeepBase.AIErrorHandler.Bootstrap` 出现次数 = 1、`InstallAIErrorHandlerForTests` 出现次数 = 1 已用 PowerShell 17 文件循环验证）

- **R9.2 不碰 .dproj/.dfm/其它源文件**：本批次未改任何 `.dproj`、`.dfm`，未修改 `DeepBase.AIErrorHandler*.pas` 三件套、未修任何 `.pas`（**本批次未触发任何 pre-existing 顺手修** —— 任务允许的两类（`DeepBase.AutoFix.ErrorRecorder.VCL → DeepBase.AutoFix.VclHook` 与 `IfThen` 缺 `System.StrUtils`）、以及 Rust 风格 `if-then-else` 表达式赋值，都没有在本批次涉及到的 4 个非 DeepBase 项目（DeepCharset / DeepClip / DeepCompare / DeepConfig）的本期编译路径里出现 —— 8 个 pre-existing 错误都是另外四类，不在允许的顺手修范围内）

- **R9.3 幂等**：17 个 `.dpr` 全是首次植入；如果对本批次再跑一次植入流水线，PowerShell 文本扫描会检出 `DeepBase.AIErrorHandler.Bootstrap` 已存在，应自动跳过

- **R7（Test_Program 必须用 ForTests）**：17 个文件全部调用 `InstallAIErrorHandlerForTests`（Bootstrap 内部强制 `bmTest`，覆盖任何 `TAIErrorConfig.SilentMode := False` 的 caller-supplied 配置），编译通过的 9 个文件运行时进入静默模式（无 `MessageDlg`），fatal 走 `ExitCode := 1; Halt(1)`

## 不修清单（pre-existing，与本特性无因果）

按"其它 pre-existing 失败 → 不修，记录跳过"约束，下表 8 处文件的 pre-existing 阻塞**不在本任务修复范围**，建议下一期单独立任务处理：

| # | .dpr | Pre-existing 类型 | 影响范围 | 建议修复期 |
|---|------|-------------------|---------|-----------|
| 1 | `DeepCharset/Tests/SelfTest_Encoding.dpr` | UTF-8 字符串字面量编码事故（5 处） | 仅 `SelfTest_Encoding.dpr` 自身，不影响 `DeepCharset.dpr` 主程序 | DeepCharset 测试稳健化期 |
| 2 | `DeepClip/tests/BehaviorMock/DeepClipBehavior.dpr` | `RegisterGovernance` 3-参重载 vs `RegisterDeepClipGovernance` 0-参签名不匹配 | 仅本测试 .dpr | DeepClip 治理测试期 |
| 3 | `DeepCompare/delphi/Tests/DeepCompareTests.dpr` | `Tests.DeepCompare.* → Tests.Touch.*` 改名遗漏 | 仅本测试 .dpr；7 个 .pas 文件名待统一 | Touch.* 残留清理期（与 `02Business/tasks.md` 既有"Touch.* 残留修复"任务合并） |
| 4 | `DeepConfig/TestConfigs.dpr` | `ErrorLogger.pas` 第 41/73 行 implementation 不一致 | 影响 `TestConfigs.dpr` + 任何 uses `ErrorLogger.pas` 的 .pas | DeepConfig 单例重构修补期 |
| 5 | `DeepConfig/tests/FinalConfigEditor.dpr` | 缺 `ConfigTypes.pas` 等单元（孤儿 .dpr） | 仅本编辑器 .dpr | DeepConfig tests/ 目录梳理期（评估去留） |
| 6 | `DeepConfig/tests/MyConfig.dpr` | 同 #5 | 仅本 .dpr | 同 #5 |
| 7 | `DeepConfig/tests/NewConfigEditor.dpr` | 缺 `ViewMain.pas` | 仅本 .dpr | 同 #5 |
| 8 | `DeepConfig/tests/SimpleConfigEditor.dpr` | 同 #7 | 仅本 .dpr | 同 #5 |

## 结论

Test 组 Batch 1（17 个 `.dpr`）按"植入正确性"维度：**17 / 17 通过**（全部首次植入、严格 +2 / -0、`getDiagnostics` 全绿、`InstallAIErrorHandlerForTests` 调用名正确、模板与 G2..G7 一致只换调用名后缀）。

按"编译干净"维度：**9 / 17 通过**（其余 8 处全部为与本特性无因果的 pre-existing 阻塞，详上"失败聚合"与"不修清单"）。

**Test 组 Batch 1 通过**（"植入正确性"维度）。下一步建议：

1. 推进 Test 组 Batch 2（DeepDev / DeepDevLite / DeepInsight / DeepInput / DeepRenew / DeepShine / DeepSpec / DeepStory / DeepSync 等的测试 .dpr，按 inventory 与 dpr-inventory.md 的剩余项目）
2. 单独立任务处理 8 处 pre-existing 阻塞 —— 建议拆成 5 个小修复期（按上"不修清单"末列），每一期都不依赖本特性的 AIErrorHandler 植入 —— 当那些 .dpr 编译干净时，本期已经植入的 `InstallAIErrorHandlerForTests` 就直接生效
3. 在 inventory `dpr-inventory.md` 的 G16 part / G17 / G18 行追加"批次状态：Test Batch 1 完成"标记，方便后续 G19+ 维护
