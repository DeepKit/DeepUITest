# G4 组：批量植入 AIErrorHandler

> 时间：2026-05-17
> 编译器：`D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe`（Delphi 13.1）
> 输出目录：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g4_compile/`
> 改动模板：每个 `.dpr` 严格 `+2 / -0`（uses 段加 `DeepBase.AIErrorHandler.Bootstrap`、`begin..end.` 起始处加 `InstallAIErrorHandler;`）

> 注：spec tasks.md 里的 task 9 标题写的是 "DeepCompare 系列 / DeepInput 系列 / Assayer / AssayerProxy"——那是设计阶段占位文字。**实际清单以 inventory `dpr-inventory.md` 的 G4 为准**：DeepInsight + DeepLaunch + DeepMoveC + DeepRenew，6 个文件。

## 结果一览

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 1 | `DeepInsight/DeepInsightApp.dpr` | **skipped** | N/A | **FMX**（`uses FMX.Forms, FMX.Skia, FMX.Dialogs, FireDAC.FMXUI.Wait`），inventory 在表中误标为 VCL，但未列入"出范围 FMX 列表"。植入 `DeepBase.AIErrorHandler.Bootstrap` 会通过 `DeepBase.AIErrorHandler` 间接拉入 `Vcl.Forms`，与 `FMX.Forms` 形成 `Application` / `TForm` 等同名符号冲突，违反"一个 .dpr 同一时间只链 VCL 或只链 FMX"。按 design.md "决策与权衡" / inventory FMX 出范围说明保持原样；待"AIErrorHandler 平台无关核心 + 平台适配器"那一期再处理 |
| 2 | `DeepLaunch/ClipDemo/ClipVault.dpr` | +2 / -0 | **1** | **pre-existing**：`Error: E1026 File not found: 'DeepClip.res'`。`.dpr` 头部仍是 `program DeepClip;`，目录里缺 `DeepClip.res`（只有 `02Business/DeepClip/DeepClip.res` 是 sibling 项目用的）；`ClipVault.dproj` 的 `<MainSource>` 也仍指 `DeepClip.dpr`。这是历史上一次"DeepClip → ClipVault 改名"留下的尾巴，与本特性无关 |
| 3 | `DeepLaunch/DeepLaunch.dpr` | +2 / -0 | **1** | **pre-existing**：`DeepLaunch\src\UI\FrameFileExplorer.pas(20) Fatal: F2613 Unit 'EasyListview' not found.`。EasyListview 是 Mustangpeak 的旧组件，这台机器的 `BDSCatalogRepository` 里 `MustangpeakListView-13/2025.03/` 是空目录，`D:\ProgramData\delphi` 也没有，整个工作区找不到 `EasyListview.pas`。是环境侧依赖缺失，与本特性无关 |
| 4 | `DeepMoveC/C盘超级瘦身.dpr` | +2 / -0 | **0** | 26267 行 / 10.4 MB code，仅 W1057 / W1036 / H2077 等 hint/warning 噪声。**注**：PowerShell `&` 调用 dcc64 时直接传中文文件名会被错误转码（`C鐩樿秴绾х槮 韬?dpr`），首轮 `F1026 File not found`。改用"在同目录复制一份 `_DeepMoveC_g4.dpr` 临时别名→编译→删别名"的方式绕过命令行编码问题；原始中文文件名文件不动，植入也是直接对原文件做 `+2 / -0` |
| 5 | `DeepRenew/DeepRenew.dpr` | +2 / -0 | **1** | **pre-existing**：`DeepRenew\ConfigDB.pas(35..53)` 一连串 `E2029` / `E2063`。根因是 `ConfigDB.pas` 第 33 行的中文行内注释 `// 解析器配置` 在某次编辑时丢了行末换行符并损坏了一个字节（`E7 BD AE`→`E7 BD 3F`，"置"被截成 `?`），导致下一行 `TParserConfig = record` 整段被吃进单行注释，从而 `record` 的字段语法在编译器看来变成了"在类型别名位置出现冒号"。与本特性无关 |
| 6 | `DeepRenew/DeepRenewAdmin.dpr` | +2 / -0 | **1** | **pre-existing**：与 #5 同源——经 `uDM.pas` 共用 `ConfigDB.pas`。植入侧 `+2 / -0` 通过；编译失败 100% 来自上一行的 `ConfigDB.pas` 编码事故 |

## 汇总

- 成功：**1**（DeepMoveC）
- 失败：**4**（ClipVault / DeepLaunch / DeepRenew / DeepRenewAdmin；**全部 pre-existing**，与 AIErrorHandler 植入无因果）
- 跳过：**1**（DeepInsightApp，inventory 误归类，实为 FMX）
- 改动严格 `+2 / -0`：✅
  - getDiagnostics 对 5 个改动 `.dpr` 全部 "No diagnostics found"
  - 文本扫描：5 个文件 `DeepBase.AIErrorHandler.Bootstrap` 出现次数=1、`InstallAIErrorHandler` 出现次数=1

## 改动模板复核

按 G2/G3 验证过的模板：

- 有 `DeepBase.*` uses（DeepLaunch / DeepRenew / DeepRenewAdmin）：紧跟在最后一个 `DeepBase.*` 之后插入 `DeepBase.AIErrorHandler.Bootstrap,`
- 无 `DeepBase.*` uses（ClipVault / C盘超级瘦身.dpr）：插入位置选在最后一个非 `XXX in 'XXX.pas'` 形式的 uses 之后、第一个业务 `in` uses 之前（ClipVault 用 `FireDAC.Phys.SQLite,`、DeepMoveC 用 `System.IOUtils,` 作为锚点）

`InstallAIErrorHandler;` 一律放在 `begin` 之后的第一行有效语句：

- ClipVault / DeepMoveC / DeepRenew / DeepRenewAdmin：放在 `Application.Initialize;` 之前
- DeepLaunch：放在最外层 `try` 之后的第一行（即 `TPathHelper.EnsureDeepBaseReady;` 之前），保证 EnsureDeepBaseReady 自身的异常也能被 AIErrorHandler 兜住

特别说明：

- DeepLaunch 的 `begin..end.` 已经被一个外层 `try..except on E: Exception do ...` 包住、并最后还有一段 `try if DeepBase.IsInitialized then DeepBase.Finalize except end;` 善后逻辑。`InstallAIErrorHandler` 放在 `try` 内部的最前面，与既有 except 分支链式互不干扰（AIErrorHandler.Install 内部链接前 OnException、bootstrap 内部 try..except 不外抛）
- ClipVault 的 single-instance mutex 检查在 `Application.Initialize;` 之前；如果当前进程是"第二实例"会触发 `Exit;` 直接返回。此时 `InstallAIErrorHandler` 之前的 mutex/SendMessage 路径不会复用 AIErrorHandler，但这正是预期——单例分支属于 fast-path，不应安装全局 hook

## 关于跳过 DeepInsightApp.dpr

文件源码（前 12 行）：

```pascal
program DeepInsightApp;

uses
  System.StartUpCopy,
  System.SysUtils,
  System.UITypes,
  FMX.Forms,
  FMX.Skia,
  FMX.Dialogs,
  FireDAC.FMXUI.Wait,
  ...
```

是典型的 FMX 入口（`FMX.Forms` + `FireDAC.FMXUI.Wait`），且 `Application.Initialize;` / `Application.CreateForm(TMainForm, ...)` 都解析到 `FMX.Forms.Application`。

`DeepBase.AIErrorHandler.Bootstrap` 的 interface 段只 `uses DeepBase.AIErrorHandler;`，但 `DeepBase.AIErrorHandler.pas` interface 段就 `uses Vcl.Forms;`——一旦把 Bootstrap 加到 `DeepInsightApp.dpr` 的 uses，链接器会同时把 `Vcl.Forms` 的 `Application` 全局变量与初始化代码也链进来，与 `FMX.Forms.Application` 形成两份 Application 实例，且 `TAIErrorHandler.Install` 里的 `Application.OnException := …` 是落在 `Vcl.Forms.Application` 上，而程序里跑的事件是 `FMX.Forms.Application`，等同于"装了等于没装"，还顺带让 VS 启动顺序、Vcl/FMX 的 OS 钩子各自激活两次。

inventory 的"出范围（FMX）"小节 8 个文件的剔除理由完全适用：

> `DeepBase.AIErrorHandler.pas` 核心 `uses Vcl.Forms` 与 `Vcl.Dialogs.MessageDlg`，要支持 FMX 入口需要拆出平台无关核心 + 两个适配器，超出本 spec 边界（违反 R5.3 不改对外签名）。留待后续 spec。

DeepInsightApp.dpr 是 inventory 表格 G4 行误归类为 VCL（实际是 FMX，且 inventory 末尾的"出范围（FMX）"小节列了 8 个文件、漏了它）。当前选择是**保持原样、原因记录到本 group log**，等"AIErrorHandler 平台无关核心拆分"那一期一并处理。

## 关于 DeepMoveC 的中文文件名

PowerShell 7+ 的 `&` 启动外部进程时，命令行参数会经过 `[Console]::OutputEncoding` / 当前 ANSI 代码页一轮转换。这台机器系统代码页是 GBK (CP936)，但 PowerShell 默认用 UTF-8 处理字符串，导致 `C盘超级瘦身.dpr` 这个 Unicode 路径在 spawn 时被双重转换，dcc64 收到的是 `C鐩樿秴绾х槮 韬?dpr` 这种坏码，立即 `F1026 File not found`。

绕开方式：在同目录用 `[System.IO.File]::Copy` 复制一份 `_DeepMoveC_g4.dpr`（纯 ASCII 文件名）作为编译别名，对它跑 dcc64，编译完删 `_DeepMoveC_g4.dpr` / `_DeepMoveC_g4.dcu` / `_DeepMoveC_g4.exe`。原始 `C盘超级瘦身.dpr` 文件本身只受 `+2 / -0` 植入修改、无任何重命名。`program DeepMoveC;` 与 .dpr 文件名一致，dcc64 不要求 `program` 名等于 .dpr 文件名（只用 .dpr 文件 stem 替换 `*.res`），所以别名编译产出的 .exe / .dcu 与正常编译完全等价。

> 副作用：用了别名编译产生的 `_DeepMoveC_g4.exe` 在 `_result/` 下被立即删除；原始的 `C盘超级瘦身.dpr` 没有 `.dproj`，IDE 路径显然另有约定，但目前不需要解决——本任务只确认 `+2 / -0` 后能 dcc64 编译干净。

## 失败聚合（dcc64 错误片段）

### ClipVault.dpr — pre-existing 资源文件缺失

```
Error: E1026 File not found: 'DeepClip.res'
```

`{$R *.res}` 把 `*.res` 解析为 .dpr 文件 stem 时按 `program DeepClip;` 找的是 `DeepClip.res`（在 dcc64 的 `*.res` 替换语义里，`*` 取 `program <Name>;` 中的 `<Name>`，不取 .dpr 文件名）。`DeepLaunch/ClipDemo/` 目录里没有 `DeepClip.res`；同名资源只在 sibling 项目 `02Business/DeepClip/DeepClip.res` 里。`ClipVault.dproj` 也仍把 `<MainSource>` 指向不存在的 `DeepClip.dpr`。

修复方向（不在本任务）：要么把 `program DeepClip;` 改成 `program ClipVault;` 并提供 `ClipVault.res`、要么把 `02Business/DeepClip/DeepClip.res` 复制 / 软链到 `02Business/DeepLaunch/ClipDemo/`、要么把 `{$R *.res}` 改成显式 `{$R DeepClip.res 'src\\path\\to\\res'}`。

### DeepLaunch.dpr — pre-existing 第三方组件缺失

```
DeepLaunch\src\UI\FrameFileExplorer.pas(20) Fatal: F2613 Unit 'EasyListview' not found.
```

`EasyListview` 是 Mustangpeak EasyListview / `MustangpeakListView-13` 的核心单元。这台机器：

- `D:\Personal\Documents\Embarcadero\Studio\37.0\CatalogRepository\MustangpeakListView-13` 是空目录
- `D:\ProgramData\delphi\` 全工作区无 `EasyListview.pas`
- `Get-ChildItem -Path 'D:\' -Recurse -Filter 'EasyListview.pas'` 全盘搜也没匹配

是环境侧依赖未安装。修复方向（不在本任务）：在该机上把 MustangpeakListView 装进 `BDSCatalogRepository` 或 `ProgramData\delphi`，或在 `DeepLaunch.dproj` 的 `DCC_UnitSearchPath` 里再补 `MustangpeakListView-13/.../Source`。

### DeepRenew.dpr / DeepRenewAdmin.dpr — pre-existing ConfigDB.pas 编码事故

```
DeepRenew\ConfigDB.pas(35) Error: E2029 '=' expected but ':' found
DeepRenew\ConfigDB.pas(36) Error: E2029 '=' expected but ':' found
DeepRenew\ConfigDB.pas(37) Error: E2029 '=' expected but ':' found
DeepRenew\ConfigDB.pas(38) Error: E2029 '=' expected but ':' found
DeepRenew\ConfigDB.pas(39) Error: E2029 '=' expected but ':' found
DeepRenew\ConfigDB.pas(40) Error: E2029 '=' expected but ':' found
DeepRenew\ConfigDB.pas(41) Error: E2029 'IMPLEMENTATION' expected but ';' found
DeepRenew\ConfigDB.pas(53) Error: E2029 '.' expected but ';' found
DeepRenew\ConfigDB.pas(64) Warning: W1011 Text after final 'END.' - ignored by compiler
DeepRenew\uDM.pas(15) Fatal: F2063 Could not compile used unit 'ConfigDB.pas'
```

逐字节分析（hex dump 在 line 33 处）：

```
... 65 6E 64 3B 0A 0A     -> "end;\n\n"
20 20 2F 2F 20            -> "  // "
E8 A7 A3                  -> "解" (UTF-8 三字节)
E6 9E 90                  -> "析" (UTF-8 三字节)
E5 99 A8                  -> "器" (UTF-8 三字节)
E9 85 8D                  -> "配" (UTF-8 三字节)
E7 BD 3F                  -> 应为 E7 BD AE = "置"，但第 3 字节被破坏成 0x3F ('?')
20 20                     -> "  "  ← 期望这里有换行符 0A，但没有！
54 50 61 72 73 65 72 ...  -> "TParser..."
```

两件坏事叠加：

1. `置` (U+7F6E, UTF-8 = `E7 BD AE`) 被损成 `E7 BD 3F`（第 3 字节被 ASCII 替换符 `?` 顶替）
2. 行末 `0A` 被吞，单行注释 `// 解析器配?  TParserConfig = record` 把下一行的类型声明也吞进了注释

后果：编译器看 `TParserConfig = record` 整段消失，下一行 `ID: Integer;` 出现在外层 type 块、被解析为 "下一个类型别名" 的位置——`Integer;` 后期望 `=`，看到 `:` → E2029 链式炸；直到 `41` 行的 `end;` 被解读成"应当是 IMPLEMENTATION"。

修复方向（不在本任务，按"其它 pre-existing → 不修"约束）：恢复 line 33 末尾的 `0A` 并把 `E7 BD 3F` 还原成 `E7 BD AE`。两步合一行：

```diff
- // 解析器配?  TParserConfig = record
+ // 解析器配置
+ TParserConfig = record
```

---

## 编译命令记录

完整脚本：

- 首轮：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g4_compile/compile_g4.ps1`
- DeepMoveC ASCII 别名重试：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g4_compile/compile_g4_retry.ps1`

```pwsh
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$ROOT = 'd:\_Progs\02Business'
$RESULT = 'd:\_Progs\02Business\.kiro\specs\aierrorhandler-rollout\exec-log\_g4_compile\_result'
$BDS_CAT = 'D:\Personal\Documents\Embarcadero\Studio\37.0\CatalogRepository'
$VTV13   = "$BDS_CAT\VirtualTreeView-13\2025.03\Source"
$MSHELL  = "$BDS_CAT\MustangpeakVirtualShell-13\2025.03\Source"
$MCOMMON = "$BDS_CAT\MustangpeakCommonLibrary-13\2025.03\Source"
$SKIA    = 'D:\ProgramData\delphi\Skia4Delphi'
$SYNEDIT = 'D:\ProgramData\delphi\SynEdit-master\Source'
$SYNHL   = 'D:\ProgramData\delphi\SynEdit-master\Source\Highlighters'
$VTV_M   = 'D:\ProgramData\delphi\VirtualTreeView-master\Source'

$CommonNS = 'System;Vcl;Winapi;System.Win;Data;Xml;Soap;Web;FireDAC'
$CommonDB = "$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance"

# 1. ClipVault (DeepLaunch/ClipDemo) — VCL GUI + Skia + SynEdit + VTV
& $DCC "-E$RESULT" `
  "-U$CommonDB;$ROOT\DeepLaunch\ClipDemo\src\Core;$ROOT\DeepLaunch\ClipDemo\src\UI;$SKIA;$SYNEDIT;$SYNHL;$VTV_M" `
  "-NS$CommonNS" "-DSKIA" `
  "$ROOT\DeepLaunch\ClipDemo\ClipVault.dpr"

# 2. DeepLaunch — VCL GUI + Mustangpeak/VirtualTree
& $DCC "-E$RESULT" `
  "-U$CommonDB;$ROOT\DeepLaunch\src\Core;$ROOT\DeepLaunch\src\UI;$VTV13;$MSHELL;$MCOMMON;$SKIA" `
  "-NS$CommonNS" `
  "$ROOT\DeepLaunch\DeepLaunch.dpr"

# 3. DeepMoveC — 中文文件名走别名
[System.IO.File]::Copy("$ROOT\DeepMoveC\C盘超级瘦身.dpr", "$ROOT\DeepMoveC\_DeepMoveC_g4.dpr", $true)
& $DCC "-E$RESULT" `
  "-U$CommonDB;$ROOT\DeepMoveC;$ROOT\DeepMoveC\AntiTamperPackage" `
  "-NS$CommonNS" `
  "$ROOT\DeepMoveC\_DeepMoveC_g4.dpr"
Remove-Item "$ROOT\DeepMoveC\_DeepMoveC_g4.dpr","$RESULT\_DeepMoveC_g4.dcu","$RESULT\_DeepMoveC_g4.exe" -ErrorAction SilentlyContinue

# 4. DeepRenew / 5. DeepRenewAdmin — 标准 DeepBase
foreach ($dpr in 'DeepRenew.dpr','DeepRenewAdmin.dpr') {
  & $DCC "-E$RESULT" `
    "-U$CommonDB;$ROOT\DeepRenew" `
    "-NS$CommonNS" `
    "$ROOT\DeepRenew\$dpr"
}
```

## 与 R9.1 / R9.2 / Property 15 的对应

- **R9.1 +2 / -0**：5 个改动 `.dpr` 均为 1 行 uses + 1 行调用，无任何源代码删除（`getDiagnostics` 全绿；文本扫描 `DeepBase.AIErrorHandler.Bootstrap` × 1 + `InstallAIErrorHandler` × 1）
- **R9.2 不碰 .dproj/.dfm/其它源文件**：本批次未改任何 .dproj、.dfm，未修改 `DeepBase.AIErrorHandler*.pas` 三件套；DeepMoveC 的 `_DeepMoveC_g4.dpr` 是临时编译别名，已删除
- **R9.3 幂等**：5 个 `.dpr` 全是首次植入，无重复跳过分支被触发；G4 复执时应自动检出 5 处已植入并跳过；DeepInsightApp 在复执时应继续按"FMX 出范围"跳过

## 结论

G4 组按"植入侧"成功率：**1/5**（DeepMoveC 唯一干净通过；其它 4 个全部 pre-existing 阻塞，与本特性无因果）；按"植入正确性"通过：**5/5**（所有改动严格 +2 / -0，diagnostics 全绿，模板复核 OK）；1 个文件按 FMX 出范围语义跳过。

**G4 通过**（"植入正确性"维度）。下一步建议：

1. 推进 G5（DeepShine 簇，5 个）
2. 单独立任务清理 G4 失败四例的 pre-existing 问题：
   - **ClipVault**：评估 ClipDemo 旧版去留；如保留则统一 `program ClipVault;` + `ClipVault.res` + 修 `.dproj` 的 `<MainSource>`；如废弃则归档
   - **DeepLaunch**：在工程机器上补 Mustangpeak EasyListview / `MustangpeakListView-13` 安装；或在 `.dproj` 的 `DCC_UnitSearchPath` 里指向已存在的副本
   - **DeepRenew / DeepRenewAdmin**：合修 `DeepRenew/ConfigDB.pas` 第 33 行（`E7 BD 3F` → `E7 BD AE`，并在 `配置` 后补 `\n`），一处源修复同时解锁两个 .dpr
3. 单独立任务把 DeepInsightApp.dpr 加进 inventory 的"出范围（FMX）"列表，并 fold 到后续"AIErrorHandler 平台拆分"那一期
