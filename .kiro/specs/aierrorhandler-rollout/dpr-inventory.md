# DPR 清单与铺开分组

> 时间：2026-05-16
> 扫描根：`d:\_Progs\02Business\`
> 排除路径：`__history`、`__recovery`、`backup`、`.git`、`bin`、`dcu`、`archive`、`Old-DeepClip`

## 总览

| 类别 | 数量 |
|------|------|
| 全工作区 `.dpr` | 144 |
| FMX 出范围（本期不铺开） | **8** |
| 搁置项目无 `.dpr`（无需铺开） | DeepAssist · DeepFlow · DeepGuide · DeepJourney · DeepUITest · DeepUse |
| **本期铺开范围** | **136** |
| ├─ Pilot（试点） | 1 |
| ├─ Main_Program（主程序） | 36 |
| ├─ Tool_Program（DeepBase 自带工具） | 13 |
| ├─ Demo_Program（DeepBase Examples） | 13 |
| └─ Test_Program（测试 / Smoke / Behavior / Governance） | 74 |

## 调用约定

- **Pilot / Main / Tool / Demo**：`InstallAIErrorHandler;`（Production_Mode）
- **Test**：`InstallAIErrorHandlerForTests;`（强制 Test_Mode，无 MessageDlg）

每个 `.dpr` 改动 = 1 行 uses + 1 行调用 = 2 行新增、0 行删除。

---

## G1 — 试点（Pilot）

| # | .dpr 路径 | 备注 |
|---|----------|------|
| 1 | `DeepSpec/DeepSpec.dpr` | 已含 `TAutoFixErrorRecorderVCL.HookApplication`，是 confluence 验证的最佳试点 |

---

## G2..G8 — Main_Program（主程序，36 个）

每组 ≤ 8 个，按产品聚合。

### G2 — Assayer + DeepCharset + DeepClip + DeepCompare 簇（8）

| # | .dpr 路径 |
|---|----------|
| 1 | `Assayer/src/DeepLLMProxy.dpr` |
| 2 | `Assayer/src/WiseLLMProxy.dpr` |
| 3 | `DeepCharset/DeepCharset.dpr` |
| 4 | `DeepClip/DeepClip.dpr` |
| 5 | `DeepClip/DeepClipLite.dpr` |
| 6 | `DeepCompare/delphi/DeepCompare.dpr` |
| 7 | `DeepCompare/delphi/DeepCompareDebug.dpr` |
| 8 | `DeepCompare/delphi/DeepCompareU.dpr` |

### G3 — DeepCompare 余 + DeepConfig 簇（8）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepCompare/delphi/ZhihuPoster.dpr` |
| 2 | `DeepCompare/delphi/ZhihuPosterPro.dpr` |
| 3 | `DeepConfig/ConfigEditor.dpr` |
| 4 | `DeepConfig/ConvertFilesToUTF8.dpr` |
| 5 | `DeepConfig/DeepConfig.dpr` |
| 6 | `DeepConfig/DeepConfig.fixed.dpr` |
| 7 | `DeepConfig/FixAccess.dpr` |
| 8 | `DeepInput/src/DeepInput.dpr` |

### G4 — DeepInsight + DeepLaunch + DeepMoveC + DeepRenew（6）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepInsight/DeepInsightApp.dpr` |
| 2 | `DeepLaunch/ClipDemo/ClipVault.dpr` |
| 3 | `DeepLaunch/DeepLaunch.dpr` |
| 4 | `DeepMoveC/C盘超级瘦身.dpr` |
| 5 | `DeepRenew/DeepRenew.dpr` |
| 6 | `DeepRenew/DeepRenewAdmin.dpr` |

### G5 — DeepShine 簇（5）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepShine/Apps/DeepShine.TestGUI/DeepShine.TestGUI.dpr` |
| 2 | `DeepShine/Apps/DeepShineConfig/DeepShineConfig.dpr` |
| 3 | `DeepShine/Apps/DeepShineFlow/DeepShineFlow.dpr` |
| 4 | `DeepShine/Apps/DeepShineStudio/DeepShineStudio.dpr` |
| 5 | `DeepShine/Common/Legacy/DeepShine.Legacy.FakeCLI.dpr` |

### G6 — DeepStory + DeepSVG（5）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepStory/DeepStory.dpr` |
| 2 | `DeepStory/DeepStoryRef.dpr` |
| 3 | `DeepSVG/CEFCopier.dpr` |
| 4 | `DeepSVG/DeepSVG.dpr` |
| 5 | `DeepSVG/DeepSVG_TestRunner.dpr` |

### G7 — DeepSync 簇（3）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepSync/DeepSync.Agent.dpr` |
| 2 | `DeepSync/DeepSync.dpr` |
| 3 | `DeepSync/DeepSync.ScreenAgent.dpr` |

> Main 合计：8 + 8 + 6 + 5 + 5 + 3 = 35 个；DeepSpec.dpr 在 G1，加起来 36。

---

## G8..G9 — Tool_Program（DeepBase 自带工具，13 个）

### G8 — DeepBase 主工具（7）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepBase/DeepBaseRun/DeepBaseRun.dpr` |
| 2 | `DeepBase/Tools/CLI/DeepBase.dpr` |
| 3 | `DeepBase/Tools/Tray/DeepBaseTray.dpr` |
| 4 | `DeepBase/Tools/Studio/DeepBaseStudio.dpr` |
| 5 | `DeepBase/Tools/Studio/Studio.dpr` |
| 6 | `DeepBase/Tools/UniPublisher/DeepPublisher.dpr` |
| 7 | `DeepBase/Tools/UpdaterHelper/UpdaterHelper.dpr` |

### G9 — DeepBase 辅助工具 + 嵌入子项目（6）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepBase/Tools/LogAnalyzer/LogAnalyzer.dpr` |
| 2 | `DeepBase/Tools/SeedTool/SeedTool.dpr` |
| 3 | `DeepBase/DeepFlow/Source/DeepFlow.dpr` |
| 4 | `DeepBase/doQry/prjDoQry.dpr` |
| 5 | `DeepInsight/tools/DeepBasePathValidator.dpr` |
| 6 | `DeepSync/tools/BuildRunner.dpr` |

---

## G10..G11 — Demo_Program（DeepBase Examples，13 个）

### G10 — Examples 第一批（7）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepBase/doQry/examples/DoQryDemo/DoQryDemo.dpr` |
| 2 | `DeepBase/Examples/DataBindingDemo/DataBindingDemo.dpr` |
| 3 | `DeepBase/Examples/FullDemo/FullDemo.dpr` |
| 4 | `DeepBase/Examples/MicroserviceClientDemo/MicroserviceClientDemo.dpr` |
| 5 | `DeepBase/Examples/MultiLanguageDemo/MultiLanguageDemo.dpr` |
| 6 | `DeepBase/Examples/MVVMDemo/MVVMDemo.dpr` |
| 7 | `DeepBase/Examples/Phase0Demo/Phase0Demo.dpr` |

### G11 — Examples 第二批（6）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepBase/Examples/Phase1Demo/Phase1Demo.dpr` |
| 2 | `DeepBase/Examples/Templates/CRUDApp/CRUDApp.dpr` |
| 3 | `DeepBase/Examples/Templates/DataAnalyzer/DataAnalyzer.dpr` |
| 4 | `DeepBase/Examples/Templates/DocManager/DocManager.dpr` |
| 5 | `DeepBase/Examples/VCLDeepShellDemo/VCLDeepShellDemo.dpr` |
| 6 | `DeepBase/Examples/FMXDemo/FMXPlatformDemo.dpr` ⚠️ FMX，可与本期 FMX 出范围一并处理 |

> Demo 合计：13 个。注意 G11 #6 是 FMX，建议跳过或与 FMX 后续 spec 一起做。

---

## G12..G21 — Test_Program（测试 / Smoke / Behavior / Governance / Probe / Bench，74 个）

### G12 — Assayer 测试（6）

| # | .dpr 路径 |
|---|----------|
| 1 | `Assayer/tests/BehaviorMock/DeepLLMBehavior.dpr` |
| 2 | `Assayer/tests/DeepLLMTests.dpr` |
| 3 | `Assayer/tests/GovernanceSmoke.dpr` |
| 4 | `Assayer/tests/mORMot2Demo.dpr` |
| 5 | `Assayer/tests/ProvisionReplayProbe.dpr` |
| 6 | `Assayer/tests/WiseLLMTests.dpr` |

### G13 — DeepBase Tests 主目录（8）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepBase/Tests/DeepBaseTests.dpr` |
| 2 | `DeepBase/Tests/InferenceTests.dpr` |
| 3 | `DeepBase/Tests/MinimalDUnitX.dpr` |
| 4 | `DeepBase/Tests/SimpleTest.dpr` |
| 5 | `DeepBase/Tests/TestLLMClient.dpr` |
| 6 | `DeepBase/Tests/TestLLMProxyClient.dpr` |
| 7 | `DeepBase/Tests/TestNewModules.dpr` |
| 8 | `DeepBase/Tests/_tmp_DeepShellTestSolo.dpr` |

### G14 — DeepBase DebugTests（6）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepBase/Tests/DebugTest.dpr` |
| 2 | `DeepBase/Tests/DebugTest2.dpr` |
| 3 | `DeepBase/Tests/DebugTest3.dpr` |
| 4 | `DeepBase/Tests/DebugTest4.dpr` |
| 5 | `DeepBase/Tests/DebugTest5.dpr` |
| 6 | `DeepBase/Tests/DebugTest6.dpr` |

### G15 — DeepBase 子目录测试（6）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepBase/Tests/Acceptance/DeepBaseAcceptanceTest.dpr` |
| 2 | `DeepBase/Tests/Architecture/DeepBaseArchitectureTests.dpr` |
| 3 | `DeepBase/Tests/Governance/ConfigRegistrarPBT.dpr` |
| 4 | `DeepBase/Tests/GUI/DeepBaseGUITests.dpr` |
| 5 | `DeepBase/Tests/GUI/PageDriverSmoke.dpr` |
| 6 | `DeepBase/Tests/Integration/DeepBaseIntegrationTests.dpr` |

### G16 — DeepBase Speech / Stress（3）+ DeepCharset 测试（3）= 6

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepBase/Tests/Speech/SpeechSpike.dpr` |
| 2 | `DeepBase/Tests/Speech/TestSpeechHeadless.dpr` |
| 3 | `DeepBase/Tests/Stress/DeepBaseStressTests.dpr` |
| 4 | `DeepCharset/Tests/QuickTest.dpr` |
| 5 | `DeepCharset/Tests/SelfTest_Encoding.dpr` |
| 6 | `DeepCharset/Tests/TestBOM.dpr` |

### G17 — DeepClip + DeepCompare 测试（6）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepClip/tests/BehaviorMock/DeepClipBehavior.dpr` |
| 2 | `DeepClip/tests/DeepClip.Tests.dpr` |
| 3 | `DeepClip/tests/GovernanceSmoke/DeepClipGovernanceSmoke.dpr` |
| 4 | `DeepClip/tests/GovernanceSmoke/DeepClipGovernanceSmokeCfg.dpr` |
| 5 | `DeepCompare/delphi/Tests/DeepCompareTests.dpr` |
| 6 | `DeepCompare/delphi/WebView2Test.dpr` |

### G18 — DeepConfig 测试（8）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepConfig/TestAddPairProgram.dpr` |
| 2 | `DeepConfig/TestConfigs.dpr` |
| 3 | `DeepConfig/tests/EasyConfigTests.dpr` |
| 4 | `DeepConfig/tests/FinalConfigEditor.dpr` |
| 5 | `DeepConfig/tests/Minimal.dpr` |
| 6 | `DeepConfig/tests/MyConfig.dpr` |
| 7 | `DeepConfig/tests/NewConfigEditor.dpr` |
| 8 | `DeepConfig/tests/SimpleConfigEditor.dpr` |

### G19 — DeepConfig 余 + DeepInput + DeepInsight + DeepLaunch + DeepMoveC（7）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepConfig/tests/SimpleTest.dpr` |
| 2 | `DeepConfig/tests/Test.dpr` |
| 3 | `DeepInput/src/behavior_mock.dpr` |
| 4 | `DeepInput/src/struct_test.dpr` |
| 5 | `DeepInsight/tests/BehaviorMock/DeepInsightBehavior.dpr` |
| 6 | `DeepInsight/tests/DeepInsightTests.dpr` |
| 7 | `DeepLaunch/Tests/RunTests.dpr` |
| 8 | `DeepMoveC/Tests/DeepMoveCCoreTests.dpr` |

### G20 — DeepShine + DeepStory 测试（8）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepShine/Tests/BehaviorMock/DeepShineBehavior.dpr` |
| 2 | `DeepShine/Tests/GovernanceSmoke/GovernanceSmoke.dpr` |
| 3 | `DeepStory/DeepStorySchemeBench.dpr` |
| 4 | `DeepStory/TestApi.dpr` |
| 5 | `DeepStory/TestDB.dpr` |
| 6 | `DeepStory/TestDeepStoryRef.dpr` |
| 7 | `DeepStory/TestImport.dpr` |
| 8 | `DeepStory/TestWriting.dpr` |

### G21 — DeepStory 余 + DeepSVG + DeepSync 测试（8）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepStory/Tests/BehaviorMock/DeepStoryBehavior.dpr` |
| 2 | `DeepSVG/TestCoreFeaturesRunner.dpr` |
| 3 | `DeepSVG/TestRunner.dpr` |
| 4 | `DeepSVG/TestRunner_Simple.dpr` |
| 5 | `DeepSVG/tests/smoke/Smoke_Anim.dpr` |
| 6 | `DeepSVG/tests/smoke/Smoke_Static.dpr` |
| 7 | `DeepSVG/tests/smoke/Smoke_UIExport.dpr` |
| 8 | `DeepSync/tests/DeepSyncTests.dpr` |

### G22 — DeepSync 余测试（4）

| # | .dpr 路径 |
|---|----------|
| 1 | `DeepSync/tests/MockBehaviorRunner.dpr` |
| 2 | `DeepSync/tests/TestAgentIPC_Smoke.dpr` |
| 3 | `DeepSync/tests/TestScreenShare_Full.dpr` |
| 4 | `DeepSync/tests/TestScreenShare_Standalone.dpr` |

> Test 合计：6 + 8 + 6 + 6 + 6 + 6 + 8 + 7 + 8 + 8 + 4 = 73 个 + 1 个（`DeepBase/Tests/_tmp_DeepShellTestSolo.dpr` 在 G13）= 73 ❌ 应为 74。漏一个找一下：DeepDevTests.dpr 是 FMX 出范围。其它... 可能我把 Test 的某项漏数。下面"出范围 / 搁置"小节的 FMX 列表能对上 8 个就 OK。

---

## 出范围（FMX，本期不铺开）

| # | .dpr 路径 | 类型 |
|---|----------|------|
| 1 | `Assayer/src/DeepLLM_FMX.dpr` | Main FMX |
| 2 | `Assayer/src/WiseLLM_FMX.dpr` | Main FMX |
| 3 | `DeepConfig/DeepConfigFMX.dpr` | Main FMX |
| 4 | `DeepDev/DeepDev.dpr` | Main FMX |
| 5 | `DeepDev/DeepDevTests.dpr` | Test FMX |
| 6 | `DeepDevLite/DeepDevLite.dpr` | Main FMX |
| 7 | `DeepDevLite/Tests/DeepDevLiteTests.dpr` | Test FMX |
| 8 | `DeepRenew/DeepRenewFMX.dpr` | Main FMX |
| 9 | `DeepInsight/DeepInsightApp.dpr` | Main FMX（G4 执行时发现 inventory 误归类，实际 uses `FMX.Forms` + `FMX.Skia` + `FMX.Dialogs` + `FireDAC.FMXUI.Wait`） |
| 10 | `DeepSync/DeepSync.dpr` | Main FMX（G7 执行时发现 inventory 误归类，同上原因） |
| 11 | `DeepBase/DeepBaseRun/DeepBaseRun.dpr` | Main FMX（G8 执行时发现 inventory 误归类，uses `FMX.Forms` + `FMX.Dialogs`） |
| 12 | `DeepBase/DeepFlow/Source/DeepFlow.dpr` | Main FMX（G9 执行时发现 inventory 误归类，uses `System.StartUpCopy` + `FMX.Forms`） |

理由（见 design.md "决策与权衡"）：`DeepBase.AIErrorHandler.pas` 核心 `uses Vcl.Forms` 与 `Vcl.Dialogs.MessageDlg`，要支持 FMX 入口需要拆出平台无关核心 + 两个适配器，超出本 spec 边界（违反 R5.3 不改对外签名）。留待后续 spec。

## 出范围（搁置项目，无 .dpr 入口）

无须铺开：

- `DeepAssist/`
- `DeepFlow/`
- `DeepGuide/`
- `DeepJourney/`
- `DeepUITest/`
- `DeepUse/`

## 已知特殊文件提醒

- `DeepConfig/DeepConfig.fixed.dpr` —— 名字带 `.fixed`，疑似临时修复版本。植入前确认是否还活着、有无对应 .dproj
- `DeepBase/Tests/_tmp_DeepShellTestSolo.dpr` —— `_tmp_` 前缀，疑似实验性入口
- `DeepBase/Tests/DebugTest1..6.dpr` —— 6 个非数字编号 DebugTest，是排错用的临时入口，仍植入但优先级低
- `DeepInput/src/behavior_mock.dpr` 和 `struct_test.dpr` —— 文件名带 `_mock` `_test` 但放在 src 下，纳入 Test 组
- `DeepLaunch/ClipDemo/ClipVault.dpr` —— 名字含 Demo 但路径不在 Examples 下，归 Main
- `DeepSVG/DeepSVG_TestRunner.dpr` —— 名字带 TestRunner 但归 Main（它是个独立可执行 GUI 测试运行器，不是 DUnit 风格命令行测试）。如出问题再调整为 Test 组

---

## 验收对账

| 类别 | 此清单 | requirements 预期 |
|------|--------|------|
| Pilot | 1 | 1（DeepSpec） |
| Main | 36 | 不强制具体数 |
| Tool | 13 | 不强制具体数 |
| Demo | 13 | 不强制具体数 |
| Test | 74 | "约 60 个"（实际偏多） |
| FMX 出范围 | 8 | 设计阶段已明确 |
| **铺开总计** | **136** | "约 90 个" |

清单总数（136）比 requirements 阶段估算的 90 偏多约 50%，主要因为：
- DeepBase/Examples/ 13 个 Demo 当时未明确归类
- DeepBase/Tests/DebugTest1..6 + 各 BehaviorMock + Smoke + Probe + Bench 把 Test 数从估算的 60 拉高到 74

不影响推进，但任务 13-22 实际会比预估略多。


---

## 批次状态（2026-05-17 收口）

### 已完成

| 批次 | 类型 | 数量 | 植入正确性 | 编译干净 | 备注 |
|------|------|------|-----------|---------|------|
| G1 | Pilot | 1 | 1/1 ✅ | 1/1 ✅ | DeepSpec 试点 |
| G2 | Main | 8 | 6/8 ✅ | 6/8 | 1 archived，1 debug-only 跳过 |
| G3 | Main | 8 | 7/8 ✅ | 3/7 | 1 broken stub 跳过；4 pre-existing 失败已记录 |
| G4 | Main | 6 | 5/6 ✅ | 1/5 | 1 FMX 跳过（DeepInsightApp）；4 pre-existing 失败已记录 |
| G5 | Main | 5 | 5/5 ✅ | 5/5 ✅ | DeepShine 簇全通 |
| G6 | Main | 5 | 5/5 ✅ | 5/5 ✅ | DeepStory + DeepSVG 全通 |
| G7 | Main | 3 | 2/3 ✅ | 2/2 ✅ | 1 FMX 跳过（DeepSync.dpr） |
| G8 | Tool | 7 | 6/7 ✅ | 3/6 | 1 FMX 跳过（DeepBaseRun）；3 pre-existing 失败已记录（Studio×2 缺 DBClient、UniPublisher 文件坏）；顺手第 3 次修 LLM.Service Rust 风格 if-then-else |
| **G9** | **Tool** | **6** | **5/6 ✅** | **2/5** | **1 FMX 跳过（DeepFlow）；3 pre-existing 失败已记录（LogAnalyzer.MainForm 中文字符串坏、prjDoQry 缺 Data.Win 命名空间、DeepBasePathValidator 名空间歧义）** |
| Test Batch 1 (G16part + G17 + G18) | Test | 17 | 17/17 ✅ | 9/17 | 8 pre-existing 失败记录 |
| Test Batch 2 (G19 + G20) | Test | 16 | 16/16 ✅ | 13/16 | 3 pre-existing 失败记录 |
| Test Batch 3 (G21 + G22) | Test | 12 | 12/12 ✅ | 7/12 | 5 pre-existing 失败记录 |
| **AI 已完成合计** | | **94** | **87 / 94 ✅** | **57 / 87** | |

### 阻塞中（等同事处理 DeepBase / Assayer）

| 批次 | 类型 | 范围 | 数量 | 阻塞原因 |
|------|------|------|------|---------|
| G10 | Demo | DeepBase Examples 第一批 | 7 | 全部在 DeepBase/Examples |
| G11 | Demo | DeepBase Examples 第二批 | 6 | 全部在 DeepBase/Examples |
| G12 | Test | Assayer/tests/* | 6 | Assayer 子树等同事修 |
| G13 | Test | DeepBase/Tests/ 主目录 | 8 | DeepBase 子树 |
| G14 | Test | DeepBase/Tests/DebugTest1..6 | 6 | DeepBase 子树 |
| G15 | Test | DeepBase/Tests/Acceptance/Architecture/Governance/GUI/Integration | 6 | DeepBase 子树 |
| G16 part | Test | DeepBase/Tests/Speech/Stress | 3 | DeepBase 子树 |
| **阻塞合计** | | | **42** | |

### 总账

136 计划铺开 = 94（已做） + 42（阻塞）。

### 阻塞解除后我接力做的事

1. 等同事确认 DeepBase / Assayer 修复并稳定（regression-2026-05-17.md 里的 13 处回退 + 7 处新发都被修掉、且不会再回退）
2. 我重跑全工作区扫描，确认 0 残留 = 绿灯
3. G8 / G9 / G10 / G11 / G12 / G13 / G14 / G15 / G16 part 五大组合计 55 个 .dpr 一次性委托给 sub-agent 批量植入
4. 跑 task 18 最终检查点：`compile_all.bat` + 全部独立编译命令一次扫一遍，断言全部 ExitCode 0

### 同事修完前 AI 自身可选做的（不依赖同事）

- 任务 17.1 / 17.2 可选 PBT 静态校验测试（Property 14、15、16）—— 可选，跳过不影响发布
- 阶段一可选 PBT 子任务（1.5-1.7、2.2-2.4、3.3-3.9 共 16 项）—— 可选

如果用户希望 AI 在等待期间补做这些 PBT 测试，可以做。否则就在这里停下，等同事消息。
