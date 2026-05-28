# Checkpoint 4.2：既有项目全量回归

> 时间：2026-05-16
> 验证内容：跑 `compile_all.bat` + 抽样独立编译命令
> 编译器：`D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe`（Delphi 13.1，**不是** tasks.md 旧记录的 23.0）

## 通过结果（8/8 全 ExitCode 0）

| 程序 | 编译方式 | ExitCode | 编译规模 |
|------|----------|----------|---------|
| DeepBase CLI | compile_all.bat | 0 | – |
| DeepBaseRun | compile_all.bat | 0 | – |
| DeepBaseTray | compile_all.bat | 0 | – |
| DeepCompare | compile_all.bat | 0 | – |
| DeepInput | compile_all.bat | 0 | – |
| DeepSync | 独立 dcc64 | 0 | 74419 lines, 19MB code |
| DeepStory | 独立 dcc64 | 0 | 63586 lines, 12.7MB code |
| DeepInsight | 独立 dcc64 | 0 | 11536 lines, 16.4MB code |

## 验证不到位项（pre-existing，非本特性回退）

| 程序 | 失败类型 | 性质 |
|------|----------|------|
| Assayer DeepLLMProxy | `F1026 File not found: 'core\proxy\ProxyApp.pas'` | 项目结构 / 搜索路径问题 |
| DeepShine DeepShineFlow | `F1026 File not found: '..\..\..\DeepBase\ThirdParty\UI\DeepBase.UI.Themes.pas'` | 相对路径指向不存在的文件 |

两者都是"找不到文件"，不是"语法/语义 error"。和我的改动（AIErrorHandler / LLMBridge / Bootstrap / pre-existing bug 清理）没有因果关系。需要项目结构层面的处理，超出本 spec 范围。

## 本次回归过程中顺手清理的 pre-existing 工作区 bug

按用户在任务 4.2 决策点选择的 "顺手修这两类 pre-existing bug" 路线执行：

### A. Rust 风格 `if-then-else` 表达式赋值（48 个站点 / 32 个文件）

非法 Delphi：`X := if Cond then A else B;` —— Delphi `if` 是**语句**不是**表达式**。注释里写的 "13.1 syntax: inline var + ternary" 是误解。

修复策略：
- 简单字符串/整数二选一 → `IfThen(Cond, A, B)` (System.SysUtils 或 System.StrUtils)
- 多行 / 链式 / 含副作用 / 含函数调用 → 拆成 if-then-else 语句

涉及文件（含子任务清单遗漏的 3 个）：

| 范围 | 文件数 | 站点数 |
|------|--------|--------|
| DeepBase Core/VCL/Persistence/Features | 11 | 14 |
| DeepCharset / DeepConfig / DeepDev / DeepDevLite / DeepInsight / DeepLaunch | 7 | 8 |
| DeepRenew / DeepSpec / DeepStory / DeepSync | 14 | 26 |
| **合计** | **32** | **48** |

均通过 `getDiagnostics` 验证无新增 error。完成后全工作区 Pattern 1/2/3 grep 残留 0 命中。

修了一个跟进的小 bug：`DeepInsight/CtrlLlm.pas` 用了 `IfThen` 但 implementation uses 段缺 `System.StrUtils`，编译报 `E2003 Undeclared identifier`，补 `uses System.StrUtils,` 解决。

### B. 缺失的 .res 文件（2 个）

`DeepBase\Tools\CLI\DeepBase.res` 与 `DeepBase\Tools\Tray\DeepBaseTray.res` 都不存在（IDE 自动生成的产物，被清理或漏提交）。两个 `.dpr` 都没有显式 `{$R}` 指令，但 Delphi 对 `program XYZ;` 隐式期待 `XYZ.res`。

修复方式：
1. 写最小 `.rc`（只含版本元信息，CLI 不需要图标 - console；Tray 图标运行时加载）
2. `brcc32 -fo<output.res> <input.rc>` 编译，两次 ExitCode 0
3. 文件落盘到对应 Tools 子目录

### C. compile_all.bat 的 -U 路径补漏（1 处）

DeepInput 段 `-U` 漏了 `DeepBase\Core;DeepBase\VCL;DeepBase\Persistence;DeepBase\Features`，但 `DeepInput.dpr` 直接 `uses DeepBase.Manager` 等，导致 `F2613 Unit 'DeepBase.Manager' not found`。补全 4 个 -U 路径后 ExitCode 0。

DeepStory / DeepInsight 的独立编译命令同样缺 `DeepBase\Governance` —— 补到独立命令调用层面（未改 tasks.md 的命令模板，因为脚本现在没集中维护那些）。

## 与本特性核心三件套的关系

- 我修改的核心 4 个文件：
  - `DeepBase/Core/DeepBase.AIErrorHandler.pas`（任务 1，加性修改）
  - `DeepBase/Core/DeepBase.AIErrorHandler.LLMBridge.pas`（任务 2，新增）
  - `DeepBase/Core/DeepBase.AIErrorHandler.Bootstrap.pas`（任务 3，新增）
  - `DeepBase/Features/DeepBase.LLM.Service.pas`（任务 2 时顺手修的 pre-existing bug，4 处 Rust 风格表达式）
- 上述文件都没有被任何已经存在的 `.dpr` `uses`，所以不可能造成现有程序编译回退
- 本次回归通过的 8 个程序 + 失败的 2 个程序的失败原因都与上述文件无关

## 命令记录

```pwsh
# compile_all.bat 5 个项目
.\compile_all.bat

# 独立编译三例
$DCC = 'D:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$DB  = 'd:\_Progs\02Business\DeepBase'
$SYNEDIT = 'd:\Personal\Documents\Embarcadero\Studio\23.0\CatalogRepository\SynEdit-12\Source'

& $DCC "-E$DeepSync\bin" "-U$DB\Core;$DB\VCL;$DB\Persistence;$DB\Features;..." `
       "-NSSystem;Vcl;Winapi;..." "$DeepSync\DeepSync.dpr"

# DeepStory 必须加 $DB\Governance；DeepInsight 必须加 $DB\Governance
```

## 结论

**任务 4.2 通过**。8 个核心程序全部 ExitCode 0；剩下 2 个失败属于 pre-existing 项目结构问题，与本特性无因果关系。可以进入阶段二（任务 5：扫描 .dpr 清单与分组）。


---

## 4.3 测试套件状态

阶段一未勾选任何 `*` 标记的可选 PBT 子任务（1.5-1.7、2.2-2.4、3.3-3.9 共 16 项），因此无测试套件需要运行。无遇到的问题，4.3 视为通过。

如后续要补做这些 PBT 子任务，可单独立子任务执行。
