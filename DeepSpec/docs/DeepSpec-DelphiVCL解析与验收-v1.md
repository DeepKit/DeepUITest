# DeepSpec Delphi/VCL 解析与验收 v1

> 日期：2026-05-14  
> 来源：`发散讨论/` 中 Delphi/VCL 优先支持、DFM 解析策略、测试样例库和 MVP 验收讨论  
> 目的：把 Delphi/VCL 相关有用内容整理成增强能力规格。  
> 重要边界：DeepSpec 第一层是免费、通用的开发文档优化器，不能绑定在 Delphi + VCL 上；Delphi/VCL 是优先增强方向和样例验证场景。

---

## 1. 为什么保留 Delphi/VCL 优先增强

DeepSpec 第一层必须通用，面向所有开发者免费可用。但 Delphi/VCL 仍然值得作为优先增强方向，有四个现实理由：

1. 技术栈一致，验证成本低；
2. `.dfm` 天然适合生成视图树；
3. 老 Delphi 项目普遍存在文档缺失、窗体肥胖、交接困难；
4. Delphi 老项目 AI 改造准备，是一个差异化商业切口。

当前表述：

**DeepSpec 不只服务 Delphi，但 Delphi/VCL 是第一批最有视觉冲击力和商业差异化的样板。**

同时必须注意：

**Delphi/VCL 解析得到的是实现侧控件树或实现证据，不等同于 DeepSpec 第一层的需求侧视图树。**

第一层视图树应优先表达：

```text
功能树中的交付界面需求
```

DFM 解析用于辅助确认界面结构、发现已有 UI 线索、补充来源证据。

---

## 2. 支持文件

MVP 优先识别：

```text
.dpr      工程入口
.dproj    项目文件
.pas      单元与类
.dfm      VCL 窗体结构
.ini      配置
.res/.rc  资源
```

后续扩展：

```text
.fmx      FMX 窗体
.inc      Delphi include
.groupproj 工程组
```

---

## 3. 总解析原则

- 不做完整 Delphi 编译器；
- 不追求编译级准确；
- 轻量、稳健、可追溯；
- 所有解析结果都带来源；
- 解析失败也要成为问题记录；
- 先读出结构，再逐步提高理解深度。

---

## 4. `.dpr` 解析

提取：

```text
program 名
uses 引用的 pas 文件
Form 别名
Application.CreateForm 中的主窗体
```

用途：

- 识别主窗体；
- 关联 `.pas` 和 `.dfm`；
- 帮助视图树排序；
- 判断项目入口。

---

## 5. `.dproj` 解析

`.dproj` 是 XML。MVP 只轻量读取：

```text
项目名
项目 GUID
目标平台
配置
MainSource
DCCReference 文件
```

注意：

- 老项目 `.dproj` 可能不完整；
- 不应过度依赖 `.dproj`；
- 解析失败记录 warning，不阻断扫描。

---

## 6. `.pas` 解析

轻量文本解析：

- 识别 `unit` 名；
- 识别 `uses`；
- 识别类；
- `TForm` → `FormUnit`；
- `TFrame` → `FrameUnit`；
- `TDataModule` → `DataModule`；
- 识别事件处理器，如 `BtnOpenFolderClick`、`actExportExecute`；
- 根据同名规则关联 DFM。

第一版不做：

- 完整 Pascal AST；
- 调用链分析；
- 泛型、条件编译的完整语义；
- 编译器级符号解析。

---

## 7. `.dfm` 解析

MVP 优先支持 text DFM。

支持关键字：

```text
object
inherited
inline
end
属性 key = value
```

核心算法：

```text
遇到 object/inherited/inline
  创建控件节点
  如果栈不空，挂到栈顶节点 children
  当前节点入栈

遇到 end
  当前节点出栈

遇到属性行
  写入当前节点属性
```

优先提取属性：

```text
Name
ClassName
Caption
Hint
Action
Align
Left
Top
Width
Height
ClientWidth
ClientHeight
TabOrder
Visible
Enabled
```

---

## 8. Caption 与 Action

Caption 处理：

- 普通字符串；
- 带 `&` 快捷键符号的字符串；
- 简单 `#数字` 编码串；
- 复杂编码保留原始值并记录 warning。

Action 处理：

- 控件有 `Action = actOpenFolder` 时，UI 节点记录 action；
- 后续从 ActionList 提取 Caption；
- Button/Menu/Action 指向同一事件时，功能树应合并来源。

---

## 9. Binary DFM 与 inherited DFM

Binary DFM：

- MVP 可不完整支持；
- 必须不崩溃；
- 记录 warning；
- 提示用户可在 Delphi 中保存为 text DFM。

Inherited DFM：

- MVP 当成 object 解析；
- 标记 `inherited = true`；
- 不尝试自动合并父窗体 DFM。

---

## 10. 中间模型

### 10.1 项目模型

```pascal
TDelphiProjectModel = class
public
  ProjectPath: string;
  DprFiles: TArray<string>;
  DprojFiles: TArray<string>;
  Units: TArray<TDelphiUnitModel>;
  Forms: TArray<TDelphiFormModel>;
end;
```

### 10.2 单元模型

```pascal
TDelphiUnitModel = class
public
  UnitName: string;
  FilePath: string;
  RelativePath: string;
  UsesUnits: TArray<string>;
  Classes: TArray<string>;
  Methods: TArray<string>;
  IsFormUnit: Boolean;
  FormClassName: string;
  DfmFilePath: string;
end;
```

### 10.3 窗体模型

```pascal
TDelphiFormModel = class
public
  FormName: string;
  FormClassName: string;
  PasFilePath: string;
  DfmFilePath: string;
  RootControl: TUIControlModel;
end;
```

### 10.4 控件模型

```pascal
TUIControlModel = class
public
  Id: string;
  Name: string;
  ClassName: string;
  Caption: string;
  Hint: string;
  ActionName: string;
  Parent: TUIControlModel;
  Children: TArray<TUIControlModel>;
  SourceFile: string;
  SourceLine: Integer;
  Align: string;
  Left: Integer;
  Top: Integer;
  Width: Integer;
  Height: Integer;
end;
```

---

## 11. 视图树生成

节点显示格式：

```text
控件名 : 控件类型 [Caption]
```

示例：

```text
TMainForm
├─ TopPanel : TPanel
│  ├─ BtnOpenFolder : TButton [打开文件夹]
│  └─ BtnExport : TButton [导出报告]
├─ MainBrowser : TEdgeBrowser
└─ StatusBar : TStatusBar
```

多个窗体排序：

1. `.dpr` 中 `Application.CreateForm` 顺序；
2. 文件名；
3. 窗体名。

---

## 12. 模块树生成

第一版以目录为主，目录下挂 `.pas` 文件。

Unit 类型：

```text
FormUnit
FrameUnit
DataModule
ClassUnit
ModelUnit
ServiceUnit
Unknown
```

模块树价值：

- 发现主窗体过重；
- 发现 UI 层和业务逻辑混杂；
- 给 AI 提供“功能应该写到哪里”的边界。

---

## 13. 功能树来源

功能树有推断成分，必须标记来源和置信度。

来源可信度建议：

| 来源 | 可信度 |
|---|---:|
| Action Caption | 0.95 |
| Menu Caption | 0.92 |
| Button Caption | 0.90 |
| ToolButton Caption/Hint | 0.85 |
| Event Handler | 0.70 |
| README 标题 | 0.65 |
| TODO | 0.45 |
| CHANGELOG | 0.50 |
| 方法名推断 | 0.40 |

去重规则：

- 去掉 `&` 快捷键符号后同名合并；
- Action/Button/Menu 指向同一事件时合并；
- 同一来源多次出现时提高置信度；
- 保留所有来源引用。

---

## 14. 解析问题分级

| 级别 | 示例 |
|---|---|
| Info | 发现项目、发现 DFM、解析完成。 |
| Warning | Binary DFM、Form 单元未找到 DFM、Caption 解码不完整。 |
| Error | DFM object/end 不匹配、文件读取失败、编码读取失败。 |
| Fatal | 项目目录无法访问。应尽量避免。 |

所有问题应进入：

- 底部日志；
- 问题页；
- 节点探查窗；
- `doc-issues.yaml` 或 `parse-issues.yaml`。

---

## 15. 样例项目库

### Sample01_MinimalVCL

包含一个主窗体、一个按钮、一个菜单、一个状态栏。

验收：识别 Delphi 项目、1 个 DFM、视图树、模块树、按钮 Caption 候选功能。

### Sample02_MultiForms

包含 Forms、Core、Render 等目录。

验收：视图树按 Form 分组；模块树按目录分组。

### Sample03_ComplexUI

包含 Panel、Splitter、PageControl、TabSheet、TreeView、ListView、ActionList、MainMenu、ToolBar、StatusBar、TEdgeBrowser。

验收：正确处理 object/end 栈，识别 PageControl/TabSheet 层级、按钮、菜单、Action。

### Sample04_DocsRich

包含 README、需求说明、CHANGELOG、TODO、AGENTS.md、CLAUDE.md、config.yaml。

验收：能分类文档和 AI 规则文件，并从文档标题提取候选功能。

### Sample05_BrokenProject

包含缺少 dproj、只有 pas 没有 dfm、损坏 dfm、binary dfm、乱码文件、超大文件、未知扩展名。

验收：不能崩溃，必须记录问题并显示在问题页和日志里。

---

## 16. Delphi/VCL MVP 验收

打开一个 Delphi/VCL 项目后，DeepSpec 应做到：

1. 识别 `.dpr/.dproj/.pas/.dfm`；
2. 读取 text DFM 控件层级；
3. 生成视图树；
4. 生成模块树；
5. 从 Caption/Menu/Action/事件名生成候选功能；
6. 每个节点显示来源；
7. Binary DFM 不崩溃；
8. 损坏 DFM 进入问题清单；
9. 探查窗显示当前节点属性；
10. 能生成给原 AI 工具的节点修正 Prompt。
