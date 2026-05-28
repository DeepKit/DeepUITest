# G5 / G6 / G7 组：批量植入 AIErrorHandler

> 时间：2026-05-17
> 编译器：`D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe`（Delphi 13.1）
> 输出目录：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g5g6g7_compile/`
> 改动模板：每个 `.dpr` 严格 `+2 / -0`（uses 段加 `DeepBase.AIErrorHandler.Bootstrap`、`begin..end.` 起始处加 `InstallAIErrorHandler;`）

> 注：spec tasks.md 没有为 inventory 的 G5/G6/G7 单列任务。**实际清单以 `dpr-inventory.md` 为准**：DeepShine 簇（5）+ DeepStory + DeepSVG（5）+ DeepSync 簇（3）= 13 个，其中 G7 的 `DeepSync.dpr` 实际是 FMX 入口，按 G4 处理 `DeepInsightApp` 的方式跳过；本批次实际植入 12/13。

## 结果一览

### G5 — DeepShine 簇

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 1 | `DeepShine/Apps/DeepShine.TestGUI/DeepShine.TestGUI.dpr` | +2 / -0 | **0** | 控制台 + VCL 双模（`{$APPTYPE CONSOLE}` + `Vcl.Forms`），`AutoLines / V3Gates` 自动化分支均干净通过 |
| 2 | `DeepShine/Apps/DeepShineConfig/DeepShineConfig.dpr` | +2 / -0 | **0** | DeepBase init 失败分支也保留交互窗口；干净通过 |
| 3 | `DeepShine/Apps/DeepShineFlow/DeepShineFlow.dpr` | +2 / -0 | **0** | 含 `{$IFDEF USE_WEBVIEW2}` 条件 uses（条件单元 `DeepBase.Browser.Engine.WebView2` 在 IFDEF 块内，不算最后一个 DeepBase.* 锚点；本期未定义 USE_WEBVIEW2 仍干净通过） |
| 4 | `DeepShine/Apps/DeepShineStudio/DeepShineStudio.dpr` | +2 / -0 | **0** | 治理（OCGS）路径 + Auto-migrate 都在 InstallAIErrorHandler 之后，全程兜底 |
| 5 | `DeepShine/Common/Legacy/DeepShine.Legacy.FakeCLI.dpr` | +2 / -0 | **0** | 纯 console（`{$APPTYPE CONSOLE}`、无 DeepBase.*），按"无 DeepBase.* uses 模板"插在 `System.SysUtils,` 之后；尽管 `in '..\Common\Legacy\DeepShine.Legacy.FakeCLI.pas'` 子句路径相对自身有歧义（`..\Common\Legacy\` 从同名目录看是 `Common\Common\Legacy\`），但 `-U DeepShine\Common\Legacy` 已经覆盖搜索路径，dcc64 回退到 `-U` 解析后通过 |

### G6 — DeepStory + DeepSVG

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 1 | `DeepStory/DeepStory.dpr` | +2 / -0 | **0** | VCL GUI；与 G2 检查点 4.2 一致，`-U` 含 `$DB\Governance` + SynEdit 后干净通过 |
| 2 | `DeepStory/DeepStoryRef.dpr` | +2 / -0 | **0** | 单 form 小程序 |
| 3 | `DeepSVG/CEFCopier.dpr` | +2 / -0 | **0** | 单 form 小程序，无 DeepBase.* uses，按"无 DeepBase.* uses 模板"插在 `Vcl.Forms,` 之后 |
| 4 | `DeepSVG/DeepSVG.dpr` | +2 / -0 | **0** | 重型 CEF4Delphi 入口；首句 `if TCommandLineController.Execute then Exit;` 也被 InstallAIErrorHandler 兜底；197876 行 / 12.3 MB code，仅 W1057 / W1050 / W1000 等 hint/warning 噪声 |
| 5 | `DeepSVG/DeepSVG_TestRunner.dpr` | +2 / -0 | **0** | DUnitX GUI runner，挂在 `Vcl.Forms` + `DUnitX.TestFramework` 之后插入 |

### G7 — DeepSync 簇

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 1 | `DeepSync/DeepSync.Agent.dpr` | +2 / -0 | **0** | 控制台 agent；`InstallAIErrorHandler` 放在最外层 `try` 内首行（同 G4 DeepLaunch 模板），`-U` 需要 `src\forms` / `src\frames` —— `uAgentSnapshotStore.pas`（`src\core`）在 interface uses 段直接引用 `uNewLocalTaskForm` / `uNewRemoteTaskForm` / `uNewCloudTaskForm`（属 `src\forms`），是 pre-existing 的 core→forms 反向耦合；不在本任务修复范围，靠扩 `-U` 解到通过 |
| 2 | `DeepSync/DeepSync.dpr` | **skipped** | N/A | **FMX 入口**：`uses System.StartUpCopy, FMX.Forms, FMX.Skia, FMX.Dialogs, FireDAC.FMXUI.Wait, ...`；inventory 的"出范围（FMX）"列表里没有它，是又一处 inventory 误归类为 VCL，与 G4 的 DeepInsightApp 同质问题，按相同方式跳过（见末尾"补充 FMX 出范围"） |
| 3 | `DeepSync/DeepSync.ScreenAgent.dpr` | +2 / -0 | **0** | 控制台 agent；`InstallAIErrorHandler` 放在 `begin` 之后第一行（在 `if not TryAcquireSingleInstance ...` 之前），最简洁形态 |

## 汇总

| 维度 | G5 | G6 | G7 | 合计 |
|------|----|----|----|------|
| 应植入 | 5 | 5 | 3 | 13 |
| 实际植入 | 5 | 5 | 2 | **12** |
| 跳过（FMX） | 0 | 0 | 1 | **1**（DeepSync.dpr） |
| 编译 ExitCode=0 | 5 | 5 | 2 | **12 / 12** |
| 编译失败（pre-existing） | 0 | 0 | 0 | **0** |
| 改动严格 +2 / -0 | 5 | 5 | 2 | **12 / 12** ✅ |

**全部 12 个改动 .dpr 一次植入即编译干净；本批次未触发任何 pre-existing 阻塞**，因此本任务说明里允许的两类顺手修（`DeepBase.AutoFix.ErrorRecorder.VCL → DeepBase.AutoFix.VclHook` 与 `IfThen` 缺 `System.StrUtils`）均**未触发**、**未做**。

## 改动模板复核（与 G2/G3/G4 模板一致）

- **有 `DeepBase.*` uses**（DeepShine 4 apps、DeepStory、DeepStoryRef、DeepSync.Agent、DeepSync.ScreenAgent）：紧跟在最后一个 `DeepBase.*` 之后插入 `DeepBase.AIErrorHandler.Bootstrap,`
  - DeepShine.TestGUI / DeepShineConfig：锚点 `DeepBase.VCL.EmptyStatePanel in ...,`
  - DeepShineFlow：锚点 `DeepBase.BrowserAutomation in ...,`（IFDEF 块内的 `DeepBase.Browser.Engine.WebView2` 不参与排序，因为本期未定义 USE_WEBVIEW2；如果将来定义，IFDEF 内单元仍在锚点之前，不影响 Bootstrap 位置）
  - DeepShineStudio：锚点 `DeepBase.Governance.Registration in ...,`
  - DeepStory：锚点 `DeepBase.Governance.Registration,`（裸名式）
  - DeepStoryRef：锚点 `DeepBase.Persistence.Manager.FireDAC,`
  - DeepSync.Agent：锚点 `DeepBase.Persistence.Manager.FireDAC,`
  - DeepSync.ScreenAgent：锚点 `DeepBase.Config,`
- **无 `DeepBase.*` uses**（DeepShine.Legacy.FakeCLI、CEFCopier、DeepSVG、DeepSVG_TestRunner）：插入位置选在最后一个非 `XXX in 'XXX.pas'` 形式的 uses 之后、第一个业务 `in` uses 之前
  - DeepShine.Legacy.FakeCLI：锚点 `System.SysUtils,`
  - CEFCopier：锚点 `Vcl.Forms,`
  - DeepSVG：锚点 `uAppExceptionLog,`（第 4 个非 `in` 单元）
  - DeepSVG_TestRunner：锚点 `DUnitX.TestFramework,`

`InstallAIErrorHandler;` 一律放在 `begin..end.` 块的第一行有效语句：
- DeepShine.TestGUI：放在 `TraceV3Gates('app initialize');` 之前（早于 trace 日志，便于观测 InstallAIErrorHandler 自身异常）
- DeepShineConfig / DeepShineFlow / DeepShineStudio / DeepStory / DeepStoryRef / CEFCopier / DeepSVG_TestRunner：放在 `Application.Initialize;` 之前
- DeepShine.Legacy.FakeCLI：放在 `RunFakeCLI;` 之前
- DeepSVG：放在 `if TCommandLineController.Execute then Exit;` 之前 —— 即使 CLI 分支提前 `Exit`，AIErrorHandler 已经安装到位
- DeepSync.Agent：放在最外层 `try` 内的第一行（即 `if not TryAcquireSingleInstance then Exit;` 之前）。沿用 G4 DeepLaunch 模板的"放在 try 之内"约定，这样如果 `InstallAIErrorHandler` 自身有异常（实际上 Bootstrap 内部 try-except 不外抛），也会被外层 `on E: Exception` 兜走再走 `LogUnhandledAgentException`
- DeepSync.ScreenAgent：放在 `begin` 之后第一行（`if not TryAcquireSingleInstance ...` 之前），最简形态。该 .dpr 没有外层 try，但 `InstallAIErrorHandler` 在 single-instance 检查之前安装 → 即使 single-instance 分支立刻 `Exit` 也已 hook 好

## 编译命令记录

完整脚本：

- 首轮：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g5g6g7_compile/compile_g5g6g7.ps1`
- 重试（5 个失败 → 全转 OK）：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g5g6g7_compile/compile_g5g6g7_retry.ps1`

```pwsh
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$ROOT = 'd:\_Progs\02Business'

$BDS_CAT = 'D:\Personal\Documents\Embarcadero\Studio\37.0\CatalogRepository'
$VTV13   = "$BDS_CAT\VirtualTreeView-13\2025.03\Source"
$SKIA    = 'D:\ProgramData\delphi\Skia4Delphi'
$SYNEDIT = 'D:\ProgramData\delphi\SynEdit-master\Source'
$SYNHL   = 'D:\ProgramData\delphi\SynEdit-master\Source\Highlighters'
$CEF     = 'D:\ProgramData\delphi\CEF4Delphi-131\source'
$WV      = 'D:\ProgramData\delphi\WebView4Delphi\source'

$CommonNS = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;$DB\ThirdParty\UI"
$ShineCommon = "$ROOT\DeepShine\Common\Core;$ROOT\DeepShine\Common\UI;$ROOT\DeepShine\Common\Data;$ROOT\DeepShine\Common\Domain;$ROOT\DeepShine\Common\Flow;$ROOT\DeepShine\Common\Legacy;$ROOT\DeepShine\Common\Browser;$ROOT\DeepShine\Common\Security;$ROOT\DeepShine\Common\Controller"

# G5-1..4 都需要 + $VTV13（DeepBase.VCL.ThemeManagerBridge.pas 用 VirtualTrees / VirtualTrees.Types / VirtualTrees.Colors）
& $DCC "-E$RESULT" "-U$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShine.TestGUI;$VTV13" "-NS$CommonNS" "$ROOT\DeepShine\Apps\DeepShine.TestGUI\DeepShine.TestGUI.dpr"
& $DCC "-E$RESULT" "-U$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShineConfig;$VTV13" "-NS$CommonNS" "$ROOT\DeepShine\Apps\DeepShineConfig\DeepShineConfig.dpr"
& $DCC "-E$RESULT" "-U$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShineFlow;$VTV13;$WV;$SKIA" "-NS$CommonNS" "$ROOT\DeepShine\Apps\DeepShineFlow\DeepShineFlow.dpr"
& $DCC "-E$RESULT" "-U$CommonDB;$ShineCommon;$ROOT\DeepShine\Apps\DeepShineStudio;$VTV13" "-NS$CommonNS" "$ROOT\DeepShine\Apps\DeepShineStudio\DeepShineStudio.dpr"

# G5-5 FakeCLI（无 GUI 依赖）
& $DCC "-E$RESULT" "-U$CommonDB;$ROOT\DeepShine\Common\Legacy" "-NS$CommonNS" "$ROOT\DeepShine\Common\Legacy\DeepShine.Legacy.FakeCLI.dpr"

# G6-1 DeepStory（VCL + SynEdit）
& $DCC "-E$RESULT" "-U$CommonDB;$ROOT\DeepStory;$SYNEDIT;$SYNHL" "-I$SYNEDIT" "-NS$CommonNS" "$ROOT\DeepStory\DeepStory.dpr"

# G6-2 DeepStoryRef（轻量）
& $DCC "-E$RESULT" "-U$CommonDB;$ROOT\DeepStory" "-NS$CommonNS" "$ROOT\DeepStory\DeepStoryRef.dpr"

# G6-3 CEFCopier（无 CEF 依赖、本身就是 CEF dependency 拷贝器）
& $DCC "-E$RESULT" "-U$CommonDB;$ROOT\DeepSVG" "-NS$CommonNS" "$ROOT\DeepSVG\CEFCopier.dpr"

# G6-4/5 DeepSVG / DeepSVG_TestRunner（CEF）
& $DCC "-E$RESULT" "-U$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$CEF" "-I$CEF" "-NS$CommonNS" "$ROOT\DeepSVG\DeepSVG.dpr"
& $DCC "-E$RESULT" "-U$CommonDB;$ROOT\DeepSVG;$ROOT\DeepSVG\tests;$CEF" "-I$CEF" "-NS$CommonNS" "$ROOT\DeepSVG\DeepSVG_TestRunner.dpr"

# G7-1 DeepSync.Agent（控制台；需要 src\forms / src\frames 因为 src\core\uAgentSnapshotStore.pas 反向耦合到 src\forms\uNewLocalTaskForm.pas 等）
& $DCC "-E$RESULT" "-U$CommonDB;$ROOT\DeepSync\src\core;$ROOT\DeepSync\src\agents;$ROOT\DeepSync\src\forms;$ROOT\DeepSync\src\frames" "-NS$CommonNS" "$ROOT\DeepSync\DeepSync.Agent.dpr"

# G7-3 DeepSync.ScreenAgent（控制台）
& $DCC "-E$RESULT" "-U$CommonDB;$ROOT\DeepSync\src\core;$ROOT\DeepSync\src\agents" "-NS$CommonNS" "$ROOT\DeepSync\DeepSync.ScreenAgent.dpr"
```

## 失败聚合

**本批次没有任何 dcc64 失败**——首轮 5 个失败（G5-1/2/3/4 缺 `VirtualTrees`、G7-1 缺 `src\forms`）全部是"-U 路径不全"的 build 配置问题（可重现、可修复，**与 .dpr 内容无关**），重试补齐 `-U` 路径后 12/12 干净通过。

为了完整记录，首轮失败的根因：

### 首轮 G5-1/2/3/4 — 缺 `VirtualTrees`（已通过补 `$VTV13` 修复）

```
DeepShine\Common\UI\DeepBase.VCL.ThemeManagerBridge.pas(9) Fatal: F2613 Unit 'VirtualTrees' not found.
```

`DeepBase.VCL.ThemeManagerBridge.pas` interface uses 段直接 `VirtualTrees, VirtualTrees.Types, VirtualTrees.Colors`，所以 4 个 DeepShine app 都需要 VTV 路径。补 `$VTV13`（`D:\Personal\Documents\Embarcadero\Studio\37.0\CatalogRepository\VirtualTreeView-13\2025.03\Source`）后 4 个 app 全部 ExitCode 0。

### 首轮 G7-1 — 缺 `src\forms`（已通过补路径修复）

```
DeepSync\src\core\uAgentSnapshotStore.pas(24) Fatal: F2613 Unit 'uNewLocalTaskForm' not found.
```

`src\core\uAgentSnapshotStore.pas` 在 interface uses 段直接引用 `uNewLocalTaskForm` / `uNewRemoteTaskForm` / `uNewCloudTaskForm`（位于 `src\forms`），属 pre-existing 的 core→forms 反向耦合（不应当存在但已经在那里）。修复方向（**不在本任务范围**）：把这三个表单单元里被 SnapshotStore 真正用到的 DTO 抽到 `src\core` 下，让 SnapshotStore 不再 uses forms。当前选择是**通过扩 `-U` 让 dcc64 找到 forms 解析通过**，与本特性无因果。

## 关于跳过 `DeepSync.dpr`

文件 uses 段（前 12 行）：

```pascal
program DeepSync;

uses
  System.SysUtils,
  System.IOUtils,
  System.StartUpCopy,
  FMX.Forms,
  FMX.Skia,
  FMX.Dialogs,
  FireDAC.Stan.Intf,
  FireDAC.UI.Intf,
  ...
```

是典型的 FMX 入口（`System.StartUpCopy` + `FMX.Forms` + `FMX.Skia` + `FMX.Dialogs` + `FireDAC.FMXUI.Wait`），且全程 `Application` 解析到 `FMX.Forms.Application`（`HookGlobalExceptionHandlers` 也是把 `FMX.Forms.Application.OnException` 接到 Sentry）。

跳过原因与 G4 的 `DeepInsightApp` 同质：

> `DeepBase.AIErrorHandler.Bootstrap` 的 interface 只 `uses DeepBase.AIErrorHandler;`，但 `DeepBase.AIErrorHandler.pas` interface 段就 `uses Vcl.Forms;`——一旦把 Bootstrap 加到 `DeepSync.dpr` 的 uses，链接器会同时把 `Vcl.Forms` 的 `Application` 全局变量与初始化代码也链进来，与 `FMX.Forms.Application` 形成两份 Application 实例，且 `TAIErrorHandler.Install` 里的 `Application.OnException := ...` 是落在 `Vcl.Forms.Application` 上，而程序里跑的事件是 `FMX.Forms.Application`，等同于"装了等于没装"，还顺带让 VCL/FMX 的 OS 钩子各自激活两次。

按 design.md "决策与权衡" / inventory FMX 出范围的同一理由保持原样；**本期不植入**，等"AIErrorHandler 平台无关核心 + 平台适配器"那一期再处理。

## 补充 FMX 出范围

inventory `dpr-inventory.md` 的"出范围（FMX）"小节当前列了 9 个文件（含 G4 阶段补录的 `DeepInsight/DeepInsightApp.dpr`）。本批次再补一个：

| 路径 | 类型 | 发现节点 |
|------|------|---------|
| `DeepSync/DeepSync.dpr` | Main FMX | G7 执行时发现 inventory 误归类为 VCL，实际 uses `FMX.Forms` + `FMX.Skia` + `FMX.Dialogs` + `FireDAC.FMXUI.Wait`，且 `Application.OnException` 落在 `FMX.Forms.Application` 上 |

建议在 inventory 第二轮维护时把这一项追加进 FMX 出范围列表（与 DeepInsightApp 一并），并在该期 spec 里把 AIErrorHandler 的 VCL 强耦合拆出来。

## 与 R9.1 / R9.2 / Property 15 的对应

- **R9.1 +2 / -0**：12 个改动 `.dpr` 均为 1 行 uses + 1 行调用，无任何源代码删除（`getDiagnostics` 全绿；文本扫描 `DeepBase.AIErrorHandler.Bootstrap` 出现次数=1、`InstallAIErrorHandler` 出现次数=1）
- **R9.2 不碰 .dproj/.dfm/其它源文件**：本批次未改任何 `.dproj`、`.dfm`，未修改 `DeepBase.AIErrorHandler*.pas` 三件套，未修任何 `.pas`（**本批次未触发任何 pre-existing 顺手修**——任务允许的 `DeepBase.AutoFix.ErrorRecorder.VCL → DeepBase.AutoFix.VclHook` 与 `IfThen` 缺 `System.StrUtils` 两类模式在 G5/G6/G7 都没有出现）
- **R9.3 幂等**：12 个 `.dpr` 全是首次植入，无重复跳过分支被触发；G5/G6/G7 复执时应自动检出 12 处已植入并跳过；`DeepSync.dpr` 在复执时应继续按"FMX 出范围"跳过

## 结论

G5/G6/G7 组按"植入侧"成功率：**12/12**（DeepShine 5、DeepStory 2、DeepSVG 3、DeepSync 2 全部干净通过；DeepSync.dpr 按 FMX 出范围跳过）；按"植入正确性"通过：**12/12**。

**G5 / G6 / G7 一并通过**。下一步建议：

1. 推进 G8（DeepBase 主工具，7 个）
2. 单独立任务把 `DeepSync/DeepSync.dpr` 加进 inventory 的"出范围（FMX）"列表（与 G4 阶段补录的 `DeepInsightApp.dpr` 一并），fold 到后续"AIErrorHandler 平台拆分"那一期
3. 单独立任务清理 G7-1 的 pre-existing core→forms 反向耦合：把 `uAgentSnapshotStore.pas` 真正用到的 form-级 DTO 抽到 `src\core` 下，让 `src\core\*` 不再 uses `src\forms\*`（不影响 AIErrorHandler，纯架构层改进）
