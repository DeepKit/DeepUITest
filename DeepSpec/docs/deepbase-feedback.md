# DeepBase 反馈：DeepSpec 接入过程中遇到的问题

> 日期：2026-05-15
> 来源：DeepSpec 首次接入 DeepBase/DeepShell

---

## 问题 1：FireDAC SQLite 驱动链接未在文档中明确

**现象**：运行时报 "Object factory for class {3E9B315B-...} is missing. To register it, you can drop component [TFDPhysSQLiteDriverLink] into your project"

**根因**：DeepBase 使用 FireDAC + SQLite 作为 ConfigDB，但接入指南（`76.vcl.DeepShell-新VCL程序接入指南.md`）只说了引用 `DeepBase.Persistence.Manager.FireDAC`，没有说明还需要在 .dpr 中加入 FireDAC SQLite 驱动单元。

**实际需要的 uses**：
```pascal
FireDAC.VCLUI.Wait,
FireDAC.Comp.UI,
FireDAC.Phys.SQLite,
FireDAC.Phys.SQLiteDef,
FireDAC.Stan.ExprFuncs,
FireDAC.Stan.Def,
FireDAC.DApt,
DeepBase.Manager,
DeepBase.Persistence.Manager.FireDAC,
```

**建议**：
1. 在 `76.vcl.DeepShell-新VCL程序接入指南.md` §3.1 标准初始化中，把完整的 FireDAC uses 列表写出来，不要只写 `DeepBase.Persistence.Manager.FireDAC`。
2. 或者让 `DeepBase.Persistence.Manager.FireDAC` 的 initialization 段自动注册 SQLite 驱动（内部 uses `FireDAC.Phys.SQLite`），这样下游不需要知道底层用的是什么数据库引擎。

---

## 问题 2：root.txt 位置和 DB 文件创建逻辑不清晰

**现象**：首次运行报 "ConfigDB Not Found"，即使 root.txt 存在。

**根因**：
1. 文档说 "root.txt 位于 EXE 同目录"，但没有说明 DeepBase 是否会自动创建 DB 文件。
2. 如果 DB 文件不存在，DeepBase 应该自动创建空 SQLite DB 并初始化 schema，而不是报错。
3. 如果手动创建了一个无效的 SQLite 文件（0 字节或格式错误），DeepBase 会把它标记为 corrupted 并重命名，但不会自动创建新的有效 DB。

**建议**：
1. 在接入指南中明确说明：首次运行时 DeepBase 是否自动创建 `{AppName}Config.db`？如果是，下游不需要预创建。如果不是，提供创建脚本。
2. 当 DB 文件不存在时，DeepBase.Manager.InitializeEx 应该自动创建空 DB 并返回成功，而不是返回错误。这是最常见的首次运行场景。

---

## 问题 3：.dproj 搜索路径配置对 AI 不友好

**现象**：AI 生成的 .dproj 在 msbuild 中编译通过，但 IDE 中报 "Unit not found"。

**根因**：
1. Delphi IDE 对 .dproj 中 PropertyGroup 的 Condition 匹配规则和 msbuild 不完全一致。
2. `DCC_UnitSearchPath` 放在 `Condition="'$(Base)'=='true'"` 中时 msbuild 能找到，但 IDE 可能需要它在 `Condition="'$(Base)'!=''"` 中。
3. `.dproj.local` 文件会覆盖 .dproj 中的设置，但 AI 不知道这个文件的存在。

**建议**：
1. 提供一个 `.dproj` 模板文件（或 scaffold 脚本），让新项目从模板生成，而不是让 AI 从零写 XML。
2. 在 VCLDeepShellDemo 的 README 中说明：如果 AI 生成 .dproj，应该参考 Demo 的格式，特别是 PropertyGroup Condition 的写法。
3. 考虑提供一个 `deepbase-scaffold.ps1` 脚本，输入项目名和路径，自动生成 .dpr + .dproj + root.txt。

---

## 问题 4：RegisterStructureProvider 等方法是 protected

**现象**：从外部单元调用 `TDeepMainForm.RegisterStructureProvider` 报 E2362 "Cannot access protected symbol"。

**根因**：接入指南 §5 示例代码把 Provider 注册写在 `RegisterProviders` override 内部（同类内可访问 protected），但如果下游把注册逻辑拆到独立单元，就需要用 class helper 或 type cast hack。

**建议**：
1. 把 `RegisterStructureProvider` / `RegisterMainViewProvider` / `RegisterInspectorProvider` 改为 public。它们是下游必须调用的 API，没有理由是 protected。
2. 或者在接入指南中明确说明：Provider 注册必须在 `RegisterProviders` override 内部完成，不能拆到外部单元。

---

## 问题 5：DeepShell Demo 中 Debug 是 Cfg_2 而非 Cfg_1

**现象**：AI 按常规假设 Debug=Cfg_1、Release=Cfg_2 生成 .dproj，但 DeepShell Demo 中 Release=Cfg_1、Debug=Cfg_2。

**根因**：Delphi IDE 生成 .dproj 时 Cfg 编号取决于创建顺序，不是固定的。但 AI 没有这个上下文。

**建议**：
1. 在 scaffold 模板中固定 Debug=Cfg_2、Release=Cfg_1（与 Demo 一致）。
2. 或者在文档中说明这个约定。

---

## 问题 6：DB protection 机制在首次创建 DB 后立即标记为 corrupted

**现象**：首次运行时 DeepBase 创建了 `DeepSpecConfig.db`（4096 字节有效 SQLite），但 DB protection 机制立即检测到"corruption"并重命名为 `.corrupted_*`，然后报错。

**根因**：DeepBase.Manager 的 DB protection 逻辑在 schema 初始化完成前就执行了完整性校验，导致刚创建的空 DB 被误判为 corrupted。

**影响**：不影响运行（in-memory fallback 正常工作），但每次首次启动都会弹出错误对话框，用户体验差。

**建议**：
1. 首次创建 DB 时跳过 protection 校验（因为还没有 schema 可以校验）。
2. 或者在 InitializeEx 中区分"DB 不存在需要创建"和"DB 存在但损坏"两种情况，前者不报错。
3. VCLDeepShellDemo 也有这个问题，说明不是 DeepSpec 特有的。

---

*本文件按 MVP 实施蓝图 §16 的要求维护，记录 DeepSpec 实践 DeepBase 过程中的反馈。*
