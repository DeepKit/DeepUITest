# 回退事件记录 — 2026-05-17

## 现象

任务 4.2 阶段的 sub-agent 修过 32 个 `.pas` 文件 / 48 个站点的 Rust 风格 `if-then-else` 表达式 bug，并经 grep 扫描确认 0 残留。
任务 2 阶段我亲自修过 `DeepBase/Features/DeepBase.LLM.Service.pas` 第 431-440 行 4 处。

执行 task 10 检查点时，全工作区扫描发现 **20 个站点重新出现非法 Rust 风格 `if-then-else`**。其中：

- **明确"修过又被回退"** ：13 处，全部在 `02Business/DeepBase/` 子树
- **新出现（我从未改过）**：7 处，全部在 `02Business/DeepBase/Tests/` 子树
- 其它产品（DeepCharset、DeepConfig、DeepDev、DeepDevLite、DeepInsight、DeepLaunch、DeepRenew、DeepSpec、DeepStory、DeepSync）**没有任何回退**

`DeepBase/Features/DeepBase.LLM.Service.pas` 第 431-440 行也回退到非法状态（已被检测到并第二次修复）。

## 详细清单

### 已被回退（DeepBase 根目录下，13 处）

| 文件 | 行号 | 形态 | sub-agent 4.2 阶段是否修过 |
|------|------|------|---------------------------|
| `DeepBase/Core/DeepBase.Collections.pas` | 422 | `L := if C < 0 then M + 1 else L;` | ✅ 修过，已回退 |
| `DeepBase/Core/DeepBase.Collections.pas` | 423 | `H := if C > 0 then M - 1 else H;` | ✅ 修过，已回退 |
| `DeepBase/Features/DeepBase.IntentClarification.LLMResilience.pas` | 453 | `var LErr := if Result.ErrorMessage <> '' then Result.ErrorMessage` | ✅ 修过，已回退 |
| `DeepBase/Features/DeepBase.LLM.Service.pas` | 431-440 | `AMaxTokens := if ATier = TierFast then 2048 ...` (4 处) | ✅ 我亲自修过，已回退 |
| `DeepBase/Persistence/DeepBase.SQLLogger.pas` | 530 | `LExtraDict.Add('success', if AEntry.Success then 'true' else 'false');` | ✅ 修过，已回退（已第二次修复，作为 task 10 排查的一部分） |
| `DeepBase/VCL/DeepBase.VCL.DeepShell.Localization.pas` | 98 | `FLocale := if ADefaultLocale <> '' then ...` | ✅ 修过，已回退 |
| `DeepBase/VCL/DeepBase.VCL.DeepShell.Panels.pas` | 112 | `FState.Size := if FPanel <> nil then ...` | ✅ 修过，已回退 |
| `DeepBase/VCL/DeepBase.VCL.DeepShell.Panels.pas` | 241 | `FCapacity := if ACapacity > 0 then ...` | ✅ 修过，已回退 |
| `DeepBase/VCL/DeepBase.VCL.DeepShell.Recent.pas` | 53 | `FCapacity := if ACapacity > 0 then ...` | ✅ 修过，已回退 |
| `DeepBase/VCL/DeepBase.VCL.DeepShell.Recent.pas` | 111 | `LItem.ItemKey := if AProjectId <> '' then ...` | ✅ 修过，已回退 |
| `DeepBase/VCL/DeepBase.VCL.DeepShell.Recent.pas` | 114 | `LItem.DisplayName := if ADisplayName <> '' then ...` | ✅ 修过，已回退 |
| `DeepBase/VCL/DeepBase.VCL.DeepShell.Settings.pas` | 119 | `WriteString(AKey, if AValue then 'true' else 'false');` | ✅ 修过，已回退 |
| `DeepBase/VCL/DeepBase.VCL.LLMSettingsFrame.pas` | 369 | `var Tag := if I = 0 then ' [首用]' else ' [兜底]';` | ✅ 修过，已回退 |

### 全新（DeepBase/Tests 与 Core 子树，我从未改过，7 处）

| 文件 | 行号 | 形态 |
|------|------|------|
| `DeepBase/Core/DeepBase.AutoFix.ErrorRecorder.pas` | 336 | `FRunId := if ARunId = '' then NewRunId else ARunId;` |
| `DeepBase/Tests/Test.DeepBase.Browser.ResponseWaiter.PBT.pas` | 212 | `AEnvelope.DurationMs := if LDurNum <> nil then LDurNum.AsInt64 else 0;` |
| `DeepBase/Tests/Test.DeepBase.Browser.ResponseWaiter.PBT.pas` | 268 | `LResult := if Iter mod 4 = 0 then 'timeout'` |
| `DeepBase/Tests/Test.DeepBase.Config.PBT.pas` | 276 | `var LSource := if (Iter mod 3) = 0 then 'src.path "weird"' else '';` |
| `DeepBase/Tests/Test.DeepBase.DeepShell.EventBus.PBT.pas` | 227 | `var LDiag := if LWrongClass = '' then 'nothing' else LWrongClass;` |
| `DeepBase/Tests/Test.DeepBase.SQL.Security.PBT.pas` | 232 | `var LDescr := if LWrongClass = '' then '<no exception>' else LWrongClass;` |
| `DeepBase/Tests/Test.DeepBase.SQL.Security.PBT.pas` | 398 | `var LDescr := if LWrongClass = '' then '<no exception>' else LWrongClass;` |
| `DeepBase/Tests/AutoFix/Test.DeepBase.AutoFix.ScenarioRunner.pas` | 197 | `var LExpectedStatus := if LThrowFlags[J] then 'fail' else 'pass';` |
| `DeepBase/Tests/Test.DeepBase.Commerce.Service.PBT.pas` | 387 | `(if LIsTerminal then 'terminal' else 'non-terminal'),` (Pattern C) |

### 未回退（其它产品子树，sub-agent 当时也修过，状态完好）

| 路径范围 | 修过站点数 | 当前状态 |
|----------|-----------|----------|
| `DeepCharset/HelperLanguage.pas` | 2 | ✅ 完好 |
| `DeepConfig/ConfigManager.pas`、`ErrorLogger.pas` | 4 | ✅ 完好 |
| `DeepDev/HelperJson.pas`、`PresenterCodeEditor.pas` | 2 | ✅ 完好 |
| `DeepDevLite/HelperJson.pas` | 1 | ✅ 完好 |
| `DeepInsight/CtrlLlm.pas` | 1 | ✅ 完好 |
| `DeepLaunch/src/Core/ThemeManager.pas` | 1 | ✅ 完好 |
| `DeepRenew/MetricsCore.pas`、`ScoringEngine.pas` | 3 | ✅ 完好 |
| `DeepSpec/**/*.pas`（Yaml、MainForm、Models、Services 等 7 个文件） | 14 | ✅ 完好 |
| `DeepStory/SvcDraw.pas`、`SvcGuide.pas`、`SvcDraft.pas` | 3 | ✅ 完好 |
| `DeepSync/src/core/uStoragePaths.pas` | 2 | ✅ 完好 |

## 模式分析

回退**完全集中**在 `02Business/DeepBase/` 子树：Core、VCL、Features、Persistence 四个子目录都有命中。

其它产品项目（DeepCharset、DeepConfig、DeepDev、DeepDevLite、DeepInsight、DeepLaunch、DeepRenew、DeepSpec、DeepStory、DeepSync）**全部完好**，覆盖 26+ 个修复站点。

`DeepBase/Tests/` 出现了一批我从未碰过的新非法表达式（7 处），疑似最近有人写了新的测试文件，没注意到 Rust 风格表达式不合法。`DeepBase.AutoFix.ErrorRecorder.pas:336` 和这一类相同 —— 也是我没改过的新代码。

## 几个可能的根因

1. **DeepBase 子模块独立 git 仓库**：`02Business/DeepBase/.git` 存在（前面 `listDirectory` 看到过）。如果有人在 DeepBase 仓库内 git pull / git checkout，就会把上游的非法版本拉进来覆盖本地修复
2. **IDE 打开了 DeepBase 子工程**：Delphi 13.1 IDE 如果挂载了 `pgDeepBase.groupproj`，自动打开了 `Core/Collections.pas`、`VCL/DeepShell.Recent.pas` 等，IDE 进程内有这些文件的旧 buffer，触发某事件就会写回磁盘
3. **备份同步反向**：`02Business/tasks.md` 提到 `d:\_Progs\04bakcup\02Business`，但通常备份是从工作区 → 备份目录的单向，反方向少见。除非有同步工具（OneDrive、Resilio Sync 等）配错了
4. **AI 协作工具的"提议改动"被反向应用**：GitHub Copilot Chat / Cursor / Continue 等如果有"建议改动"面板，是否被人误点了 reject + revert

## 建议的下一步

请按你的环境情况，做下面其中一项确认：

1. `cd 02Business/DeepBase && git status` —— 看 DeepBase 子仓有没有未提交的"修改" / "未跟踪"，特别是上面 13 处文件
2. `cd 02Business/DeepBase && git log --since='2 hours ago' --all --oneline` —— 最近两小时有没有 commit / pull
3. 看一下 IDE/Delphi/VSCode/Cursor 是不是开着 `pgDeepBase.groupproj`、`Collections.pas`、`SQLLogger.pas` 等文件（如果有，先**关掉所有 buffer 不保存**）
4. 确认有没有同步工具进程（任务管理器查 `OneDrive.exe` / `rsync` / `Resilio Sync` 等）

我现在不再继续推进任何 G8/G9 任务，免得反复修反复回退。等你查完根因再说。

## 已完成的回退恢复

为不阻塞 task 10 的 DeepInput 验证，我已经把 `DeepBase/Persistence/DeepBase.SQLLogger.pas:530` 和 `DeepBase/Features/DeepBase.LLM.Service.pas:431-440` **第二次修复**。剩下 11 处回退 + 9 处新出现，**等根因确认后再批量处理**，避免做无用功。
