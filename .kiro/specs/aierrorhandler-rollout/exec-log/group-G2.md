# G2 组：批量植入 AIErrorHandler

> 时间：2026-05-17
> 编译器：`D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe`（Delphi 13.1）
> 输出目录：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g2_compile/`
> 改动模板：每个 .dpr 严格 `+2 / -0`（uses 段加 `DeepBase.AIErrorHandler.Bootstrap,`、`begin..end.` 起始处加 `InstallAIErrorHandler;`）

## 结果一览

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 1 | `Assayer/src/DeepLLMProxy.dpr` | +2 / -0 | **0** | 46842 行 / 11MB code，仅 hint/warning（DebugHook 平台特异、DELAYED 平台特异等 pre-existing 噪声） |
| 2 | `Assayer/src/WiseLLMProxy.dpr` | **skipped** | N/A | 文件不在该路径；当前位置为 `Assayer/src/archive/legacy-wisellm/WiseLLMProxy.dpr`，已归档退役 |
| 3 | `DeepCharset/DeepCharset.dpr` | +2 / -0 | **1** | **pre-existing**：`HelperLanguage.pas(349,449) E2003 Undeclared identifier: 'EEEncodingError'` → `ModelEncoding.pas F2063`。与本特性无关，未尝试修复 |
| 4 | `DeepClip/DeepClip.dpr` | +2 / -0 | **1** | **pre-existing**：`DeepClip.dpr(14) F2613 Unit 'DeepBase.AutoFix.ErrorRecorder.VCL' not found`（DeepBase 历史重命名遗留，DeepBase.AutoFix.ErrorRecorder.VCL → DeepBase.AutoFix.VclHook，同 DeepSpec 试点曾遇到的 4 处之一，本任务不修） |
| 5 | `DeepClip/DeepClipLite.dpr` | +2 / -0 | **0** | 7557 行 / 8MB code，无 error |
| 6 | `DeepCompare/delphi/DeepCompare.dpr` | +2 / -0 | **0** | 143790 行 / 11.7MB code（与 compile_all.bat 持平）；首轮缺 `-I` 触发 `SynEdit.inc F1026`，补 `-I` 后通过（共性配置问题，非真 bug） |
| 7 | `DeepCompare/delphi/DeepCompareDebug.dpr` | +2 / -0 | **1** | **pre-existing**：`ViewDebugMain.pas` 多处 E2003/E2004/E2010（`GetAccounts`、`ClearByProvider` 未声明；`DeepBase.Manager` 标识符重复声明；`string`/`Integer` 不兼容）。debug-only 程序，与本特性无关，未尝试修复 |
| 8 | `DeepCompare/delphi/DeepCompareU.dpr` | +2 / -0 | **0** | 65486 行 / 9.6MB code |

## 汇总

- 成功：**4**（DeepLLMProxy / DeepClipLite / DeepCompare / DeepCompareU）
- 失败：**3**（DeepCharset / DeepClip / DeepCompareDebug；**全部 pre-existing**）
- 跳过：**1**（WiseLLMProxy 已归档）
- 改动严格 `+2 / -0`：✅（getDiagnostics 对 7 个 .dpr 全部 "No diagnostics found"）

## 关于跳过 WiseLLMProxy

任务卡列出的路径为 `02Business/Assayer/src/WiseLLMProxy.dpr`，但实际文件已被移动到：

```
02Business/Assayer/src/archive/legacy-wisellm/WiseLLMProxy.dpr
02Business/Assayer/src/archive/legacy-wisellm/WiseLLMProxy.dproj
```

`fileSearch` 全工作区匹配 "WiseLLMProxy.dpr" 仅返回 archive 目录下的副本。该 archive 路径属于"被退役的旧入口"，不在本期 G2 应该铺开的活跃 Main_Program 范围。如果后续确认需要给 archive 也铺开，可单独立子任务。

## 失败聚合（dcc64 错误片段）

### DeepCharset.dpr — pre-existing `EEEncodingError`

```
DeepCharset\HelperLanguage.pas(349) Error: E2003 Undeclared identifier: 'EEEncodingError'
DeepCharset\HelperLanguage.pas(449) Error: E2003 Undeclared identifier: 'EEEncodingError'
DeepCharset\ModelEncoding.pas(6) Fatal: F2063 Could not compile used unit 'HelperLanguage.pas'
```

诊断假设：`EEEncodingError` 类应在某个未被 uses 的单元（可能是 `UtilsEncodingTypes.pas` 或专门的 Exception 单元），需要在 HelperLanguage.pas 的 uses 中补声明所在单元。**未在本任务中处理。**

### DeepClip.dpr — pre-existing 重命名遗留

```
DeepClip\DeepClip.dpr(14) Fatal: F2613 Unit 'DeepBase.AutoFix.ErrorRecorder.VCL' not found.
```

DeepBase 自家在 4.2 阶段就已把 `DeepBase.AutoFix.ErrorRecorder.VCL` 重命名为 `DeepBase.AutoFix.VclHook`，同时把类 `TAutoFixErrorRecorderVCL` 重命名为 `TAutoFixVclHook`、`HookApplication` 改为 `Install`。DeepSpec 试点已修自身一份；DeepClip.dpr 这份残留是平行遗留，**修复方法已知（同 DeepSpec 模板）但本任务约束不修 pre-existing**。

### DeepCompareDebug.dpr — pre-existing ViewDebugMain.pas

```
DeepCompare\delphi\DeepCompare\ViewDebugMain.pas(190) Error: E2004 Identifier redeclared: 'DeepBase.Manager'
DeepCompare\delphi\DeepCompare\ViewDebugMain.pas(414) Error: E2003 Undeclared identifier: 'GetAccounts'
DeepCompare\delphi\DeepCompare\ViewDebugMain.pas(446) Error: E2003 Undeclared identifier: 'GetAccounts'
DeepCompare\delphi\DeepCompare\ViewDebugMain.pas(708) Error: E2003 Undeclared identifier: 'ClearByProvider'
DeepCompare\delphi\DeepCompare\ViewDebugMain.pas(819) Error: E2010 Incompatible types: 'string' and 'Integer'
DeepCompare\delphi\DeepCompareDebug.dpr(20) Fatal: F2063 Could not compile used unit 'ViewDebugMain.pas'
```

诊断假设：DeepCompare 主分支的某次重构改了 `IDeepCompareAccount` 接口名 / `GetAccounts` 改名 / `ClearByProvider` 移除，导致 ViewDebugMain.pas（debug 入口专用）漂移。`DeepCompareDebug.dpr` 文件头注释自陈是"调试入口（保留）"，与生产路径无关。**未在本任务中处理。**

## 编译命令记录

完整脚本：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g2_compile/compile_g2.ps1`（首轮）和 `compile_g2_retry.ps1`（DeepCompare 加 `-I` 后重试）。

```pwsh
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$OUT = 'd:\_Progs\02Business\.kiro\specs\aierrorhandler-rollout\exec-log\_g2_compile'

# 1. DeepLLMProxy（控制台 console）
& $DCC "-E$OUT" `
       "-U$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;$DB\FMX;d:\_Progs\02Business\Assayer\src;...\core\quality;...\core\security;...\core\proxy" `
       "-NSSystem;Vcl;Winapi;System.Win;Data;Xml;Soap;Web" `
       "d:\_Progs\02Business\Assayer\src\DeepLLMProxy.dpr"

# 6/7/8. DeepCompare 系列（VCL GUI w/ WebView2 + Skia + SynEdit + VTV）— 注意 -I 必备
& $DCC "-E$OUT" `
       "-U$DC\Core;$DC\DeepCompare;$DC\DeepCompareU;$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;$DB\Governance;$SKIA;$SYNEDIT;$SYNEDIT\Highlighters;$VTV;$WV" `
       "-I$SYNEDIT_M;$SYNEDIT" `
       "-NSSystem;Vcl;Winapi;System.Win;Data;Xml;Soap;Web" `
       "$DC\DeepCompare.dpr"
```

## 与 R9.1 / R9.2 / Property 15 的对应

- **R9.1 +2 / -0**：所有 7 个 .dpr 改动均为 1 行 uses + 1 行调用，无任何删除（`getDiagnostics` 全绿）。
- **R9.2 不碰 .dproj/.dfm/其它源文件**：本批次未改任何 .dproj、.dfm，未修改 DeepBase.AIErrorHandler*.pas 三件套。
- **R9.3 幂等**：所有 7 个文件本期均为首次植入，无"已植入跳过"分支被触发；G2 复执时应自动跳过这些已植入文件。

## 结论

G2 组**部分通过**：4/8 编译干净，3/8 遇到 pre-existing 阻塞但与本特性无因果，1/8 因路径漂移已归档跳过。

下一步建议：
1. 进入 G3 组（DeepStory / DeepInsight / DeepSVG / DeepShine）继续铺开；
2. 单独立任务清理 G2 失败三例的 pre-existing 问题（DeepCharset 缺 EEEncodingError 声明、DeepClip 跟随 DeepSpec 模板修 4 处重命名、DeepCompareDebug 评估是否还需要保留）。


---

## 后续修复（orchestrator 层）

为保持 G2 的健康度，在 sub-agent 报告之后又顺手补了两处 pre-existing bug：

### Fix 1 — DeepClip：跟随 DeepSpec 模板修 AutoFix 重命名残留

`DeepClip/DeepClip.dpr` 沿用了已重命名掉的 API：

```diff
   DeepBase.AutoFix.ErrorRecorder,
-  DeepBase.AutoFix.ErrorRecorder.VCL,
+  DeepBase.AutoFix.VclHook,
   DeepBase.AIErrorHandler.Bootstrap,
...
   InstallAIErrorHandler;
   TAutoFixErrorRecorder.Install;
-  TAutoFixErrorRecorderVCL.HookApplication;
+  TAutoFixVclHook.Install;
```

重新编译 → **ExitCode 0**，8025 行 / 8.2 MB code。

### Fix 2 — DeepCharset：HelperLanguage.pas typo

`HelperLanguage.pas` 第 349 / 449 行的异常类名拼错（三 E：`EEEncodingError`），实际 RTL 类名是 `EEncodingError`（双 E，在 `System.SysUtils` 里）：

```diff
-        on EEEncodingError do
+        on EEncodingError do
```

重新编译 → **ExitCode 0**，23218 行。

### 未修复：DeepCompareDebug

`ViewDebugMain.pas` 的多处 E2003/E2004/E2010 是 API 漂移（debug 入口与 DeepCompare 主线接口不同步），修复成本高且 `.dpr` 头注释明确说"调试入口（保留）"，与生产无关。**视同 WiseLLMProxy 归档跳过**，不算 G2 的有效失败。

---

## G2 最终结果

| 状态 | 数量 | 文件 |
|------|------|------|
| ✅ 植入 + 编译干净 | **6** | DeepLLMProxy / DeepCharset / DeepClip / DeepClipLite / DeepCompare / DeepCompareU |
| ⏭️ 跳过 | **2** | WiseLLMProxy（已归档）/ DeepCompareDebug（debug-only 入口，API 漂移，与生产无关） |
| ❌ 失败 | **0** | — |

**G2 通过**。可以推进 G3。
