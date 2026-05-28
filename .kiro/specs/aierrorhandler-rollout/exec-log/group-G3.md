# G3 组：批量植入 AIErrorHandler

> 时间：2026-05-17
> 编译器：`D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe`（Delphi 13.1）
> 输出目录：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g3_compile/`
> 改动模板：每个 .dpr 严格 `+2 / -0`（uses 段加 `DeepBase.AIErrorHandler.Bootstrap`、`begin..end.` 起始处加 `InstallAIErrorHandler;`）

> 注：spec tasks.md 里的 G3 标题写的是 "DeepStory + DeepInsight + DeepSVG + DeepShine"——那是设计阶段占位文字。**实际清单以 inventory `dpr-inventory.md` 的 G3 为准**：DeepCompare 余 + DeepConfig 簇 + DeepInput。

## 结果一览

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 1 | `DeepCompare/delphi/ZhihuPoster.dpr` | +2 / -0 | **0** | 1676 行 console，CoInitialize → InstallAIErrorHandler 顺序 OK；只剩 hint/warning 噪声 |
| 2 | `DeepCompare/delphi/ZhihuPosterPro.dpr` | +2 / -0 | **1** | **pre-existing**：`F1026 File not found: 'Core\DeepCompare.Database.pas'`；该文件在工作区只在 `delphi\__history\` 残留，无 `.dproj`，是一份长期失修的源（`fileSearch` 全工作区匹配仅命中 history 副本） |
| 3 | `DeepConfig/ConfigEditor.dpr` | +2 / -0 | **1** | **pre-existing**：`ErrorLogger.pas(41)` E2356 / `ErrorLogger.pas(73)` E2009，单元自身的 property/method 类型不匹配，与本特性无关 |
| 4 | `DeepConfig/ConvertFilesToUTF8.dpr` | +2 / -0 | **1** | **pre-existing**：`UTF8Converter.pas(14) E2065 Unsatisfied forward declaration: 'TfrmUTF8Converter.FormCreate'`，UTF8Converter 单元自身 forward 声明未实现 |
| 5 | `DeepConfig/DeepConfig.dpr` | +2 / -0 | **0** | VCL GUI，唯一 hint 是 Bootstrap 自身的 H2077 噪声 |
| 6 | `DeepConfig/DeepConfig.fixed.dpr` | **skipped** | N/A | 文件结构性损坏：仅 6 行（`program / uses / Vcl.Forms, / System.SysUtils, / Vcl.Dialogs,`），uses 段未闭合，无 `begin..end.` 块。强制 +2 会创造不合法 Pascal 源；按 inventory "等 orchestrator 决定保不保留" 的提示，原样保留交还 |
| 7 | `DeepConfig/FixAccess.dpr` | +2 / -0 | **1** | **pre-existing**：源文件本身 GBK 字符乱码（多处 mojibake `'源文�?`、`'不存�?` 之类），在第 32/84/92/104 行触发 E2052 "Unterminated string"；早于本特性 |
| 8 | `DeepInput/src/DeepInput.dpr` | +2 / -0 | **0** | VCL GUI，干净通过 |

## 汇总

- 成功：**3**（ZhihuPoster / DeepConfig / DeepInput）
- 失败：**4**（ZhihuPosterPro / ConfigEditor / ConvertFilesToUTF8 / FixAccess；**全部 pre-existing**，与 AIErrorHandler 植入无因果）
- 跳过：**1**（DeepConfig.fixed.dpr 结构性损坏，无 begin..end. 块）
- 改动严格 `+2 / -0`：✅（getDiagnostics 对 7 个改动 .dpr 全部 "No diagnostics found"）

## 改动模板复核

按 G2 验证过的模板：

- 有 `DeepBase.*` uses（DeepInput、ZhihuPoster）：紧跟在最后一个 `DeepBase.*` 之后插入 `DeepBase.AIErrorHandler.Bootstrap`；ZhihuPoster 因为 `DeepBase.AppLifecycle;` 是 uses 末项，新增行成为新末项并继承 `;` 终止符（旧末项改 `,`，无行删除）
- 无 `DeepBase.*` uses（ZhihuPosterPro / ConfigEditor / ConvertFilesToUTF8 / DeepConfig / FixAccess）：插入位置选在最后一个非 `XXX in 'XXX.pas'` 形式的 uses 之后、第一个业务 `in` uses 之前；FixAccess 三个 uses 都是非 `in` 形式，最后的 `System.IOUtils;` 改 `,`，新增行成为新末项

`InstallAIErrorHandler;` 一律放在 `begin` 之后的第一行有效语句：
- ZhihuPoster：放在 `CoInitialize(nil);` 之前
- ZhihuPosterPro / ConfigEditor / DeepConfig / DeepInput：放在 `Application.Initialize;` 之前
- ConvertFilesToUTF8 / FixAccess：放在外层 `try` 之前

## 失败聚合（dcc64 错误片段）

### ZhihuPosterPro.dpr — 缺源文件（pre-existing）

```
DeepCompare\delphi\ZhihuPosterPro.dpr(23) Fatal: F1026 File not found: 'Core\DeepCompare.Database.pas'
```

`fileSearch` 全工作区找不到 `DeepCompare\delphi\Core\DeepCompare.Database.pas`，只有 `__history\DeepCompare.Database.pas` 残留。该 .dpr 也没有对应 .dproj，疑似长期失修的副入口或半重构遗留。**不在本任务修复范围**。

### ConfigEditor.dpr — ErrorLogger.pas 类型错误（pre-existing）

```
DeepConfig\ErrorLogger.pas(41) Error: E2356 Property accessor must be an instance field or method
DeepConfig\ErrorLogger.pas(41) Error: E2356 Property accessor must be an instance field or method
DeepConfig\ErrorLogger.pas(73) Error: E2009 Incompatible types: 'method pointer and regular procedure'
DeepConfig\FormMain.pas(9) Fatal: F2063 Could not compile used unit 'ErrorLogger.pas'
```

ErrorLogger.pas 单元自身 property accessor 与方法签名不匹配。与本特性无关，**不在本任务修复范围**。

### ConvertFilesToUTF8.dpr — UTF8Converter.pas 未实现 forward（pre-existing）

```
DeepConfig\UTF8Converter.pas(14) Error: E2065 Unsatisfied forward or external declaration: 'TfrmUTF8Converter.FormCreate'
DeepConfig\ConvertFilesToUTF8.dpr(12) Fatal: F2063 Could not compile used unit 'UTF8Converter.pas'
```

UTF8Converter.pas 中声明了 `TfrmUTF8Converter.FormCreate` 但未提供实现。**不在本任务修复范围**。

### FixAccess.dpr — 源文件 GBK 字符乱码（pre-existing）

```
DeepConfig\FixAccess.dpr(32) Error: E2052 Unterminated string
DeepConfig\FixAccess.dpr(33) Error: E2029 ',' or ')' expected but identifier 'Exit' found
DeepConfig\FixAccess.dpr(84) Error: E2052 Unterminated string
DeepConfig\FixAccess.dpr(85) Error: E2029 ')' expected but identifier 'FileContent' found
DeepConfig\FixAccess.dpr(92) Error: E2052 Unterminated string
DeepConfig\FixAccess.dpr(93) Error: E2029 ',' or ')' expected but 'END' found
DeepConfig\FixAccess.dpr(104) Error: E2052 Unterminated string
DeepConfig\FixAccess.dpr(105) Error: E2029 ',' or ')' expected but 'FINALLY' found
DeepConfig\FixAccess.dpr(106) Error: E2066 Missing operator or semicolon
DeepConfig\FixAccess.dpr(107) Error: E2125 EXCEPT or FINALLY expected
```

源文件存在多处中文字符 GBK→UTF-8 解码失败的 mojibake（如 `'源文�?'`、`'不存�?'`、`'已创建备�?'` 等），半字符破坏字符串闭合，连锁触发后续语法错误。这是 `.dpr` 文件本身的字符编码损坏，**不在本任务修复范围**。

## 关于 DeepConfig.fixed.dpr

文件全文（共 6 行）：

```pascal
program DeepConfig;

uses
  Vcl.Forms,
  System.SysUtils,
  Vcl.Dialogs,
```

——uses 段未闭合（末项是 `,`，没有 `;`）、无业务单元 `XXX in '...'`、无 `begin..end.` 块。

无法在保持 `+2 / -0` 不变量的前提下植入：
- 加 `DeepBase.AIErrorHandler.Bootstrap` 需要给 `Vcl.Dialogs,` 闭合 uses，但同时没有 `begin..end.` 容纳 `InstallAIErrorHandler;`，强行加会让本来就不合法的源更不合法。
- inventory 已经把这个文件标注为 "疑似临时修复版本——还是植入，等 orchestrator 决定保不保留"。当前选择是**原样保留**，由 orchestrator 决策保留 / 删除 / 重建后再植入。

## 编译命令记录

完整脚本：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g3_compile/compile_g3.ps1`

```pwsh
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$DC  = 'd:\_Progs\02Business\DeepCompare\delphi'
$DCFG = 'd:\_Progs\02Business\DeepConfig'
$DI   = 'd:\_Progs\02Business\DeepInput'

# DeepCompare 系列（ZhihuPoster*）：与 G2 的 DeepCompare 走相同 -U/-I，含 Skia / SynEdit / VTV / WebView4Delphi
& $DCC "-E$OUT" `
       "-U$DC\Core;$DC\DeepCompare;$DC\DeepCompareU;$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;$SKIA;$SYNEDIT;$SYNEDIT_HL;$VTV;$WV" `
       "-I$SYNEDIT_M" `
       "-NSSystem;Vcl;Winapi;System.Win;Data;Xml;Soap;Web" `
       "$DC\ZhihuPoster.dpr"

# DeepConfig 系列：单一目录 + DeepBase Core/VCL/Persistence/Features/Governance
& $DCC "-E$OUT" `
       "-U$DCFG;$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance" `
       "-NSSystem;Vcl;Winapi;System.Win;Data;Xml;Soap;Web" `
       "$DCFG\DeepConfig.dpr"

# DeepInput：DeepBase Core/VCL/Persistence/Features + Skia + SynEdit + VTV
& $DCC "-E$OUT" `
       "-U$DI\src;$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;$SKIA;$SYNEDIT;$SYNEDIT_HL;$VTV" `
       "-NSSystem;Vcl;Winapi;System.Win;Data;Xml;Soap;Web" `
       "$DI\src\DeepInput.dpr"
```

## 与 R9.1 / R9.2 / Property 15 的对应

- **R9.1 +2 / -0**：所有 7 个改动 .dpr 均为 1 行 uses + 1 行调用，无任何源代码删除（`getDiagnostics` 全绿）。两处需要把上一条 uses 的 `;` → `,` 是终止符调整、不是行删除。
- **R9.2 不碰 .dproj/.dfm/其它源文件**：本批次未改任何 .dproj、.dfm，未修改 DeepBase.AIErrorHandler*.pas 三件套。
- **R9.3 幂等**：8 个 .dpr 全是首次植入，无重复跳过分支被触发；G3 复执时应自动检出 7 处已植入并跳过。

## 结论

G3 组按"植入侧"成功率：**3/7**（剩 4 全部 pre-existing 阻塞，与本特性无因果）；按"植入正确性"通过：**7/7**（所有改动严格 +2 / -0，diagnostics 全绿）；1 个文件结构性损坏跳过。

下一步建议：
1. 推进 G4（DeepInsight + DeepLaunch + DeepMoveC + DeepRenew）；
2. 单独立任务清理 G3 失败四例的 pre-existing 问题：
   - **ZhihuPosterPro**：评估是否还需要 → 找回 / 重建 `Core\DeepCompare.Database.pas` 或确认 .dpr 退役（无 .dproj 倾向已退役）
   - **ConfigEditor / ConvertFilesToUTF8**：`ErrorLogger.pas`、`UTF8Converter.pas` 单元自身 bug，纯单元修复
   - **FixAccess**：`.dpr` 字符编码修复（GBK → UTF-8 重整中文字面量）
3. 评估 `DeepConfig.fixed.dpr` 去留：（a）若是历史误存，删之；（b）若仍需要，补全 uses + begin..end. 后再植入。
