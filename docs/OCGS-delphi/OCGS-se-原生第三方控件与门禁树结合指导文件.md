# OCGS-se：原生/第三方控件与门禁树结合指导文件

> 版本：v1.0  
> 主题：AI 面向门开发系统中的 Delphi 原生控件、FMX/VCL 控件、第三方控件与 AccessGateTree 的对应关系  
> 适用对象：AI 生成 Delphi 软件、人类微调、OCGSRuntime / AccessGateTree / OutputSet / PurposeSet / ProjectionSet / AbilitySet / DueSet 落地  
> 核心句：控件不是功能，控件是门的投射体；事件不是业务，事件是门的触发器；第三方控件不是例外，也必须通过门禁树接入。

---

## 一、为什么需要这份文件

前面已经形成了：

```text
OutputSet → AccessGateTree → PurposeSet / ProjectionSet / AbilitySet / DueSet
```

的面向门开发流程。

但还缺一个关键文件：

> 原生控件、第三方控件、不可见组件、API 能力，如何与门禁树结合？

如果没有这份对应表，AI 很容易犯以下错误：

1. 把 `TButton` 当功能；
2. 把 `OnClick` 当业务入口；
3. 把 `TPageControl` 当普通容器，而不是空间门；
4. 把 `TDBGrid` 的编辑、删除、保存写回 View；
5. 把 `SynEdit`、`VirtualTreeView`、`Cef4Delphi` 等第三方控件直接暴露成逻辑中心；
6. 把拖拽、双击、右键菜单、快捷键散落在事件里；
7. 忘记 View / Controller / Model / Data 分层；
8. 忘记 UniBase 必用能力；
9. 忘记 FMX 设计时优先；
10. 生成后无法二次修改。

所以本文件的目标是：

> 建立一张 AI 可执行的“控件—门禁—属集”对应表，让 AI 知道每种控件在 OCGS-se 中应该归入哪类 Gate、对应哪些事件、投射哪些状态、调用哪些 Ability、是否需要 DueSet，以及应如何生成代码。

---

## 二、总原则

### 1. 控件不是功能

错误理解：

```text
按钮 = 保存功能
DBGrid = 数据管理功能
PageControl = 页面功能
SynEdit = 代码编辑功能
```

正确理解：

```text
按钮 = ControlGate 的投射体
DBGrid = DataGridGate / RecordSelectGate 的投射体
PageControl = TabSpaceGate / PageRegionGate 的投射体
SynEdit = CodeEditorGate 的投射体
```

控件只是门的“身体”。

真正的软件结构来自：

```text
OutputSet
AccessGateTree
PurposeSet
AbilitySet
DueSet
ContextSet
StateSet
FeedbackSet
TraceSet
```

---

### 2. 事件不是业务

错误：

```pascal
procedure TMainForm.btnSaveClick(Sender: TObject);
begin
  SaveData;
end;
```

正确：

```text
btnSave.OnClick
  → Runtime.EnterGate('main.editor.file.save')
```

事件只能做：

```text
PreviewGate
EnterGate
CancelGate
RouteGate
```

不能直接做业务、查数据库、写文件、删记录、执行 SQL。

---

### 3. UI 是投射，不是宿主

Form、Frame、Panel、Button、MenuItem、TAction、TabSheet 都属于投射面。

它们不拥有功能，只承接：

```text
AccessGateState
PurposeState
DueProjectionState
FeedbackState
RuntimeState
```

---

### 4. 设计时优先

控件应优先在 `.fmx` / `.dfm` 中设计和生成。

AI 不应因为“没打开 IDE”就在 `.pas` 中大量 `TButton.Create(nil)`。

面向门开发中，控件参数来源于：

```text
Projection 参数表
```

然后生成 `.fmx/.dfm`。

---

### 5. View 不得越层

View 层只做投射和门触发：

```text
View/Form/Frame
  → Runtime.EnterGate / PreviewGate
  → Controller / AbilityProvider
  → Model / Data
```

View 不直接：

```text
访问数据库
执行 SQL
引用全局 DM
写业务规则
做高风险判断
```

---

## 三、核心对象关系

### 1. OCGSRuntime

运行时入口。

```text
OCGSRuntime
  → AccessGateTree
    → ProjectionSet
    → PurposeSet
    → AbilitySet
    → DueSet
    → ContextSet
    → StateSet
    → EventSet
    → ResourceSet
    → FeedbackSet
    → TraceSet
```

---

### 2. AccessGateNode

每个控件或界面入口最终应映射为一个 AccessGateNode。

```text
GateKey:
GateType:
ProjectionRef:
PurposeRef:
AbilityRefs:
DueRefs:
ContextRefs:
StateRefs:
FeedbackRef:
TracePolicy:
```

---

### 3. ProjectionNode

ProjectionNode 是控件参数表中的投射节点。

```text
ProjectionKey:
ComponentClass:
ParentProjection:
GateRef:
Caption:
Hint:
Left:
Top:
Width:
Height:
Align:
Anchors:
VisibleBinding:
EnabledBinding:
Style:
```

---

### 4. ComponentAdapter

为每种原生或第三方控件定义适配器。

```text
ComponentAdapter = 控件类型与门禁树之间的翻译器
```

它负责：

```text
1. 把控件事件转成 PreviewGate / EnterGate；
2. 把 GateState 投射回控件属性；
3. 把控件数据包装成 Context；
4. 把第三方控件的复杂事件降级为门事件；
5. 保证 AI 不直接把业务写进控件事件。
```

---

## 四、原生可见控件对应表

### 1. TForm / 主窗体 / 子窗体

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | `TForm` / FMX Form |
| GateType | `WindowGate` |
| Projection 类型 | `ProjectionSurface` |
| 典型事件 | `OnCreate`, `OnShow`, `OnCloseQuery`, `OnResize` |
| 事件降级 | `EnterGate`, `RefreshGate`, `LeaveGate` |
| 不可做 | 不写业务逻辑，不直接访问 Data 层 |
| 典型 GateKey | `main.window`, `settings.window`, `evidence.window` |

#### AI 规则

```text
Form 只能作为 WindowGate 的投射面。
Form 不得成为业务中心。
Form 的事件只能调用 Runtime 或 Controller。
```

---

### 2. TFrame

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | `TFrame` |
| GateType | `FrameGate` / `PanelGate` |
| Projection 类型 | `ProjectionPanel` |
| 典型用途 | 可复用区域、功能面板、状态面板 |
| 典型事件 | `OnEnter`, `OnExit`, 自定义刷新 |
| 事件降级 | `EnterGate`, `RefreshGate` |
| 典型 GateKey | `main.output_review.frame`, `main.editor.frame` |

#### AI 规则

```text
Frame 是推荐拆分单位。
超大 Form 必须向 Frame 迁移。
Frame 可以声明 ProjectionRef，但不直接执行业务。
```

---

### 3. TPanel / TLayout / TGroupBox

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | `TPanel`, `TLayout`, `TGroupBox` |
| GateType | `RegionGate` / `PanelGate` |
| Projection 类型 | `ProjectionRegion` |
| 典型用途 | 区域门、布局门、分组门 |
| 事件 | 通常无业务事件 |
| 状态投射 | Visible, Enabled, Width, Height, Align |
| 典型 GateKey | `main.right_panel`, `main.output_review.region` |

#### AI 规则

```text
Panel 不是功能容器，而是空间门。
Panel 上的子控件必须有各自 GateKey。
```

---

### 4. TButton / TSpeedButton / TToolButton

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | Button 类 |
| GateType | `ControlGate` |
| Projection 类型 | `ProjectionControl` |
| 典型事件 | `OnClick` |
| 事件降级 | `EnterGate(GateKey)` |
| 状态投射 | Caption, Hint, Enabled, Visible, Style, Icon |
| 典型 GateKey | `main.output_review.quality_check.run` |

#### AI 规则

```text
Button 不得直接调用 Handler。
Button.OnClick 只能调用 Runtime.EnterGate。
Caption / Hint / Enabled 来自 Projection 参数和 GateState。
```

---

### 5. TMenuItem / PopupMenu Item

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | MenuItem |
| GateType | `MenuGate` / `CommandGate` |
| Projection 类型 | `ProjectionCommand` |
| 典型事件 | `OnClick` |
| 事件降级 | `EnterGate(GateKey)` |
| 状态投射 | Caption, Enabled, Visible, Checked, Shortcut |
| 典型 GateKey | `menu.file.export_pdf` |

#### AI 规则

```text
菜单项和按钮可以指向同一个 Gate 或同一个 Purpose。
不要为菜单和按钮写两套业务。
```

---

### 6. TAction / TActionList

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | `TAction`, `TActionList` |
| GateType | `ActionGate` / `CommandGate` |
| Projection 类型 | `ProjectionBinding` |
| 典型事件 | `OnExecute`, `OnUpdate` |
| 事件降级 | `OnExecute → EnterGate`, `OnUpdate → BindGateState` |
| 状态投射 | Caption, Hint, Enabled, Visible, Checked, Shortcut |
| 典型 GateKey | `action.file.save` |

#### AI 规则

```text
TActionList 是 ProjectionBinding 容器，不是业务中心。
TAction.OnExecute 不得写业务。
TAction.OnUpdate 不得手写复杂状态判断，应绑定 GateState。
```

---

### 7. TEdit / TMemo / TComboBox / TCheckBox / TRadioButton

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | 输入控件 |
| GateType | `InputGate` / `StateEditGate` |
| Projection 类型 | `ProjectionInput` |
| 典型事件 | `OnChange`, `OnExit`, `OnKeyDown` |
| 事件降级 | `UpdateContext`, `PreviewGate`, `ValidateGate` |
| 状态投射 | Text, Checked, Items, Enabled, Visible |
| 典型 Output | `form.input.updated`, `config.value.changed` |

#### AI 规则

```text
输入控件不直接保存数据。
OnChange 只更新 Context/State，保存必须经过 SaveGate。
高风险配置修改必须进入 DueSet。
```

---

### 8. TListView / TListBox

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | 列表控件 |
| GateType | `ListGate` / `ItemSelectGate` |
| Projection 类型 | `ProjectionList` |
| 典型事件 | `OnItemClick`, `OnChange`, `OnDblClick` |
| 事件降级 | `EnterGate(selected_item_gate)` |
| 状态投射 | Items, Selected, Enabled, EmptyState |
| 典型 GateKey | `main.document_list.item.select` |

#### AI 规则

```text
列表项选择只是 ContextGate。
双击打开必须进入 OpenGate。
不要在 OnDblClick 中写加载业务。
```

---

### 9. TTreeView

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | 树控件 |
| GateType | `TreeGate` / `TreeNodeGate` |
| Projection 类型 | `ProjectionTree` |
| 典型事件 | `OnChange`, `OnDblClick`, `OnDragDrop`, `OnExpanding` |
| 事件降级 | `SelectGate`, `OpenGate`, `DropGate`, `ExpandGate` |
| 典型 GateKey | `main.project_tree.file_node.open` |

#### AI 规则

```text
TreeNode.Tag 不应成为业务中心。
节点类型应进入 ContextSet。
双击节点必须经过 FileTypeRouteGate 或 PurposeGate。
```

---

### 10. TPageControl / TTabSheet

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | PageControl / TabSheet |
| GateType | `PageSpaceGate` / `TabGate` / `DropGate` |
| Projection 类型 | `ProjectionPageSpace` |
| 典型事件 | `OnChange`, `OnDragOver`, `OnDragDrop` |
| 事件降级 | `SwitchTabGate`, `PreviewGate`, `EnterGate` |
| 状态投射 | ActivePage, TabVisible, Caption, Enabled |
| 典型 GateKey | `main.editor.tab.code.open` |

#### AI 规则

```text
TabSheet 是房间门，不是功能。
PageControl 的拖拽必须经过 DragGate → PayloadGate → RouteGate → TabDropGate。
```

---

### 11. TDBGrid / TStringGrid / TGrid

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | Grid |
| GateType | `DataGridGate` / `RecordSelectGate` / `CellEditGate` |
| Projection 类型 | `ProjectionDataGrid` |
| 典型事件 | `OnCellClick`, `OnDblClick`, `OnEditingDone`, `OnKeyDown` |
| 事件降级 | `SelectRecordGate`, `EditCellGate`, `SaveRecordGate` |
| 典型 Output | `record.detail.loaded`, `record.saved`, `record.deleted` |

#### AI 规则

```text
Grid 只做投射和选择上下文。
保存、删除、批量修改不能写在 Grid 事件里。
View 层不得直接访问数据库。
```

---

### 12. TImage / TPaintBox / TRectangle / Shape

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | 图像/绘制控件 |
| GateType | `PreviewGate` / `CanvasGate` / `ImageDropGate` |
| Projection 类型 | `ProjectionVisual` |
| 典型事件 | `OnPaint`, `OnClick`, `OnDragDrop` |
| 事件降级 | `PreviewGate`, `SelectGate`, `DropGate` |
| 典型 Ability | `image.load`, `image.render`, `canvas.draw` |

#### AI 规则

```text
绘制逻辑应进入 Ability/Renderer，不直接堆在 View 事件。
复杂绘制优先考虑 Skia4Delphi。
```

---

### 13. TStatusBar / TProgressBar / ActivityIndicator

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | 状态反馈控件 |
| GateType | `FeedbackGate` / `ProgressGate` |
| Projection 类型 | `ProjectionFeedback` |
| 输入来源 | FeedbackSet / RuntimeState / GateState |
| 典型状态 | Info, Warning, Error, Running, Completed |

#### AI 规则

```text
状态栏不直接生成业务消息。
状态栏显示来自 FeedbackSet。
```

---

### 14. TOpenDialog / TSaveDialog / Dialog

| 项目 | 面向门归属 |
|---|---|
| 控件类型 | Dialog |
| GateType | `DialogGate` / `FileSelectGate` / `ConfirmGate` |
| Projection 类型 | `ProjectionDialog` |
| 典型事件 | Execute 结果 |
| 事件降级 | `EnterGate`, `ConfirmGate`, `CancelGate` |
| 典型 Output | selected_file, save_path, user_confirmed |

#### AI 规则

```text
Dialog 只是门，不是 DueSet。
MessageDlg 不能替代 EvidenceGate / AccountabilityGate。
```

---

## 五、不可见组件对应表

### 1. TTimer

| 项目 | 面向门归属 |
|---|---|
| 组件 | TTimer |
| GateType | `TimerGate` / `ScheduledGate` |
| 所属 Set | EventSet |
| 事件 | OnTimer |
| 事件降级 | `Runtime.EnterGate(timer.gate_key)` |

#### AI 规则

```text
Timer 不直接写业务。
Timer 触发 ScheduledGate，再进入 Purpose。
```

---

### 2. TApplicationEvents

| 项目 | 面向门归属 |
|---|---|
| 组件 | TApplicationEvents |
| GateType | `AppEventGate` |
| 所属 Set | EventSet |
| 典型事件 | OnException, OnIdle, OnActivate |
| 事件降级 | `Runtime.EnterGate(app.event.xxx)` |

#### AI 规则

```text
异常必须走 UniBase.Logger / madExcept / TraceSet。
不得空 except。
```

---

### 3. TDataSource / DataSet 绑定

| 项目 | 面向门归属 |
|---|---|
| 组件 | TDataSource |
| 所属 Set | ContextSet / DataBindingSet |
| 用途 | 将当前记录投射为 Context |
| 不可做 | 不作为业务逻辑中心 |

#### AI 规则

```text
DataSource 只提供当前上下文。
DataSet.Post/Delete 不应从 View 直接触发。
```

---

### 4. TImageList / SVGIconImageList

| 项目 | 面向门归属 |
|---|---|
| 组件 | ImageList |
| 所属 Set | ResourceSet |
| 用途 | 图标、状态图标、门状态图标 |
| 关联 | ProjectionSet 通过 IconKey 引用 |

#### AI 规则

```text
控件不直接硬编码图标索引。
使用 ResourceKey / IconKey。
```

---

### 5. HTTPClient / REST Client

| 项目 | 面向门归属 |
|---|---|
| 组件 | HTTP 客户端 |
| 所属 Set | AbilityProvider |
| 典型 Ability | http.get, http.post, api.call |
| Due 可能 | RiskGate, EvidenceGate, RetryPolicy |

#### AI 规则

```text
HTTP 调用不写在 View。
API 能力注册到 AbilitySet。
```

---

### 6. FireDAC / 数据库连接

| 项目 | 面向门归属 |
|---|---|
| 组件 | FireDAC 连接、Query |
| 所属 Set | Data / AbilityProvider |
| 访问方式 | UniBase.DB.Pool / DoQry |
| 禁止 | View 直接 TFDQuery / SQL.Text := |

#### AI 规则

```text
数据库能力必须通过 Data 层或 UniBase.DB。
不得在 View 中直接查询。
不得裸 SQL。
```

---

## 六、第三方控件对应表

### 1. SynEdit

| 项目 | 面向门归属 |
|---|---|
| 第三方库 | SynEdit |
| 适用场景 | 代码编辑器、脚本编辑器、SQL 编辑器 |
| GateType | `CodeEditorGate` / `TextEditGate` |
| Projection 类型 | `ProjectionCodeEditor` |
| 常见事件 | OnChange, OnGutterClick, OnKeyDown |
| 事件降级 | `EditStateGate`, `CommandGate`, `SaveGate` |
| 典型 Ability | code.load, code.format, code.save, code.analyze |

#### AI 规则

```text
SynEdit 是代码编辑门的投射体。
代码保存、格式化、AI 修复必须通过 Purpose/Ability。
不要把代码处理逻辑写进 SynEdit 事件。
```

---

### 2. VirtualTreeView

| 项目 | 面向门归属 |
|---|---|
| 第三方库 | VirtualTreeView |
| 适用场景 | 大数据量树、项目树、对象树 |
| GateType | `VirtualTreeGate` / `NodeGate` |
| Projection 类型 | `ProjectionVirtualTree` |
| 常见事件 | OnGetText, OnFocusChanged, OnDblClick |
| 事件降级 | `SelectNodeGate`, `OpenNodeGate`, `RouteGate` |
| 典型 Ability | node.load_children, node.open, node.route |

#### AI 规则

```text
VirtualTreeView 的 NodeData 只是 Context，不是业务中心。
双击 / 右键必须进入 Gate。
```

---

### 3. Cef4Delphi

| 项目 | 面向门归属 |
|---|---|
| 第三方库 | Cef4Delphi |
| 适用场景 | Web 渲染、预览、内嵌浏览器 |
| GateType | `WebViewGate` / `BrowserGate` |
| Projection 类型 | `ProjectionWebView` |
| 常见事件 | OnBeforeBrowse, OnLoadEnd, JS Bridge |
| 事件降级 | `NavigateGate`, `WebCommandGate`, `BridgeGate` |
| Due 重点 | 外部 URL、脚本注入、文件访问、安全边界 |

#### AI 规则

```text
WebView 不是自由入口。
导航、下载、JS Bridge 必须有 BoundaryGate / RiskGate。
```

---

### 4. Skia4Delphi

| 项目 | 面向门归属 |
|---|---|
| 第三方库 | Skia4Delphi |
| 适用场景 | 图表、自定义绘制、高质量 2D |
| GateType | `VisualRenderGate` |
| Projection 类型 | `ProjectionCanvas` |
| 典型 Ability | chart.render, canvas.draw, diagram.render |
| ResourceSet | theme, palette, icon, vector |

#### AI 规则

```text
复杂绘制能力应注册为 Render Ability。
Skia 控件只投射渲染结果，不承载业务逻辑。
```

---

### 5. graphics32

| 项目 | 面向门归属 |
|---|---|
| 第三方库 | graphics32 |
| 适用场景 | 位图处理、图像编辑 |
| GateType | `ImageProcessGate` |
| Projection 类型 | `ProjectionImageEditor` |
| Ability | image.crop, image.resize, image.filter |

#### AI 规则

```text
图像处理属于 AbilitySet。
UI 只是预览和参数入口。
```

---

### 6. DUnitX

| 项目 | 面向门归属 |
|---|---|
| 第三方库 | DUnitX |
| 适用场景 | 单元测试 |
| GateType | `TestGate` / `VerificationGate` |
| 所属 Set | DueSet / AbilitySet |
| Ability | test.run, test.report |
| Output | test_report.generated |

#### AI 规则

```text
测试是 VerificationGate 的能力来源。
高风险 Output 必须能挂测试门。
```

---

### 7. madExcept

| 项目 | 面向门归属 |
|---|---|
| 第三方库 | madExcept |
| 适用场景 | 崩溃诊断 |
| GateType | `ExceptionGate` |
| 所属 Set | TraceSet / FeedbackSet |
| Output | crash_report.generated |

#### AI 规则

```text
异常不是简单 ShowMessage。
异常必须进入 Trace / Feedback / Evidence。
```

---

### 8. FastMM4

| 项目 | 面向门归属 |
|---|---|
| 第三方库 | FastMM4 |
| 适用场景 | 内存泄漏检测 |
| GateType | `MemoryCheckGate` |
| 所属 Set | VerificationGate / DueSet |
| Output | memory_report.generated |

#### AI 规则

```text
内存检查是验证门，不是 UI 功能。
```

---

### 9. python4delphi

| 项目 | 面向门归属 |
|---|---|
| 第三方库 | python4delphi |
| 适用场景 | 脚本能力、扩展脚本 |
| GateType | `ScriptGate` / `PythonAbilityGate` |
| 所属 Set | AbilitySet / DueSet |
| Due 重点 | 权限、沙箱、文件访问、执行边界 |

#### AI 规则

```text
脚本执行必须有 BoundaryGate / RiskGate。
不要让 Python 能力裸露给 AI 或用户。
```

---

### 10. mORMot2 / Indy / HTTP Server

| 项目 | 面向门归属 |
|---|---|
| 第三方库 | mORMot2 / Indy |
| 适用场景 | HTTP 服务、REST API、代理 |
| GateType | `ApiGate` / `HttpRouteGate` |
| 所属 Set | AccessGateTree / AbilitySet / DueSet |
| Ability | api.handle_request, proxy.forward |
| Due 重点 | 认证、权限、请求边界、审计 |

#### AI 规则

```text
HTTP 路由也是门。
URL Path 应进入 ApiGate / RouteGate，而不是 if/else 散落。
```

---

## 七、控件事件到门事件对应表

| Delphi 事件 | 面向门事件 | 说明 |
|---|---|---|
| `OnClick` | `EnterGate` | 点击进入一道操作门 |
| `OnDblClick` | `EnterGate` / `RouteGate` | 双击通常是打开门 |
| `OnChange` | `UpdateContext` / `ValidateGate` | 输入变化更新上下文，不直接保存 |
| `OnExit` | `ValidateGate` | 离开输入控件时校验 |
| `OnKeyDown` | `CommandGate` | 快捷键进入命令门 |
| `OnDragOver` | `PreviewGate` | 预判是否可进入 |
| `OnDragDrop` | `EnterGate` | 真正进入投放门 |
| `OnMouseEnter` | `PreviewGate` | 可显示提示 |
| `OnShow` | `EnterGate` / `RefreshGate` | 窗口或区域进入 |
| `OnCloseQuery` | `LeaveGate` / `DueGate` | 关闭前检查未保存、风险 |
| `OnTimer` | `ScheduledGate` | 定时事件进入计划门 |
| `OnException` | `ExceptionGate` | 异常进入追踪和反馈 |

---

## 八、AI 生成控件时必须输出的表

### 1. 控件映射表

```text
ProjectionKey:
ComponentClass:
NativeOrThirdParty:
Library:
GateRef:
PurposeRef:
ParentProjection:
DesignTimeRequired:
RuntimeCreateAllowed:
```

---

### 2. 事件映射表

```text
ProjectionKey:
EventName:
GateAction:
GateKey:
ContextBuilder:
AllowedLogic:
ForbiddenLogic:
```

例如：

```text
ProjectionKey: btnSealArtifact
EventName: OnClick
GateAction: EnterGate
GateKey: main.output_review.artifact.seal
AllowedLogic: build click context; call Runtime.EnterGate
ForbiddenLogic: hash artifact; write evidence; seal file directly
```

---

### 3. 状态投射表

```text
ProjectionKey:
GateKey:
EnabledFrom:
VisibleFrom:
CaptionFrom:
HintFrom:
StyleFrom:
IconFrom:
BusyFrom:
WarningFrom:
```

---

### 4. 第三方依赖表

```text
Library:
Reason:
ExistingApprovedLibrary:
UsesUnits:
GateTypes:
AbilityTypes:
DueRisks:
ApprovalRequired:
```

---

## 九、AI 的硬性禁止规则

```text
1. 不准把控件当功能。
2. 不准在 OnClick / OnDragDrop / OnDblClick 中写业务逻辑。
3. 不准用控件名当 PurposeKey / AbilityKey。
4. 不准让 View 直接访问数据库。
5. 不准在 View 中写裸 SQL。
6. 不准绕过 AccessGateTree 调用 AbilitySet。
7. 不准绕过 DueSet 做高风险操作。
8. 不准直接改生成后 DFM 作为源头，必须改 Projection 参数表。
9. 不准引入新第三方库前不检查已安装库清单。
10. 不准在 .pas 中运行时创建控件，除非标注 RUNTIME-ALLOWED 并说明原因。
11. 不准空 except。
12. 不准把 MessageDlg 当完整 DueSet。
```

---

## 十、AI 面向门开发系统应补齐的模块

### 1. ControlCatalog / 控件目录

保存所有原生与第三方控件的能力描述。

```text
ControlClass
Library
SupportedGateTypes
SupportedEvents
ProjectionProps
StateBindings
DefaultAdapter
RiskNotes
```

---

### 2. ComponentAdapterSet / 控件适配集

每类控件一个 Adapter。

```text
ButtonGateAdapter
ActionGateAdapter
PageControlGateAdapter
TreeViewGateAdapter
GridGateAdapter
SynEditGateAdapter
VirtualTreeGateAdapter
CefGateAdapter
```

Adapter 负责：

```text
事件 → Gate
GateState → 控件属性
控件输入 → Context
控件资源 → ResourceKey
```

---

### 3. EventBridge / 事件桥

统一把 Delphi 事件转成：

```text
PreviewGate
EnterGate
LeaveGate
CancelGate
RouteGate
UpdateContext
```

---

### 4. ProjectionParamStore / 投射参数库

保存 UI 参数。

```text
Left
Top
Width
Height
Align
Anchors
CaptionKey
HintKey
IconKey
StyleKey
ParentProjection
```

---

### 5. GateValidationEngine / 门模型校验器

生成代码前检查：

```text
控件是否有 GateRef
事件是否只调用 Runtime
Gate 是否有 PurposeRef
Purpose 是否有 AbilityRef
高风险 Gate 是否有 DueRef
ProjectionRef 是否存在
ThirdParty 库是否在白名单
View 是否越层
```

---

### 6. CodeGenPolicy / 代码生成策略

规定：

```text
FMX/DFM 由 Projection 参数生成
PAS 只保留事件桥接和绑定
业务进入 Controller / AbilityProvider
Data 进入 uDM / Pool
高风险进入 DueSet
```

---

## 十一、最小落地顺序

### 第一步：做 ControlCatalog

先建立原生控件与第三方控件的表。

### 第二步：做 ComponentAdapterSet

至少实现：

```text
ButtonAdapter
ActionAdapter
PageControlAdapter
TabSheetAdapter
TreeViewAdapter
GridAdapter
```

### 第三步：做 EventBridge

统一事件转 Gate。

### 第四步：做 Projection 参数表

让控件位置、大小、Caption、Hint、Icon 都可由参数生成。

### 第五步：接入 GateValidationEngine

生成前校验。

### 第六步：扩展第三方控件

优先接：

```text
SynEdit
VirtualTreeView
Cef4Delphi
Skia4Delphi
DUnitX
```

---

## 十二、控件接入示例：TPageControl 文件拖入

```text
ProjectionKey: MainPageControl
ComponentClass: TPageControl
GateRef: main.pagecontrol.external_file_drag

EventMapping:
  OnDragOver → PreviewGate(main.pagecontrol.external_file_drag)
  OnDragDrop → EnterGate(main.pagecontrol.external_file_drag)

RouteGate:
  GateKey: main.pagecontrol.file_extension_route
  RouteBy: file.extension
  RouteTable:
    .pas: main.pagecontrol.tab.code.drop
    .dfm: main.pagecontrol.tab.dfm.drop
    .json: main.pagecontrol.tab.config.drop
    .png: main.pagecontrol.tab.image.drop
    default: main.pagecontrol.tab.unknown.drop
```

---

## 十三、控件接入示例：DBGrid 删除记录

```text
ProjectionKey: CustomerDBGrid
ComponentClass: TDBGrid
GateRef: main.customer_grid.record.select

ProjectionKey: btnDeleteCustomer
ComponentClass: TButton
GateRef: main.customer_detail.delete

EventMapping:
  btnDeleteCustomer.OnClick → EnterGate(main.customer_detail.delete)

DueRefs:
  - PermissionGate.can_delete_record
  - EvidenceSet.delete_log_required
  - AccountabilitySet.current_user_required
```

---

## 十四、控件接入示例：SynEdit 保存代码

```text
ProjectionKey: CodeEditorSynEdit
ComponentClass: TSynEdit
Library: SynEdit
GateRef: main.editor.code.edit

EventMapping:
  OnChange → UpdateContext(code_document.modified)
  Ctrl+S → EnterGate(main.editor.code.save)

PurposeRef:
  code.document.save

AbilityRefs:
  - file.text.write
  - evidence.write_optional

DueRefs:
  - BoundarySet.no_readonly_file_save
```

---

## 十五、最终冻结句

> 在面向门的 AI Delphi 开发系统中，原生控件和第三方控件都不能被直接理解为功能或业务入口。它们必须先进入 ControlCatalog，被映射为 ProjectionNode 与 AccessGateNode，再通过 ComponentAdapter 把控件事件降级为 PreviewGate / EnterGate / UpdateContext / RouteGate，把 GateState 投射回 Caption / Hint / Enabled / Visible / Style 等控件属性。第三方控件也不例外：SynEdit 是 CodeEditorGate 的投射体，VirtualTreeView 是 VirtualTreeGate 的投射体，Cef4Delphi 是 WebViewGate 的投射体，DUnitX 是 VerificationGate 的能力来源。AI 生成 Delphi 软件时，必须先查控件—门禁对应表，再生成 Projection 参数、事件桥接、Purpose/Ability/Due 挂接，最后通过结构校验和原有 Delphi 开发约定检测。
