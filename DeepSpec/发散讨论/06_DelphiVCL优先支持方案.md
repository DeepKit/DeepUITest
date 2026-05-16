# DeepSpec MVP：Delphi/VCL 优先支持方案

## 一、为什么 MVP 优先支持 Delphi/VCL

DeepSpec 第一版运行在 Windows 上，并使用 Delphi + VCL + WebView2 开发。

优先支持 Delphi/VCL 项目有几个好处：

1. 与自身技术栈一致；
2. 可以直接解析 `.pas / .dfm / .dpr / .dproj`；
3. `.dfm` 天然适合生成 UI 层次树；
4. 老 Delphi 项目普遍存在文档缺失、窗体肥胖、交接困难；
5. 适合形成商业化切口：Delphi 老项目结构可视化与 AI 改造准备工具。

---

## 二、需要识别的文件

```text
.dpr      工程入口
.dproj    项目文件
.pas      单元与类
.dfm      VCL 窗体结构
.ini      配置
.res/.rc  资源
```

---

## 三、从 .dpr / .dproj 提取

可提取：

- 项目名称；
- 主工程文件；
- 引用单元；
- 主窗体；
- 编译目标；
- 平台信息。

---

## 四、从 .pas 提取

可提取：

- Unit 名称；
- Interface / Implementation；
- uses 列表；
- Class 名；
- Form 类；
- DataModule 类；
- 方法名；
- 事件处理器；
- 注释标题。

---

## 五、从 .dfm 提取

可提取：

- Form 名；
- 控件树；
- 控件类型；
- 控件名称；
- Caption；
- Align；
- Parent；
- Menu；
- Action；
- PageControl / TabSheet；
- TEdgeBrowser；
- TTreeView；
- Button；
- Panel。

---

## 六、Delphi/VCL 的三棵树生成

### 1. UI 层次树

主要来自 `.dfm`。

示例：

```text
TMainForm
├─ TopToolbar
│  ├─ BtnOpenFolder
│  ├─ BtnRescan
│  └─ BtnExport
├─ LeftPanel
│  └─ ProjectTree
├─ CenterPanel
│  └─ StructureTreeTabs
└─ RightPanel
   └─ DetailWebView
```

### 2. 模块树

来自：

- 目录结构；
- Unit 名；
- Form 名；
- uses 关系；
- Core / UI / Render / IO 等目录。

### 3. 候选功能树

来自：

- Button Caption；
- Menu Caption；
- Action Caption；
- 方法名；
- README 功能说明；
- TODO。

---

## 七、商业化切口

DeepSpec 第一版可以面向：

# **Delphi 老项目结构可视化与 AI 改造准备**

用户价值：

- 看清窗体；
- 看清控件；
- 看清模块；
- 看清候选功能；
- 生成 AI 参考摘要；
- 为后续 AI 修改提供基准。
