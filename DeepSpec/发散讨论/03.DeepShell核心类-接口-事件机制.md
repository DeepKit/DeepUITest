# DeepShell 核心类、接口与事件机制

## 1. 设计目标

DeepShell 是通用桌面标准壳，不直接做业务。它提供主窗体、左右悬浮窗、顶部可折叠摘要区、底部可折叠信息区、当前上下文、命令系统、事件总线、布局保存和 Provider 接入机制。

## 2. 核心类

### TDeepShellMainForm

主窗体。负责工具栏、顶部摘要区、中部主工作区、底部信息区、打开/隐藏左右悬浮窗、接收上下文变化、协调主内容显示。不负责具体业务扫描、树生成、属性计算或 AI 调用。

### TDeepShellStructureWindow

左侧悬浮结构窗。负责显示结构树、切换结构页、搜索节点、过滤节点、最近节点、异常节点、节点右键菜单和节点选择事件。

### TDeepShellInspectorWindow

右侧悬浮探查窗。负责当前对象属性、状态、来源、关联、问题、决定、变更、备注。

### TDeepShellTopPanel

顶部可折叠摘要区。负责项目摘要、扫描统计、当前基准、最近变更、当前任务等。

### TDeepShellBottomPanel

底部可折叠信息区。负责状态、日志、问题、错误、操作记录、变更记录、调试信息。

### TDeepShellContext

当前上下文对象。它回答当前用户选中了什么，主窗体正在展示什么，当前对象属于哪个项目，它是什么类型。

```pascal
TDeepShellContext = class
public
  ProjectId: string;
  ProjectPath: string;
  ObjectId: string;
  ObjectType: string;
  ObjectName: string;
  SourceFile: string;
  SourceLine: Integer;
  ViewId: string;
  ViewType: string;
  ExtraData: TObject;
end;
```

### TDeepShellCommandManager

命令管理器。所有按钮、菜单、快捷键、右键菜单都走命令。

常见命令：OpenFolder、RescanProject、ShowStructureWindow、ShowInspectorWindow、ShowLogPanel、ConfirmBaseline、ExportReport、CopyForAI、OpenSourceFile。

### TDeepShellEventBus

事件总线。负责主窗体、悬浮窗、底部日志、业务模块之间通信。

常见事件：ContextChanged、ObjectSelected、ProjectOpened、ProjectScanned、TreeNodeSelected、MainViewChanged、IssueAdded、LogAdded、BaselineConfirmed、LayoutChanged。

### TDeepShellLayoutManager

布局管理器。负责保存和恢复主窗体位置、左右悬浮窗位置、窗口打开状态、置顶/锁定状态、顶部区折叠状态、底部区折叠状态、各 PageControl 当前 Tab。

原则：窗口布局属于本机配置，项目状态属于项目目录。

## 3. 核心接口

### IShellStructureProvider

```pascal
IShellStructureProvider = interface
  function GetTreeNames: TArray<string>;
  function GetTreeRoot(const ATreeName: string): TObject;
  function GetNodeChildren(ANode: TObject): TArray<TObject>;
  function GetNodeDisplayText(ANode: TObject): string;
end;
```

### IShellInspectorProvider

```pascal
IShellInspectorProvider = interface
  function GetProperties(AObject: TObject): TArray<TShellProperty>;
  function GetRelations(AObject: TObject): TArray<TShellRelation>;
  function GetIssues(AObject: TObject): TArray<TShellIssue>;
end;
```

### IShellMainViewProvider

```pascal
IShellMainViewProvider = interface
  function GetViewForObject(AObject: TObject): TShellViewInfo;
end;
```

### IShellLogProvider

```pascal
IShellLogProvider = interface
  procedure AddLog(const ALevel, AMessage: string);
  function GetLogs: TArray<TShellLogItem>;
end;
```

### IShellCommandProvider

```pascal
IShellCommandProvider = interface
  function GetCommands: TArray<TShellCommand>;
  procedure ExecuteCommand(const ACommandId: string; AContext: TDeepShellContext);
end;
```

## 4. 事件类型

```pascal
TDeepShellEventKind = (
  sekProjectOpened,
  sekProjectClosed,
  sekContextChanged,
  sekObjectSelected,
  sekViewChanged,
  sekTreeChanged,
  sekIssueAdded,
  sekLogAdded,
  sekBaselineConfirmed,
  sekLayoutChanged
);
```

事件对象：

```pascal
TDeepShellEvent = record
  Kind: TDeepShellEventKind;
  ObjectId: string;
  ObjectType: string;
  MessageText: string;
  Payload: TObject;
end;
```

## 5. 典型事件流

### 选中结构节点

```text
StructureWindow.NodeSelected
  ↓
EventBus.Publish(ObjectSelected)
  ↓
ShellContext 更新
  ↓
MainForm 显示主内容
  ↓
InspectorWindow 显示属性
  ↓
BottomPanel 显示相关问题
```

### 打开项目

```text
MainForm.OpenProject
  ↓
CommandManager.Execute(OpenProject)
  ↓
业务模块打开项目
  ↓
EventBus.Publish(ProjectOpened)
  ↓
TopPanel 更新摘要
  ↓
StructureWindow 加载树
  ↓
MainView 显示扫描报告
```

### 扫描完成

```text
ProjectScanner.ScanFinished
  ↓
EventBus.Publish(ProjectScanned)
  ↓
TopPanel 更新统计
  ↓
StructureWindow 刷新三棵树
  ↓
MainView 显示 scan-report.html
  ↓
BottomPanel 显示扫描日志
```

## 6. 结论

DeepShell 不直接做业务，而是提供主工作区、结构窗、探查窗、上下折叠区、命令、事件、上下文和布局记忆；具体业务由各产品实现 Provider 接入。
