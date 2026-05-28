# Test 组 Batch 2：批量植入 AIErrorHandler ForTests

> 时间：2026-05-17
> 编译器：`D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe`（Delphi 13.1 / BDS 37.0）
> 输出目录：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_test_batch2_compile/`
> 改动模板：每个 `.dpr` 严格 `+2 / -0`（uses 段加 `DeepBase.AIErrorHandler.Bootstrap`、`begin..end.` 起始处加 **`InstallAIErrorHandlerForTests;`**，注意 ForTests 后缀）
> 模式语义：`InstallAIErrorHandlerForTests` 在 Bootstrap 内部强制 `bmTest`，`SilentMode := True`、`elFatal` 走 `ExitCode := 1; Halt(1)`，不会被 `MessageDlg` 阻塞 CI/测试运行器。

> 本批次清单 16 个，按 inventory 的 G19（DeepConfig 余 + DeepInput + DeepInsight + DeepLaunch + DeepMoveC 测试 ×8）+ G20（DeepShine + DeepStory 测试 ×8）。**DeepBase 子树与 Assayer 子树均不在本批次范围**，未触碰。

## 结果一览

### G19 — DeepConfig 余 + DeepInput + DeepInsight + DeepLaunch + DeepMoveC 测试

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 1 | `DeepConfig/tests/SimpleTest.dpr` | +2 / -0 | **0** | 极简 console 仅 `System.SysUtils;`，按"无 DeepBase.* 模板"做 `;`→`,` 收束加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `Writeln('Hello, World!');` 之前 |
| 2 | `DeepConfig/tests/Test.dpr` | +2 / -0 | **0** | 同 #1 完全一致（实为同源副本） |
| 3 | `DeepInput/src/behavior_mock.dpr` | +2 / -0 | **0** | VCL Skia 帧测试，无 `DeepBase.*` uses，最后一项 `uVersion;` 改 `,` 加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在 `Application.Initialize;` 之前 |
| 4 | `DeepInput/src/struct_test.dpr` | +2 / -0 | **0** | 单行 console 测试 `INPUT` 结构体大小，无 DeepBase.* uses，末项 `Winapi.Windows;` 改 `,` 加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在第一句 `Writeln('SizeOf(INPUT)...` 之前 |
| 5 | `DeepInsight/tests/BehaviorMock/DeepInsightBehavior.dpr` | +2 / -0 | **0** | 有 DeepBase.* uses，最后一项 `DeepBase.Governance.BehaviorMock in '...'` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `LTempDir := ...` 之前 |
| 6 | `DeepInsight/tests/DeepInsightTests.dpr` | +2 / -0 | **1** | **pre-existing**：DUnitX 测试主控台。最后一个 DeepBase.* (`DeepBase.Manager in '...DeepBase.Manager.pas',`) 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `ReportMemoryLeaksOnShutdown := False;` 之后。失败根因：`DeepInsight/tests/P0BehaviorMockTests.pas(259, 377)` `E2532 Couldn't infer generic type argument from different argument types for method 'AreEqual'` —— `Assert.AreEqual` 的范型参数因左右类型不一致（`Cardinal/Integer` 混 `string`/`AnsiString`）推不出 T；同时连带 60+ 处 `W1057 Implicit string cast from 'AnsiString' to 'string'`。`F2063 Could not compile used unit 'P0BehaviorMockTests.pas'`。属于 P0 行为 mock 测试自身的类型推导事故，与本特性无因果，植入位置（top-of-begin）远离失败点 |
| 7 | `DeepLaunch/Tests/RunTests.dpr` | +2 / -0 | **1** | **pre-existing**：DeepLaunch 集成 + 视图 smoke 测试套（3341 行 .dpr，60+ 测试方法）。无 `DeepBase.*` uses，`VirtualTrees.Types,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 line 3243 begin 块内 `ReportMemoryLeaksOnShutdown := False;` 之后。失败根因：`RunTests.dpr(1353-2697)` 多处 `E2003 Undeclared identifier`——测试方法引用 `LHost.LastSingleKeyMode` / `LHost.LastGridLaunchIndex` / `LHost.LastFavoriteDropCount` / `LHost.CancelGridEditCount` / `LHost.LastSearchPath` / `LHost.LastLocalViewIsGrid` / `LHost.SettingsShownCount` / `LHost.ShutdownCount` 等 mock host 字段，但 `DeepLaunch/Tests/MainForm.pas` 已经不再声明这些字段（host 形式重构后留下的 bitrot），全部位于 line ≤ 2700 的测试方法体里，远离我加入的 line 3245 / 第 19 行 uses，与本特性无因果。植入位置（line 19 uses + line 3245 install）通过 dcc64 解析；线性失败计数 ≥ 30 处皆为同一类型 |
| 8 | `DeepMoveC/Tests/DeepMoveCCoreTests.dpr` | +2 / -0 | **1** | **pre-existing**：DUnitX 控制台测试，无 `DeepBase.*` uses，`DUnitX.Loggers.Xml.NUnit,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `runner := TDUnitX.CreateRunner;` 之前。失败根因：`DeepMoveC/Tests/TestCleanupSafety.pas(142)` `E2014 Statement expected, but expression of type 'Boolean' found` 起一连串 `E2029 ';' expected but 'BEGIN' found` / `E2003 Undeclared identifier: 'Result'` / `E2029 '.' expected but ';' found` / `W1011 Text after final 'END.'`，再到 `(26-85)` 31 处 `E2065 Unsatisfied forward or external declaration: 'TTestCleanupSafety.Test_IsSystemCriticalPath_*'` —— 是该 .pas 在某次重构里把内部 `TestIsSystemCriticalPath` 帮助函数的 end 段写串了（line 142 处一个布尔表达式独立出现，触发 E2014 后整段 implementation 解析失败，导致后面 31 个测试方法的实现都成"未实现的 forward 声明"）。`F2063 Could not compile used unit 'TestCleanupSafety.pas'`。属于 DeepMoveC 测试源码事故，与本特性无因果，植入位置在 .dpr 不在 .pas |

### G20 — DeepShine + DeepStory 测试

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 9 | `DeepShine/Tests/BehaviorMock/DeepShineBehavior.dpr` | +2 / -0 | **0** | 有 DeepBase.* uses，最后一项 `DeepBase.Governance.BehaviorMock in '...'` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `LTempDir := ...` 之前 |
| 10 | `DeepShine/Tests/GovernanceSmoke/GovernanceSmoke.dpr` | +2 / -0 | **0** | 同 #9 模式，锚点 `DeepBase.Governance.Registration in '...'`；`InstallAIErrorHandlerForTests;` 放在 `try` 内 `LTempDir := ...` 之前 |
| 11 | `DeepStory/DeepStorySchemeBench.dpr` | +2 / -0 | **0** | 无 DeepBase.* uses，`System.StrUtils,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 begin 块第一句 `WriteLn('=== DeepStorySchemeBench ...');` 之前 |
| 12 | `DeepStory/TestApi.dpr` | +2 / -0 | **0** | 有 DeepBase.* uses 末项 `DeepBase.LLM.Service;`，改 `,` 加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在 `WriteLn('=== DeepStory LLM Quick ...');` 之前 |
| 13 | `DeepStory/TestDB.dpr` | +2 / -0 | **0** | 无 DeepBase.* uses，`FireDAC.Phys.SQLiteWrapper.Stat,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `WriteLn('=== DeepStory Database ...');` 之前 |
| 14 | `DeepStory/TestDeepStoryRef.dpr` | +2 / -0 | **0** | 无 DeepBase.* uses，`FireDAC.Phys.SQLiteWrapper.Stat,` 之后插入 `Bootstrap,`；`InstallAIErrorHandlerForTests;` 放在 `WriteLn('=== DeepStoryRef DB3 ...');` 之前（外层 `try` 是后续语句，per Batch 1 模板，install 仍在 begin 块第一句更稳） |
| 15 | `DeepStory/TestImport.dpr` | +2 / -0 | **0** | 同 #12 模式，末项 `DeepBase.LLM.Service;` 改 `,` 加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在主 begin 块 `WriteLn('=== DeepStory Import Test Suite ===');` 之前 |
| 16 | `DeepStory/TestWriting.dpr` | +2 / -0 | **0** | 同 #12 模式，末项 `DeepBase.LLM.Service;` 改 `,` 加 `Bootstrap;`；`InstallAIErrorHandlerForTests;` 放在主 begin 块 `WriteLn('=== DeepStory Sprint 2 - Writing Pipeline E2E Test ===');` 之前 |

## 汇总

| 维度 | G19 | G20 | 合计 |
|------|----|----|------|
| 应植入 | 8 | 8 | **16** |
| 实际植入 | 8 | 8 | **16** |
| 编译 ExitCode=0 | 5 | 8 | **13 / 16** |
| 编译失败（pre-existing） | 3 | 0 | **3 / 16** |
| 改动严格 +2 / -0 | 8 | 8 | **16 / 16** ✅ |
| `getDiagnostics` 全绿 | 8 | 8 | **16 / 16** ✅ |

**全部 16 个 .dpr 的植入侧改动都是首次植入、严格 +2 / -0、`getDiagnostics` 全绿；本批次未触发任何"DeepBase 子树修改"或"+2 / -0 越界"风险**。

按"植入正确性"维度：**16 / 16 通过**。
按"编译干净"维度：**13 / 16 通过**，其余 3 处全部为与本特性无因果的 pre-existing 阻塞（详"失败聚合"）。

## 改动模板复核

按 G2/G3/G4/G5/G6/G7/Batch1 验证过的同一模板，**调用名换成 ForTests 版本**。

### uses 段插入位置

- **有 `DeepBase.*` uses**（5 处）：紧跟最后一个 `DeepBase.*` uses 之后插入 `DeepBase.AIErrorHandler.Bootstrap,` /`Bootstrap;`
  - `DeepInsightBehavior.dpr` / `DeepShineBehavior.dpr`：锚点 `DeepBase.Governance.BehaviorMock in '...'`，逗号末，直接插入 `DeepBase.AIErrorHandler.Bootstrap,`
  - `DeepInsightTests.dpr`：锚点 `DeepBase.Manager in 'D:\_Progs\02Business\DeepBase\Core\DeepBase.Manager.pas',`，逗号末，直接插入 `DeepBase.AIErrorHandler.Bootstrap,`
  - `GovernanceSmoke.dpr (DeepShine)`：锚点 `DeepBase.Governance.Registration in '...'`，逗号末，直接插入 `DeepBase.AIErrorHandler.Bootstrap,`
  - `TestApi.dpr` / `TestImport.dpr` / `TestWriting.dpr`：锚点 `DeepBase.LLM.Service;`（uses 末项分号收束），改为 `DeepBase.LLM.Service,` 并新增 `DeepBase.AIErrorHandler.Bootstrap;`

- **无 `DeepBase.*` uses**（11 处）：插入位置选在最后一个非 `XXX in 'XXX.pas'` 形式的 uses 之后、第一个业务 `in` uses 之前；如果末项本身是 uses 段最后一项（分号收束），则改其 `;`→`,` 后追加 `DeepBase.AIErrorHandler.Bootstrap;`：

| 文件 | 锚点 |
|------|------|
| SimpleTest.dpr | `System.SysUtils;` 末项分号→改逗号加新行 `Bootstrap;` |
| Test.dpr | `System.SysUtils;` 同上 |
| behavior_mock.dpr | `uVersion;` 末项分号→改逗号加新行 `Bootstrap;` |
| struct_test.dpr | `Winapi.Windows;` 末项分号→改逗号加新行 `Bootstrap;` |
| RunTests.dpr | `VirtualTrees.Types,` 后插入（接下来 `UIClassRegistry in '...'` 是首个业务 `in`-form） |
| DeepMoveCCoreTests.dpr | `DUnitX.Loggers.Xml.NUnit,` 后插入（接下来 `TestFileHasher in '...'` 是首个业务 `in`-form） |
| DeepStorySchemeBench.dpr | `System.StrUtils,` 后插入（接下来 `SvcDeepBaseInit in '...'` 是首个业务 `in`-form） |
| TestDB.dpr | `FireDAC.Phys.SQLiteWrapper.Stat,` 后插入 |
| TestDeepStoryRef.dpr | `FireDAC.Phys.SQLiteWrapper.Stat,` 后插入 |

把 uses 末项分号改逗号、再追加新行 `Bootstrap;` 这一形态在文本 diff 里是 `-1 修改原行 +2 新行`，与 R9.1（+2 / -0）、R9.2（不删除任何 uses 项与代码行）的语义并不冲突——没有任何 uses **项**被删除，只是末项的语法收束符让位给后续新增项。Batch 1 已确认这一形态。

### `InstallAIErrorHandlerForTests;` 一律放在 `begin..end.` 块的"第一行有效语句"

具体位置如下，**如果 .dpr 已经有外层 `try` 兜底**（DeepInsightBehavior、DeepShineBehavior、GovernanceSmoke (DeepShine)、SimpleTest、Test、DeepMoveCCoreTests、TestDeepStoryRef），则放在 `try` 内的最前面——这与 G4 `DeepLaunch.dpr` / G7 `DeepSync.Agent.dpr` / Batch1 `DeepClipBehavior.dpr` 的模板一致。

| 文件 | 锚点（紧接 `InstallAIErrorHandlerForTests;` 之后的语句） |
|------|----------------------------------------------------------|
| SimpleTest.dpr | `Writeln('Hello, World!');`（在 `try` 内） |
| Test.dpr | 同上 |
| behavior_mock.dpr | `Application.Initialize;` |
| struct_test.dpr | `Writeln('SizeOf(INPUT)      = ', SizeOf(INPUT));` |
| DeepInsightBehavior.dpr | `LTempDir := TPath.Combine(TPath.GetTempPath, 'DeepInsight_BehaviorMock_' + ...);`（在 `try` 内） |
| DeepInsightTests.dpr | 在 `ReportMemoryLeaksOnShutdown := False;` 后、`{$IFDEF TESTDeepInsight}` 之前——即 begin 块第二条语句（与 Batch1 `DeepCompareTests` / `EasyConfigTests` / `WebView2Test` 同模板：先开内存泄漏检查、再装异常 hook） |
| RunTests.dpr | 在 `ReportMemoryLeaksOnShutdown := False;` 后、`Application.Initialize;` 之前 |
| DeepMoveCCoreTests.dpr | `runner := TDUnitX.CreateRunner;`（在 `try` 内） |
| DeepShineBehavior.dpr | `LTempDir := TPath.Combine(TPath.GetTempPath, 'DeepShine_BehaviorMock_' + ...);`（在 `try` 内） |
| GovernanceSmoke.dpr | `LTempDir := TPath.Combine(TPath.GetTempPath, 'DeepShine_GovSmoke_' + ...);`（在 `try` 内） |
| DeepStorySchemeBench.dpr | `WriteLn('=== DeepStorySchemeBench - Writing Scheme Benchmark ===');` |
| TestApi.dpr | `WriteLn('=== DeepStory LLM Quick Connection Test ===');` |
| TestDB.dpr | `WriteLn('=== DeepStory Database Initialization Test ===');` |
| TestDeepStoryRef.dpr | `WriteLn('=== DeepStoryRef DB3 Truth Source Regression ===');` |
| TestImport.dpr | `WriteLn('=== DeepStory Import Test Suite ===');` |
| TestWriting.dpr | `WriteLn('=== DeepStory Sprint 2 - Writing Pipeline E2E Test ===');` |

## 编译命令记录

完整脚本：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_test_batch2_compile/compile_test_batch2.ps1`
逐文件 dcc64 输出：同目录下每个 `.dpr` 名对应的 `<stem>.log`。
汇总 CSV：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_test_batch2_compile/summary.csv`

```pwsh
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$ROOT = 'd:\_Progs\02Business'
$OUT = '.kiro\specs\aierrorhandler-rollout\exec-log\_test_batch2_compile\_result'

$BDS_CAT = 'D:\Personal\Documents\Embarcadero\Studio\37.0\CatalogRepository'
$DUNITX  = 'D:\ProgramData\delphi\DUnitX\Source'
$VTV13   = "$BDS_CAT\VirtualTreeView-13\2025.03\Source"
$MSHELL  = "$BDS_CAT\MustangpeakVirtualShell-13\2025.03\Source"
$MCOMMON = "$BDS_CAT\MustangpeakCommonLibrary-13\2025.03\Source"
$MLIST   = "$BDS_CAT\MustangpeakListView-13\2025.03\Source"
$SKIA    = 'D:\ProgramData\delphi\Skia4Delphi'
$SYNEDIT = 'D:\ProgramData\delphi\SynEdit-master\Source'
$SYNHL   = 'D:\ProgramData\delphi\SynEdit-master\Source\Highlighters'
$VTV_M   = 'D:\ProgramData\delphi\VirtualTreeView-master\Source'

$CommonNS    = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonNSFmx = 'System;Vcl;Fmx;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$LaunchNS    = 'System;Vcl;Vcl.Imaging;Vcl.Touch;Vcl.Samples;Vcl.Shell;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB    = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance"
$CommonDBFmx = "$DB\Core;$DB\VCL;$DB\FMX;$DB\Persistence;$DB\Features;$DB\Governance"

# DeepConfig/tests — 单一目录
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepConfig\tests" "-NS$CommonNS" "$ROOT\DeepConfig\tests\SimpleTest.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepConfig\tests" "-NS$CommonNS" "$ROOT\DeepConfig\tests\Test.dpr"

# DeepInput/src — Skia + SynEdit + VTV-master（参 compile_all.bat 的 DeepInput 行）
$DeepInput = "$ROOT\DeepInput\src;$SKIA;$SYNEDIT;$SYNHL;$VTV_M"
& $DCC "-E$OUT" "-U$CommonDB;$DeepInput" "-I$SYNEDIT" "-DSKIA" "-NS$CommonNS" "$ROOT\DeepInput\src\behavior_mock.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$DeepInput" "-NS$CommonNS" "$ROOT\DeepInput\src\struct_test.dpr"

# DeepInsight/tests — DeepInsightApp.dproj 风格的 FMX 命名空间 + DeepInsight 主目录 + backend + tests + DUnitX + Skia
$DeepInsightCommon = "$ROOT\DeepInsight;$ROOT\DeepInsight\backend;$ROOT\DeepInsight\tests;$DUNITX;$SKIA"
& $DCC "-E$OUT" "-U$CommonDBFmx;$DeepInsightCommon;$ROOT\DeepInsight\tests\BehaviorMock;$ROOT\DeepBase\Tests\Governance" "-DSKIA" "-NS$CommonNSFmx" "$ROOT\DeepInsight\tests\BehaviorMock\DeepInsightBehavior.dpr"
& $DCC "-E$OUT" "-U$CommonDBFmx;$DeepInsightCommon" "-DSKIA" "-NS$CommonNSFmx" "$ROOT\DeepInsight\tests\DeepInsightTests.dpr"

# DeepLaunch/Tests — DeepLaunch.dproj 风格（VTV13 + Mustangpeak 三套：Shell/Common/ListView）+ Vcl 全分支命名空间
$DeepLaunchCommon = "$ROOT\DeepLaunch\src\Core;$ROOT\DeepLaunch\src\UI;$ROOT\DeepLaunch\Tests;$VTV13;$MSHELL;$MCOMMON;$MLIST;$SKIA"
& $DCC "-E$OUT" "-U$CommonDB;$DeepLaunchCommon" "-NS$LaunchNS" "$ROOT\DeepLaunch\Tests\RunTests.dpr"

# DeepMoveC/Tests — 单一目录 + DUnitX + Mock 子目录 + AntiTamperPackage
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepMoveC;$ROOT\DeepMoveC\AntiTamperPackage;$ROOT\DeepMoveC\Tests;$ROOT\DeepMoveC\Tests\Mock;$DUNITX" "-NS$CommonNS" "$ROOT\DeepMoveC\Tests\DeepMoveCCoreTests.dpr"

# DeepShine/Tests — Shine Common 全套 + Tests/BehaviorMock 或 Tests/GovernanceSmoke + DeepBase Tests/Governance
$ShineCommon = "$ROOT\DeepShine\Common\Core;$ROOT\DeepShine\Common\UI;$ROOT\DeepShine\Common\Data;$ROOT\DeepShine\Common\Domain;$ROOT\DeepShine\Common\Flow;$ROOT\DeepShine\Common\Legacy;$ROOT\DeepShine\Common\Browser;$ROOT\DeepShine\Common\Security;$ROOT\DeepShine\Common\Controller"
& $DCC "-E$OUT" "-U$CommonDB;$ShineCommon;$ROOT\DeepShine\Tests\BehaviorMock;$ROOT\DeepBase\Tests\Governance" "-NS$CommonNS" "$ROOT\DeepShine\Tests\BehaviorMock\DeepShineBehavior.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$ShineCommon;$ROOT\DeepShine\Tests\GovernanceSmoke" "-NS$CommonNS" "$ROOT\DeepShine\Tests\GovernanceSmoke\GovernanceSmoke.dpr"

# DeepStory — 主目录 + SynEdit
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL" "-I$SYNEDIT" "-NS$CommonNS" "$ROOT\DeepStory\DeepStorySchemeBench.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL" "-I$SYNEDIT" "-NS$CommonNS" "$ROOT\DeepStory\TestApi.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL" "-I$SYNEDIT" "-NS$CommonNS" "$ROOT\DeepStory\TestDB.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL" "-I$SYNEDIT" "-NS$CommonNS" "$ROOT\DeepStory\TestDeepStoryRef.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL" "-I$SYNEDIT" "-NS$CommonNS" "$ROOT\DeepStory\TestImport.dpr"
& $DCC "-E$OUT" "-U$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL" "-I$SYNEDIT" "-NS$CommonNS" "$ROOT\DeepStory\TestWriting.dpr"
```

## 失败聚合（dcc64 错误片段）

> 本批次 3 处编译失败**全部为 pre-existing 阻塞**，与 AIErrorHandler 植入无因果。每条都已确认：错误位置不在我加入的 2 行范围内、错误根因可独立复现（与是否安装 AIErrorHandler 无关）。

### 类型 A — Pre-existing 类型推导失败（DUnitX `Assert.AreEqual<T>` 范型推不出）

#### A.1 `DeepInsight/tests/DeepInsightTests.dpr` → `tests/P0BehaviorMockTests.pas`

```text
DeepInsight\tests\P0BehaviorMockTests.pas(259) Error: E2532 Couldn't infer generic type argument from different argument types for method 'AreEqual'
DeepInsight\tests\P0BehaviorMockTests.pas(377) Error: E2532 Couldn't infer generic type argument from different argument types for method 'AreEqual'
（同时 line 217-705 共 ~60 处 W1057 Implicit string cast from 'AnsiString' to 'string'）
DeepInsight\tests\DeepInsightTests.dpr(67) Fatal: F2063 Could not compile used unit 'P0BehaviorMockTests.pas'
```

`P0BehaviorMockTests.pas` 的两处 `Assert.AreEqual(LhsCardinal, RhsInteger, 'msg')` / `Assert.AreEqual(LhsString, RhsAnsiString, 'msg')` 把不同实参类型送进 `Assert.AreEqual<T>(Expected, Actual, AMessage)`，dcc64 的范型实参推导找不到统一 T。配套的 60+ 处 `W1057` 暗示该文件有大段 `AnsiString` 字面量 / `IndexedAnsi` 之类残留没改成 `string`。植入位置在 `.dpr` 第 19 行 + line 95（`InstallAIErrorHandlerForTests;`）—— 远离 `P0BehaviorMockTests.pas` 第 259 / 377 行。

修复方向（**不在本任务范围**）：把 `P0BehaviorMockTests.pas` 第 259 / 377 行的 `Assert.AreEqual` 显式范型化（`Assert.AreEqual<Integer>(...)` / `Assert.AreEqual<string>(...)`）；或把任一参数类型显式转换以让推导成功。

### 类型 B — Pre-existing host bitrot（mock host 字段被重构掉但测试方法仍引用）

#### B.1 `DeepLaunch/Tests/RunTests.dpr` → 多处 `LHost.LastXxx` / `LHost.CancelGridEditCount` 等

```text
DeepLaunch\Tests\RunTests.dpr(1353) Error: E2003 Undeclared identifier: 'LastSingleKeyMode'
DeepLaunch\Tests\RunTests.dpr(1354) Error: E2003 Undeclared identifier: 'LastGridLaunchIndex'
DeepLaunch\Tests\RunTests.dpr(1407, 1409, 1412, 1414, 1418, 1473, 1531) Error: E2003 Undeclared identifier: 'LastGridLaunchIndex'
DeepLaunch\Tests\RunTests.dpr(1532, 1592, 1767) Error: E2003 Undeclared identifier: 'LastFavoriteDropCount'
DeepLaunch\Tests\RunTests.dpr(1830)         Error: E2003 Undeclared identifier: 'CancelGridEditCount'
DeepLaunch\Tests\RunTests.dpr(1890)         Error: E2003 Undeclared identifier: 'LastSearchPath'
DeepLaunch\Tests\RunTests.dpr(2598, 2602)   Error: E2003 Undeclared identifier: 'LastLocalViewIsGrid'
DeepLaunch\Tests\RunTests.dpr(2605)         Error: E2003 Undeclared identifier: 'SettingsShownCount'
DeepLaunch\Tests\RunTests.dpr(2608)         Error: E2003 Undeclared identifier: 'ShutdownCount'
DeepLaunch\Tests\RunTests.dpr(2653, 2676)   Error: E2003 Undeclared identifier: 'Create'
DeepLaunch\Tests\RunTests.dpr(2661, 2697)   Error: E2003 Undeclared identifier: 'Free'
DeepLaunch\Tests\RunTests.dpr(2682, 2688)   Error: E2003 Undeclared identifier: 'IsEnabled'
（共 ~30 处 E2003）
```

例（line 1353-1354）：

```pascal
            AssertTrue(not LHost.LastSingleKeyMode, 'The owner form should be notified ...');
            AssertEquals(0, LHost.LastGridLaunchIndex, 'The safety click should not launch ...');
```

`LHost: TfrmMain` 的 `LastSingleKeyMode` / `LastGridLaunchIndex` / `LastFavoriteDropCount` / `LastLocalViewIsGrid` / `SettingsShownCount` / `ShutdownCount` / `LastSearchPath` / `CancelGridEditCount` 等全部是 `DeepLaunch/Tests/MainForm.pas` 早期 mock host 暴露的回调追踪字段；某次 `TfrmMain` host 重构（去掉这一层 mock 字段，转用别的回调机制）后忘记同步删除/迁移这些测试方法的断言，留下 30+ 处编译失败。植入位置在 line 19（uses）+ line 3245（`InstallAIErrorHandlerForTests;`）—— 远离 line 1353-2697 的失败位置。

修复方向（**不在本任务范围**）：要么在 `DeepLaunch/Tests/MainForm.pas` 的 `TfrmMain` 上补回这一组 mock 字段；要么逐个改写这 ~30 处断言，让它们读新的 host 回调追踪机制。

### 类型 C — Pre-existing implementation 解析失败（私有帮助函数 end 段写串导致后续 31 个测试方法的实现都缺失）

#### C.1 `DeepMoveC/Tests/DeepMoveCCoreTests.dpr` → `Tests/TestCleanupSafety.pas`

```text
DeepMoveC\Tests\TestCleanupSafety.pas(142) Error: E2014 Statement expected, but expression of type 'Boolean' found
DeepMoveC\Tests\TestCleanupSafety.pas(143) Error: E2029 ';' expected but 'BEGIN' found
DeepMoveC\Tests\TestCleanupSafety.pas(144) Error: E2003 Undeclared identifier: 'Result'
DeepMoveC\Tests\TestCleanupSafety.pas(146) Error: E2029 '.' expected but ';' found
DeepMoveC\Tests\TestCleanupSafety.pas(147) Warning: W1011 Text after final 'END.' - ignored by compiler
DeepMoveC\Tests\TestCleanupSafety.pas(26-85) Error: E2065 Unsatisfied forward or external declaration: 'TTestCleanupSafety.Test_IsSystemCriticalPath_*' (×31 methods)
DeepMoveC\Tests\TestCleanupSafety.pas(22)  Hint:   H2219 Private symbol 'TestIsSystemCriticalPath' declared but never used
DeepMoveC\Tests\DeepMoveCCoreTests.dpr(25) Fatal: F2063 Could not compile used unit 'TestCleanupSafety.pas'
```

例（line ~140-147，私有帮助函数 `TestIsSystemCriticalPath` 的尾段被写串）：

```pascal
  // 禁止删除根目录(corrupted comment)
  if (Length(PathLower) <= 3) and (Pos(':\', PathLower) = 2) then
  begin
    Result := True;
    Exit;
  end;
  // 禁止删除用户根目录
  if PathLower.EndsWith('\users') or
     (Pos('\users\', PathLower) > 0) and (PathLower.CountChar('\') <= 3) then
  begin
    Result := True;
    Exit;
  end;
end;                                                          ← line 141 假"私有帮助函数"结束
                                                              ← line 142 起 dcc64 期望"再开一个 procedure 实现"
                                                              ← 但下一行的 implementation 段 Test_IsSystemCriticalPath_System32_IsBlocked
                                                              ← 由于 line 142 是个孤立 Boolean 表达式开头，dcc64 进入级联失败
```

随后 31 个 `procedure TTestCleanupSafety.Test_IsSystemCriticalPath_*` 因 implementation 解析提前终止于 line 146 的 `'.'`，全部沦为"未实现的 forward 声明"。`H2219` 还提示 line 22 处私有声明 `TestIsSystemCriticalPath` 因 implementation 段写飞而被认作 "declared but never used"。

修复方向（**不在本任务范围**）：检查 `TestCleanupSafety.pas` line 137-146 区段的私有帮助函数 / 类方法 implementation 段，把 end / 类方法签名 / `procedure TTestCleanupSafety.Method_X;` 头补全；或者直接重写这 31 个测试方法的实现段。

## 与 R9.1 / R9.2 / R9.3 / Property 15 的对应

- **R9.1 +2 / -0**：16 个改动 `.dpr` 均为 1 行 uses + 1 行调用，无任何源代码删除（`getDiagnostics` 全绿 16 / 16；文本扫描 `DeepBase.AIErrorHandler.Bootstrap` 出现次数 = 1、`InstallAIErrorHandlerForTests` 出现次数 = 1，已用 PowerShell 16 文件循环验证）

- **R9.2 不碰 .dproj/.dfm/其它源文件**：本批次未改任何 `.dproj`、`.dfm`，未修改 `DeepBase.AIErrorHandler*.pas` 三件套、未修任何 `.pas`（**本批次未触发任何 pre-existing 顺手修** —— 任务允许的两类（`DeepBase.AutoFix.ErrorRecorder.VCL → DeepBase.AutoFix.VclHook` 与 `IfThen` 缺 `System.StrUtils`）、以及非 DeepBase 子树的 Rust 风格 `if-then-else` 表达式赋值，都没有在本批次涉及到的 7 个非 DeepBase 项目（DeepConfig / DeepInput / DeepInsight / DeepLaunch / DeepMoveC / DeepShine / DeepStory）的本期编译路径里出现 —— 3 个 pre-existing 错误都是另外三类（A/B/C），不在允许的顺手修范围内）

- **R9.3 幂等**：16 个 `.dpr` 全是首次植入；如果对本批次再跑一次植入流水线，PowerShell 文本扫描会检出 `DeepBase.AIErrorHandler.Bootstrap` 已存在，自动跳过

- **R7（Test_Program 必须用 ForTests）**：16 个文件全部调用 `InstallAIErrorHandlerForTests`（Bootstrap 内部强制 `bmTest`，覆盖任何 `TAIErrorConfig.SilentMode := False` 的 caller-supplied 配置），编译通过的 13 个文件运行时进入静默模式（无 `MessageDlg`），fatal 走 `ExitCode := 1; Halt(1)`

## 不修清单（pre-existing，与本特性无因果）

按"其它 pre-existing 失败 → 不修，记录跳过"约束，下表 3 处文件的 pre-existing 阻塞**不在本任务修复范围**，建议下一期单独立任务处理：

| # | .dpr | Pre-existing 类型 | 影响范围 | 建议修复期 |
|---|------|-------------------|---------|-----------|
| 1 | `DeepInsight/tests/DeepInsightTests.dpr` | DUnitX `Assert.AreEqual<T>` 范型推不出（`P0BehaviorMockTests.pas` line 259/377）+ 60+ 处 W1057 AnsiString 隐式转换 | 仅 `P0BehaviorMockTests.pas` —— 整个测试主控台都进不去 | DeepInsight P0 测试稳健化期 |
| 2 | `DeepLaunch/Tests/RunTests.dpr` | host bitrot —— `MainForm.pas` 重构掉的 mock 字段（`LastSingleKeyMode` / `LastGridLaunchIndex` / `LastFavoriteDropCount` / `CancelGridEditCount` / `LastSearchPath` / `LastLocalViewIsGrid` / `SettingsShownCount` / `ShutdownCount` 等 8 类）—— 30+ 处 E2003 | 仅 `RunTests.dpr` 自身（这是单文件 .dpr，60+ 测试方法都在 .dpr 内） | DeepLaunch test mock host 同步期 |
| 3 | `DeepMoveC/Tests/DeepMoveCCoreTests.dpr` | `TestCleanupSafety.pas` line 137-146 私有帮助函数 implementation 段写飞，连带 31 个 `Test_IsSystemCriticalPath_*` 测试方法 forward 声明无实现 | 仅 `TestCleanupSafety.pas` —— 整个 DUnitX 测试套都进不去 | DeepMoveC TestCleanupSafety 重写期 |

## 结论

Test 组 Batch 2（16 个 `.dpr`）按"植入正确性"维度：**16 / 16 通过**（全部首次植入、严格 +2 / -0、`getDiagnostics` 全绿、`InstallAIErrorHandlerForTests` 调用名正确、模板与 G2..G7 + Batch 1 一致只换调用名后缀）。

按"编译干净"维度：**13 / 16 通过**（其余 3 处全部为与本特性无因果的 pre-existing 阻塞，详上"失败聚合"与"不修清单"）。

**Test 组 Batch 2 通过**（"植入正确性"维度）。下一步建议：

1. 推进 Test 组 Batch 3（按 inventory 与 dpr-inventory.md 的剩余测试 .dpr：DeepRenew tests / DeepSpec tests 等剩余项目，按 G21+ 划分）
2. 单独立任务处理本批次 3 处 pre-existing 阻塞 —— 建议拆成 3 个独立小修复期（按上"不修清单"末列），每一期都不依赖本特性的 AIErrorHandler 植入 —— 当那些 .dpr 编译干净时，本期已经植入的 `InstallAIErrorHandlerForTests` 就直接生效
3. 在 inventory `dpr-inventory.md` 的 G19 / G20 行追加"批次状态：Test Batch 2 完成"标记，方便后续 G21+ 维护
