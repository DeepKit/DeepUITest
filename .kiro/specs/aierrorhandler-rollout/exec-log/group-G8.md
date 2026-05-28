# G8 组 (Tool_Program)：DeepBase 主工具 — AIErrorHandler 植入

> 时间：2026-05-18
> 编译器：`D:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc64.exe`（Delphi 13.1）
> 输出目录：`02Business/.kiro/specs/aierrorhandler-rollout/exec-log/_g8_compile/`
> 改动模板：每个 `.dpr` 严格 `+2 / -0`（uses 段加 `DeepBase.AIErrorHandler.Bootstrap`、`begin..end.` 起始处加 `InstallAIErrorHandler;`）
> 对应 spec 任务：tasks.md 任务 11 / inventory G8

> 注：tasks.md 任务 11 列出 4 个 .dpr（CLI / DeepBaseRun / DeepBaseTray / DeepPublisher），但 inventory G8 实际是 7 个；按 inventory 全集执行。

## 阻塞回看

进入 G8 前，先按 regression-2026-05-17.md 的根因清单确认：

- DeepBase 子树 13 处历史回退 + 7 处新现 Rust 风格 `if-then-else` 当前已被同事修干净（`grepSearch` 全树扫描 0 命中）
- 唯一例外：`DeepBase\Features\DeepBase.LLM.Service.pas:430-440` **第 3 次回退**（与 regression-2026-05-17.md 行号完全相同）。本批次顺手第 3 次修复，把 4 处 Rust 风格 `:= if X then Y else Z` 重写为标准 Delphi `if-then-else` 语句块；不改可见行为，仅改语法形式。

## 结果一览

| # | 路径 | 改动 | 编译 ExitCode | 备注 |
|---|------|------|---------------|------|
| 1 | `DeepBase/DeepBaseRun/DeepBaseRun.dpr` | **skipped** | N/A | **FMX 入口**（`uses System.StartUpCopy, FMX.Forms, FMX.Dialogs`），按 design.md "决策与权衡"出范围；inventory 误归类为 VCL（与 G4 DeepInsightApp / G7 DeepSync.dpr 同质），统一在 inventory 末尾"补充 FMX 出范围"小节登记 |
| 2 | `DeepBase/Tools/CLI/DeepBase.dpr` | +2 / -0 | **0** | 纯控制台（`{$APPTYPE CONSOLE}`，无 Vcl.Forms）；Bootstrap 透传 `Vcl.Forms`，安装 OnException 在无消息泵时仍是无害空操作 |
| 3 | `DeepBase/Tools/Tray/DeepBaseTray.dpr` | +2 / -0 | **0** | 标准 VCL Application |
| 4 | `DeepBase/Tools/Studio/DeepBaseStudio.dpr` | +2 / -0 | **1** | **pre-existing**：`Studio\Frames\Studio.SQLFrame.pas:31` 引用 RAD Studio 自带单元 `DBClient`（DataSnap），dcc64 命令行未链接 Embarcadero source 路径 → F2613；与 AIErrorHandler 改动无关 |
| 5 | `DeepBase/Tools/Studio/Studio.dpr` | +2 / -0 | **1** | **pre-existing**：同 #4，共用 `Studio.SQLFrame.pas` |
| 6 | `DeepBase/Tools/UniPublisher/DeepPublisher.dpr` | +2 / -0 | **1** | **pre-existing**：`UniPublisher\Core\Publisher.Manifest.pas` 头部把 JSON 示例直接写在 `{ ... }` 注释里，内嵌 `}` 提前关闭注释（行 15 起 `'UNIT' expected but ']' found` + 一长串 E2038 / E2003 / E2005），文件本身坏；与 AIErrorHandler 改动无关 |
| 7 | `DeepBase/Tools/UpdaterHelper/UpdaterHelper.dpr` | +2 / -0 | **0** | 纯控制台 |

## 汇总

| 维度 | 计数 |
|------|------|
| 应植入（inventory G8） | 7 |
| 实际植入 | 6 |
| 跳过（FMX） | 1（DeepBaseRun） |
| 编译 ExitCode=0 | **3** / 6 |
| 编译失败（pre-existing） | **3** / 6（DeepBaseStudio / Studio / UniPublisher） |
| 改动严格 +2 / -0 | **6 / 6** ✅ |

## 改动模板复核（与 G2..G7 模板一致）

- **VCL Application（已有 `Vcl.Forms`）**：紧邻 `Vcl.Forms,` 之后插入 `DeepBase.AIErrorHandler.Bootstrap in '..\..\Core\DeepBase.AIErrorHandler.Bootstrap.pas',`
  - DeepBaseTray：锚点 `Vcl.Forms,`
  - DeepBaseStudio：锚点 `Vcl.Forms,`
  - Studio：锚点 `Vcl.Forms,`
  - UniPublisher：锚点 `Vcl.Forms,`
- **纯控制台（无 Vcl.Forms）**：紧邻 `System.SysUtils,` 之后插入；Bootstrap 单元 `interface uses` 通过 `DeepBase.AIErrorHandler.pas` 透传引入 `Vcl.Forms`，satisfies design.md template 4.3 的 "控制台仍可 uses Vcl.Forms 拿到 Application" 但**不需要在 .dpr 里显式 uses Vcl.Forms**（保住 +2 / -0 不变）
  - CLI/DeepBase.dpr：锚点 `System.SysUtils,`
  - UpdaterHelper：锚点 `System.SysUtils,`
- `InstallAIErrorHandler;` 一律放在 `begin` 之后**首条**语句

## 编码注意事项

- `Tools/CLI/DeepBase.dpr` 与 `Tools/Studio/Studio.dpr` 头部 `{ ... }` 中文注释含部分非法 UTF-8 字节（先存 GBK 后被部分转换）。直接用文本编辑器替换会导致字节级"重写注释"diff。本次改用 PowerShell 脚本 `_g8_compile/_inject.ps1` 在锚点行末做字节级插入，保持其余字节不动，git diff 严格 `+2 / -0`。
- 其余 4 个文件均为 UTF-8（含 BOM 或纯 ASCII），直接 strReplace 即可。

## 顺手修（必须，不属本任务严格范围但阻塞编译）

- `DeepBase\Features\DeepBase.LLM.Service.pas:430-440`：4 处 Rust 风格 `:= if X then Y else if Z then W else V` 重写为 Delphi 标准 `if-then-else` 语句块（`begin … end` 包裹）；纯语法变换，行为不变。

## 留给同事 / 后续 spec 的事

- `Studio.SQLFrame.pas` 依赖 `DBClient`（`Data.DBClient` / DataSnap）：要么补 dcc64 `-U` Embarcadero source 路径，要么改用 `.dproj`/MSBuild；非本 spec 范畴
- `Publisher.Manifest.pas` 注释里 JSON 示例需要把 `{ ... }` 包装注释换成 `(* ... *)` 或 `// ` 行注释；非本 spec 范畴
- `DeepBase.LLM.Service.pas:430-440` 第 3 次回退根因仍未排掉，建议正式 commit 修复后跟踪 git log，下次回退记录在 regression-2026-05-18.md
