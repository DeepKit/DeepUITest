# DeepDevLite 核心功能开发规格文�?
**版本**: v1.1  
**技术栈**: Delphi FMX（跨平台�? 
**定位**: Progee 轻量入门版，单文件验证闭�? 
**关联文档**: DeepDevLite-Dev-Spec.md（UI/报告/卡片规格�?
---

## 目录

1. 产品核心流程总览
2. 用户旅程（完整）
3. 输入方式
4. 契约字段定义
5. 模块一：文件输入（内置文件浏览器）
6. 模块二：AI 分析契约
7. 模块三：用户确认契约
8. 模块四：测试脚本生成与执�?9. 模块五：自动修复循环（智能赛马）
10. 模块六：代码文件输出
11. 模块七：契约文件输出�?yaml�?12. 模块八：封存记录
13. 分享与复制功�?14. 首页 ODD 介绍
15. AI 模型调用规范
16. 本地环境检�?17. 窗体与状态机设计
18. 开发顺序建�?
---

## 1. 产品核心流程总览

```
┌─────────────────────────────────────────────────────────────�?�?                     DeepDevLite 主流�?                       �?└─────────────────────────────────────────────────────────────�?
  [欢迎页]
  ODD理念介绍 + 引导用户开�?       �?       �?  [代码输入]
  拖拽 / 粘贴代码 / 选择文件
       �?       �?  [AI 分析]
  读取代码 �?推导契约草稿
       �?       �?  [契约确认]  ←── 正式化表单展示，用户理解ODD
       �?       �?  [生成测试脚本]
  AI 生成 �?调用本地环境运行
       �?       ├── 通过 ──────────────────────────────────────�?       �?                                             �?       └── 失败                                       �?            �?                                        �?            ├── �?轮：AI 修复 �?重新验证           �?            ├── �?轮：升级模型 �?重新验证           �?            ├── �?轮：再升�?�?重新验证             �?            └── 仍失�?�?报告失败原因               �?                        用户手动修改后可重试           �?                                                      �?  ◄─────────────────────────────────────────────────�?  [输出]
  �?代码文件（封存标记版 �?AI修正版，可覆盖源文件�?  📄 验证报告（PDF + PNG�?  📋 契约文件�?yaml�?  🔒 封存记录（SHA-256 + 时间戳）
  📱 朋友圈卡片生成器
  🔗 邀请分享链�?  📋 一键复制代码到剪贴�?```

---

## 2. 用户旅程（完整）

```
┌─────────────────────────────────────────────────────────────�?�?                       用户旅程                              �?├─────────────────────────────────────────────────────────────�?�?                                                             �?�? Step 1: 首页                                               �?�? ┌─────────────────────────────────────────────────────�?  �?�? �? 🏭 DeepDevLite                                     �?  �?�? �? AI 原生软件工厂                                    �?  �?�? �?                                                     �?  �?�? �? ODD = Output-Driven Development                   �?  �?�? �? 输出驱动开发，让AI代码有据可循                     �?  �?�? �?                                                     �?  �?�? �?     [开始验证]                                     �?  �?�? └─────────────────────────────────────────────────────�?  �?�?                                                             �?�? Step 2: 代码输入（三种方式）                               �?�? ┌──────────────────�? ┌──────────────────�?             �?�? �?  📁 拖拽文件    �? �?  📋 粘贴代码    �?             �?�? └──────────────────�? └──────────────────�?             �?�? ┌──────────────────�?                                   �?�? �?  📂 选择文件    �?                                   �?�? └──────────────────�?                                   �?�?                                                             �?�? Step 3: 契约生成 + 确认                                   �?�? ┌─────────────────────────────────────────────────────�?  �?�? �? 📋 验证契约（AI 推导�?                           �?  �?�? �?                                                     �?  �?�? �? 标题：用户登录验�?                                 �?  �?�? �? 描述：实现用户登录功�?..                           �?  �?�? �? 语言：Python                                       �?  �?�? �? 验收标准�?�?                                    �?  �?�? �? 边界条件�?�?                                    �?  �?�? �? 异常输入�?�?                                    �?  �?�? �?                                                     �?  �?�? �? [重新分析]        [确认契约，开始验证]            �?  �?�? └─────────────────────────────────────────────────────�?  �?�?                                                             �?�? Step 4: 验证过程                                           �?�? ┌─────────────────────────────────────────────────────�?  �?�? �? 🔄 正在验证...                                     �?  �?�? �?                                                     �?  �?�? �? [████████░░░░] 60%                                �?  �?�? �? 当前: 运行测试脚本                                  �?  �?�? �?                                                     �?  �?�? �? 日志输出...                                        �?  �?�? └─────────────────────────────────────────────────────�?  �?�?                                                             �?�? Step 5: 验证通过                                           �?�? ┌─────────────────────────────────────────────────────�?  �?�? �? �?验证通过�?                                     �?  �?�? �?                                                     �?  �?�? �? 模块: 用户登录验证  场景: 3/3  用时: 2.3s        �?  �?�? �?                                                     �?  �?�? �? [📱 生成分享卡片]  [🔗 复制代码]  [📋 分享链接]  �?  �?�? �? [📥 保存代码]      [📄 查看报告]                  �?  �?�? └─────────────────────────────────────────────────────�?  �?�?                                                             �?└─────────────────────────────────────────────────────────────�?```

---

## 3. 输入方式

### 3.1 拖拽文件

支持将代码文件拖入窗口，自动识别语言并加载�?
### 3.2 粘贴代码（独立功能）

提供文本输入框，用户可直接粘贴代码内容�?
```pascal
// 粘贴代码输入界面
type
  TFrameCodeInput = class(TFrame)
    MemoCode: TMemo;           // 代码输入区域
    LblLanguage: TLabel;       // 自动识别的语言
    BtnVerify: TButton;       // 开始验证按�?    procedure BtnVerifyClick(Sender: TObject);
  end;
```

### 3.3 选择文件

使用 TOpenDialog 选择本地代码文件�?
---

## 4. 契约字段定义

### 4.1 核心属�?
| 属�?| 类型 | 约束 | 说明 |
|------|------|------|------|
| **id** | UUID | 系统生成 | 主键 |
| **title** | VARCHAR(200) | 硬性，�?字符 | 功能名称 |
| **description** | TEXT | 硬性，�?0字符 | 功能描述 |
| **language** | VARCHAR(30) | 硬性，单�?| 主要语言 |
| **module** | VARCHAR(100) | 软�?| 所属功能模块名�?|

### 4.2 验收属�?
| 属�?| 类型 | 约束 | 说明 |
|------|------|------|------|
| **acceptance_criteria** | JSONB | 硬性，�?�?| 整体验收标准（Given-When-Then�?|
| **boundary_cases** | JSONB | 硬性，�?�?| 边界条件（必须包含异常输入） |
| **error_cases** | JSONB | 硬性，�?�?| 异常输入的输入输出映�?|

### 4.3 acceptance_criteria 结构

```json
{
  "criteria": [
    {
      "id": "AC-001",
      "given": "前置条件描述",
      "when": "触发动作描述",
      "then": "期望结果描述",
      "priority": "must|should|could"
    }
  ]
}
```

### 4.4 boundary_cases 结构

```json
{
  "cases": [
    {
      "id": "BC-001",
      "scenario": "边界场景描述",
      "input": "边界输入",
      "expected": "期望行为"
    }
  ]
}
```

### 4.5 error_cases 结构

```json
{
  "cases": [
    {
      "id": "EC-001",
      "scenario": "异常场景描述",
      "input": "异常输入",
      "expected_error": "期望的错误码或消�?
    }
  ]
}
```

---

## 5. 模块一：文件输入（与原文档相同�?
## 6. 模块二：AI 分析契约（与原文档相同）

## 7. 模块三：用户确认契约

### 7.1 契约编辑�?UI（正式化表单�?
```
┌──────────────────────────────────────────────────────────────�?�? 📋 验证契约                                                �?├──────────────────────────────────────────────────────────────�?�? 编号: PRG-20260220-0001      状�? 待确�?                 �?├──────────────────────────────────────────────────────────────�?�? 基本信息                                                    �?�? ─────────────────────────────────────────────────────────  �?�? 标题 *        �?[输入框]                                    �?�? 描述 *        �?[输入框]                                    �?�? 语言          �?[Python           ▼]                       �?�? 模块          �?[输入框]                                    �?├──────────────────────────────────────────────────────────────�?�? 验收标准 (Given-When-Then)                                 �?�? ─────────────────────────────────────────────────────────  �?�? ┌────────────────────────────────────────────────────────�?�?�? �?AC-001  must                                          �?�?�? �?Given: 用户输入有效账号                               �?�?�? �?When: 点击登录                                        �?�?�? �?Then: 返回登录成功                                    �?�?�? └────────────────────────────────────────────────────────�?�?�? ┌────────────────────────────────────────────────────────�?�?�? �?AC-002  must                                          �?�?�? �?Given: 用户输入错误密码                                �?�?�? �?When: 点击登录                                        �?�?�? �?Then: 返回错误提示                                    �?�?�? └────────────────────────────────────────────────────────�?�?�?                                                     [+添加] �?├──────────────────────────────────────────────────────────────�?�? 边界条件                                                    �?�? ─────────────────────────────────────────────────────────  �?�? BC-001: 用户名为�?�?提示必填                            �?�? BC-002: 用户名超�?�?提示最大长�?                       �?�? BC-003: 密码为空 �?提示必填                              �?├──────────────────────────────────────────────────────────────�?�? 异常输入                                                    �?�? ─────────────────────────────────────────────────────────  �?�? EC-001: SQL注入 �?返回安全警告                            �?├──────────────────────────────────────────────────────────────�?�? 质量评分: 85/100                                          �?�? ─────────────────────────────────────────────────────────  �?�? [重新分析]                              [确认契约，开始验证]�?└──────────────────────────────────────────────────────────────�?```

### 7.2 契约确认的意�?
- 用户通过表单**显式理解**验证目标
- ODD 理念贯穿：先定义"什么是完成"，再验证
- 契约�?*人机协同**的桥�?
---

## 8-12. （与原文档相同）

## 13. 分享与复制功�?
### 13.1 一键复制代�?
```pascal
procedure CopyVerifiedCodeToClipboard(const Code: string);
begin
  // 使用 FMX 剪贴�?  Clipboard.AsText := Code;
  ShowMessage('代码已复制到剪贴板！');
end;
```

### 13.2 邀请分享链�?
分享验证结果，生成链接供他人查看�?
```pascal
function GenerateShareLink(const ReportID: string): string;
begin
  Result := Format('https://progeelite.com/share/%s', [ReportID]);
end;

procedure ShareToClipboard(const ReportID: string);
var
  Link: string;
begin
  Link := GenerateShareLink(ReportID);
  Clipboard.AsText := Link;
  ShowMessage('分享链接已复制！');
end;
```

### 13.3 分享按钮 UI

```
[📋 复制代码]  [🔗 分享链接]  [📱 生成分享卡片]
```

---

## 14. 首页 ODD 介绍

### 14.1 首页布局

```
┌─────────────────────────────────────────────────────────────�?�?                                                            �?�?                   🏭 DeepDevLite                            �?�?                 AI 原生软件工厂                             �?�?                                                            �?�? ───────────────────────────────────────────────────────   �?�?                                                            �?�? 什么是 ODD�?                                              �?�? ───────────────────────────────────────────────────────   �?�? ODD = Output-Driven Development                           �?�? 输出驱动开�?                                              �?�?                                                            �?�? 传统的开发方式：                                           �?�?   写代�?�?人工测试 �?上线                                �?�?   �?依赖开发者经�?�?难以复现                            �?�?                                                            �?�? ODD 的方式：                                               �?�?   定义验证契约 �?AI生成代码 �?自动验证 �?封存              �?�?   �?有据可循 �?可复�?�?可追�?                          �?�?                                                            �?�? ───────────────────────────────────────────────────────   �?�?                                                            �?�?        [开始验�?→]                                        �?�?                                                            �?�? ───────────────────────────────────────────────────────   �?�?                                                            �?�? 支持: Python JavaScript TypeScript Go Java...             �?�?                                                            �?└─────────────────────────────────────────────────────────────�?```

### 14.2 ODD 内容获取（未来）

未来�?www.goodmem.cn 拉取 ODD 理念介绍内容�?
---

## 15-18. （与原文档相同）

---

## 附录 A：支持语言列表

| 语言 | 扩展�?| 运行命令 |
|------|--------|----------|
| Python | .py | python |
| JavaScript | .js | node |
| TypeScript | .ts | ts-node |
| Go | .go | go run |
| Java | .java | java |
| C# | .cs | dotnet script |
| Ruby | .rb | ruby |
| PHP | .php | php |
| Swift | .swift | swift |
| Rust | .rs | cargo script |
| Dart | .dart | dart |
| Kotlin | .kt | kotlin |

## 附录 B：输出文件命名规�?
| 文件 | 命名规则 | 示例 |
|------|----------|------|
| 封存代码 | `原名_sealed.ext` | `login_sealed.py` |
| 契约文件 | `原名.contract.yaml` | `login.contract.yaml` |
| 封存记录 | `原名.seal.txt` | `login.seal.txt` |
| 验证报告 | `DeepDevLite_报告ID.pdf` | `DeepDevLite_PRG-20260220-0042.pdf` |
| 朋友圈卡�?| `DeepDevLite_Card_日期.png` | `DeepDevLite_Card_20260220.png` |
| 分享链接 | `https://progeelite.com/share/报告ID` | `https://progeelite.com/share/PRG-20260220-0001` |

---

## 1. 产品核心流程总览

```
┌─────────────────────────────────────────────────────�?�?                  DeepDevLite 主流�?                  �?└─────────────────────────────────────────────────────�?
  [文件输入]
  拖拽 / 按钮 / 内置文件�?       �?       �?  [AI 分析]
  读取代码 �?推导契约草稿
       �?       �?  [用户确认契约]  ←── 必须确认才继续（人是仲裁者）
       �?       �?  [生成测试脚本]
  AI 生成 �?调用本地环境运行
       �?       ├── 通过 ──────────────────────────────────�?       �?                                         �?       └── 失败                                   �?            �?                                   �?            ├── �?轮：AI 修复 �?重新验证          �?            ├── �?轮：升级模型 �?重新验证          �?            ├── �?轮：再升�?�?重新验证            �?            └── 仍失�?�?报告失败原因              �?                        用户手动修改后可重试        �?                                                  �?  ◄─────────────────────────────────────────────�?  [输出]
  �?代码文件（封存标记版 �?AI修正版，可覆盖源文件�?  📄 验证报告（PDF + PNG�?  📋 契约文件�?yaml�?  🔒 封存记录（SHA-256 + 时间戳）
  📱 朋友圈卡片生成器
```

### 1.1 核心状态枚�?
```pascal
type
  TVerifyState = (
    vsIdle,           // 空闲，等待文件输�?    vsFileLoaded,     // 文件已加载，等待分析
    vsAnalyzing,      // AI 正在分析契约
    vsContractReady,  // 契约草稿已生成，等待用户确认
    vsConfirmed,      // 用户已确认契�?    vsGeneratingTest, // AI 正在生成测试脚本
    vsRunningTest,    // 测试运行�?    vsFixing,         // AI 修复代码中（第N轮）
    vsPassed,         // 验证通过
    vsFailed,         // 验证最终失�?    vsOutputting      // 输出文件�?  );
```

---

## 2. 模块一：文件输�?
### 2.1 三种输入方式

#### 方式 A：拖�?
```pascal
// 在主窗体�?Drop Zone 控件上注册拖拽事�?procedure TFormMain.OnDragOver(Sender: TObject; const Data: TDragObject;
  const Point: TPointF; var Operation: TDragOperation);
begin
  // 检查是否为单个文件
  if (Length(Data.Files) = 1) then
    Operation := TDragOperation.Copy
  else
    Operation := TDragOperation.None;
end;

procedure TFormMain.OnDragDrop(Sender: TObject; const Data: TDragObject;
  const Point: TPointF);
begin
  if Length(Data.Files) = 1 then
    LoadSourceFile(Data.Files[0]);
end;
```

#### 方式 B：按钮上�?
```pascal
procedure TFormMain.BtnOpenFileClick(Sender: TObject);
var
  OpenDlg: TOpenDialog;
begin
  OpenDlg := TOpenDialog.Create(nil);
  try
    OpenDlg.Filter :=
      'Source Files|*.py;*.js;*.ts;*.go;*.java;*.cs;*.rb;*.php;*.swift;*.kt;' +
      '*.cpp;*.c;*.h;*.rs;*.dart|All Files|*.*';
    OpenDlg.Title := '选择要验证的代码文件';
    if OpenDlg.Execute then
      LoadSourceFile(OpenDlg.FileName);
  finally
    OpenDlg.Free;
  end;
end;
```

#### 方式 C：内置文件浏览器

使用 FMX `TTreeView` 构建，左侧常驻面板�?
```pascal
type
  TFileTreePanel = class(TPanel)
  private
    FTreeView  : TTreeView;
    FRootPath  : string;
    FOnFileSelected: TProc<string>;
    procedure BuildTree(ParentNode: TTreeViewItem; const Path: string);
    procedure OnItemDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetRootPath(const Path: string);
    property OnFileSelected: TProc<string> read FOnFileSelected write FOnFileSelected;
  end;

procedure TFileTreePanel.BuildTree(ParentNode: TTreeViewItem; const Path: string);
var
  SR       : TSearchRec;
  DirItem  : TTreeViewItem;
  FileItem : TTreeViewItem;
begin
  // 先加目录
  if FindFirst(Path + PathDelim + '*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name <> '.') and (SR.Name <> '..') and
         (SR.Attr and faDirectory <> 0) then
      begin
        DirItem := TTreeViewItem.Create(FTreeView);
        DirItem.Text := '📁 ' + SR.Name;
        DirItem.TagString := Path + PathDelim + SR.Name;
        if ParentNode = nil then
          DirItem.Parent := FTreeView
        else
          DirItem.Parent := ParentNode;
        BuildTree(DirItem, Path + PathDelim + SR.Name);
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;

  // 再加文件（过滤支持的扩展名）
  if FindFirst(Path + PathDelim + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory = 0) and IsSourceFile(SR.Name) then
      begin
        FileItem := TTreeViewItem.Create(FTreeView);
        FileItem.Text := '📄 ' + SR.Name;
        FileItem.TagString := Path + PathDelim + SR.Name;
        if ParentNode = nil then
          FileItem.Parent := FTreeView
        else
          FileItem.Parent := ParentNode;
      end;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

function TFileTreePanel.IsSourceFile(const FileName: string): Boolean;
const
  EXTS: array[0..14] of string = (
    '.py','.js','.ts','.go','.java','.cs','.rb',
    '.php','.swift','.kt','.cpp','.c','.h','.rs','.dart'
  );
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := False;
  for var E in EXTS do
    if Ext = E then Exit(True);
end;
```

### 2.2 文件加载

```pascal
procedure TFormMain.LoadSourceFile(const FilePath: string);
var
  SL: TStringList;
begin
  // 单文件限制检�?  if GetFileSize(FilePath) > 500 * 1024 then  // 500KB 上限
  begin
    ShowMessage('DeepDevLite 仅支持单文件验证，文件不超过 500KB�? + #13#10 +
                '如需处理完整项目，请使用 Progee 完整版�?);
    Exit;
  end;

  SL := TStringList.Create;
  try
    SL.LoadFromFile(FilePath, TEncoding.UTF8);
    FSourceCode    := SL.Text;
    FSourcePath    := FilePath;
    FSourceLang    := DetectLanguage(FilePath);
  finally
    SL.Free;
  end;

  SetState(vsFileLoaded);
  UpdateFileInfo;  // 更新界面显示文件名、语言、行�?end;
```

### 2.3 语言自动识别

```pascal
function TFormMain.DetectLanguage(const FilePath: string): TSourceLanguage;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FilePath));
  if      Ext = '.py'    then Result := slPython
  else if Ext = '.js'    then Result := slJavaScript
  else if Ext = '.ts'    then Result := slTypeScript
  else if Ext = '.go'    then Result := slGo
  else if Ext = '.java'  then Result := slJava
  else if Ext = '.cs'    then Result := slCSharp
  else if Ext = '.rb'    then Result := slRuby
  else if Ext = '.php'   then Result := slPHP
  else if Ext = '.swift' then Result := slSwift
  else if Ext = '.kt'    then Result := slKotlin
  else if Ext = '.cpp'   then Result := slCPP
  else if Ext = '.rs'    then Result := slRust
  else if Ext = '.dart'  then Result := slDart
  else                        Result := slUnknown;
end;
```

---

## 3. 模块二：AI 分析契约

### 3.1 分析 Prompt 模板

```pascal
function TFormMain.BuildAnalysisPrompt: string;
const
  TMPL =
    'You are a code contract analyzer.' + #10 +
    'Analyze the following %s code and extract a verification contract.' + #10 +
    #10 +
    'The contract must include:' + #10 +
    '1. Function/module purpose (one sentence, Chinese)' + #10 +
    '2. At least 3 acceptance scenarios: normal case, edge case, error case' + #10 +
    '3. Each scenario must have: input, expected output, description (Chinese)' + #10 +
    #10 +
    'Output ONLY valid YAML in this exact format:' + #10 +
    '---' + #10 +
    'contract:' + #10 +
    '  title: "功能标题"' + #10 +
    '  language: "%s"' + #10 +
    '  purpose: "这段代码的目的是..."' + #10 +
    '  scenarios:' + #10 +
    '    - id: S001' + #10 +
    '      desc: "正常场景描述"' + #10 +
    '      type: normal' + #10 +
    '      input: "输入描述或�?' + #10 +
    '      expected: "期望输出描述或�?' + #10 +
    '    - id: S002' + #10 +
    '      desc: "边界场景描述"' + #10 +
    '      type: edge' + #10 +
    '      input: "..."' + #10 +
    '      expected: "..."' + #10 +
    '    - id: S003' + #10 +
    '      desc: "异常场景描述"' + #10 +
    '      type: error' + #10 +
    '      input: "..."' + #10 +
    '      expected: "..."' + #10 +
    '---' + #10 +
    #10 +
    'Source code:' + #10 +
    '```%s' + #10 +
    '%s' + #10 +
    '```';
begin
  Result := Format(TMPL, [
    LanguageToString(FSourceLang),
    LanguageToString(FSourceLang),
    LanguageToString(FSourceLang),
    FSourceCode
  ]);
end;
```

### 3.2 调用 AI 分析

```pascal
procedure TFormMain.AnalyzeContract;
begin
  SetState(vsAnalyzing);
  ShowProgress('AI 正在分析代码，推导契�?..');

  TTask.Run(procedure
  var
    Prompt   : string;
    Response : string;
    Contract : TContract;
  begin
    Prompt := BuildAnalysisPrompt;
    Response := CallAI(Prompt, FModelTier1);  // 使用一级模�?
    TThread.Synchronize(nil, procedure
    begin
      if TryParseContract(Response, Contract) then
      begin
        FContract := Contract;
        SetState(vsContractReady);
        ShowContractEditor;  // 展示契约编辑�?      end
      else
      begin
        ShowError('契约解析失败，请重试�?);
        SetState(vsFileLoaded);
      end;
    end);
  end);
end;
```

---

## 4. 模块三：用户确认契约

### 4.1 契约编辑�?UI

契约确认界面分两栏：

```
┌──────────────────────────────────────────────────────�?�? 📋 契约草稿（AI 推导�?         可直接编�?          �?├─────────────────────┬────────────────────────────────�?�? 契约标题           �? [编辑框]                       �?�? 功能目的           �? [编辑框]                       �?├─────────────────────┴────────────────────────────────�?�? 验证场景                              [+ 添加场景]   �?�? ┌────────────────────────────────────────────────�? �?�? �?S001  正常场景  [描述]  输入:[...]  期望:[...] �? �?�? �?S002  边界场景  [描述]  输入:[...]  期望:[...] �? �?�? �?S003  异常场景  [描述]  输入:[...]  期望:[...] �? �?�? └────────────────────────────────────────────────�? �?├──────────────────────────────────────────────────────�?�? [重新分析]                    [确认契约，开始验证]   �?└──────────────────────────────────────────────────────�?```

### 4.2 契约数据结构

```pascal
type
  TScenarioType = (stNormal, stEdge, stError);

  TContractScenario = record
    ID       : string;          // S001, S002...
    Desc     : string;          // 中文描述
    ScenType : TScenarioType;
    Input    : string;          // 输入描述
    Expected : string;          // 期望输出描述
  end;

  TContract = record
    Title     : string;
    Language  : TSourceLanguage;
    Purpose   : string;
    Scenarios : array of TContractScenario;
    CreatedAt : TDateTime;
    // 运行�?    ConfirmedAt : TDateTime;
    IsConfirmed : Boolean;
  end;
```

### 4.3 契约 YAML 解析

```pascal
function TFormMain.TryParseContract(const YAMLText: string;
  out Contract: TContract): Boolean;
var
  Lines    : TStringList;
  Line     : string;
  InScenario: Boolean;
  CurScenario: TContractScenario;
begin
  Result := False;
  Lines := TStringList.Create;
  try
    Lines.Text := YAMLText;
    InScenario := False;

    for var i := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[i]);

      if Line.StartsWith('title:') then
        Contract.Title := ExtractYAMLValue(Line)
      else if Line.StartsWith('purpose:') then
        Contract.Purpose := ExtractYAMLValue(Line)
      else if Line.StartsWith('language:') then
        Contract.Language := FSourceLang
      else if Line.StartsWith('- id:') then
      begin
        if InScenario then
          Contract.Scenarios := Contract.Scenarios + [CurScenario];
        CurScenario := Default(TContractScenario);
        CurScenario.ID := ExtractYAMLValue(Line);
        InScenario := True;
      end
      else if InScenario then
      begin
        if Line.StartsWith('desc:') then
          CurScenario.Desc := ExtractYAMLValue(Line)
        else if Line.StartsWith('type:') then
          CurScenario.ScenType := ParseScenType(ExtractYAMLValue(Line))
        else if Line.StartsWith('input:') then
          CurScenario.Input := ExtractYAMLValue(Line)
        else if Line.StartsWith('expected:') then
          CurScenario.Expected := ExtractYAMLValue(Line);
      end;
    end;

    if InScenario then
      Contract.Scenarios := Contract.Scenarios + [CurScenario];

    Result := (Contract.Title <> '') and (Length(Contract.Scenarios) >= 1);
  finally
    Lines.Free;
  end;
end;

function TFormMain.ExtractYAMLValue(const Line: string): string;
var
  Pos: Integer;
begin
  Pos := Line.IndexOf(':');
  if Pos >= 0 then
  begin
    Result := Trim(Line.Substring(Pos + 1));
    // 去掉首尾引号
    if (Length(Result) >= 2) and
       (Result[1] = '"') and (Result[Length(Result)] = '"') then
      Result := Result.Substring(1, Length(Result) - 2);
  end
  else
    Result := '';
end;
```

### 4.4 用户确认

```pascal
procedure TFormMain.BtnConfirmContractClick(Sender: TObject);
begin
  // 从编辑器回写契约数据
  ReadContractFromEditor(FContract);

  // 验证契约完整�?  if Length(FContract.Scenarios) = 0 then
  begin
    ShowMessage('请至少保留一个验证场景�?);
    Exit;
  end;

  FContract.IsConfirmed := True;
  FContract.ConfirmedAt := Now;

  SetState(vsConfirmed);
  GenerateTestScript;
end;
```

---

## 5. 模块四：测试脚本生成与执�?
### 5.1 生成测试脚本 Prompt

```pascal
function TFormMain.BuildTestGenPrompt: string;
const
  TMPL =
    'Generate a runnable test script for the following %s code.' + #10 +
    #10 +
    'Contract to verify:' + #10 +
    '%s' + #10 +
    #10 +
    'Source code:' + #10 +
    '```%s' + #10 +
    '%s' + #10 +
    '```' + #10 +
    #10 +
    'Requirements:' + #10 +
    '1. Generate ONE self-contained test file' + #10 +
    '2. Test each scenario in the contract' + #10 +
    '3. Output PASS/FAIL for each scenario ID (e.g. S001: PASS)' + #10 +
    '4. Final line must be: OVERALL: PASS or OVERALL: FAIL' + #10 +
    '5. No external dependencies beyond standard library' + #10 +
    '6. Output ONLY the code, no explanation';
begin
  Result := Format(TMPL, [
    LanguageToString(FSourceLang),
    ContractToYAML(FContract),
    LanguageToString(FSourceLang),
    FSourceCode
  ]);
end;
```

### 5.2 执行测试脚本

```pascal
procedure TFormMain.RunTestScript(const ScriptCode: string);
var
  ScriptPath : string;
  OutputPath : string;
begin
  // 写入临时文件
  ScriptPath := TPath.GetTempFileName + GetLangExt(FSourceLang);
  OutputPath := TPath.GetTempFileName + '.txt';

  TFile.WriteAllText(ScriptPath, ScriptCode, TEncoding.UTF8);

  ShowProgress(Format('运行测试�?.. (�?d�?', [FRetryCount + 1]));

  TTask.Run(procedure
  var
    ExitCode : Integer;
    Output   : string;
    Results  : TTestResults;
  begin
    ExitCode := ExecuteProcess(
      BuildRunCommand(FSourceLang, ScriptPath),
      Output,
      30  // 30秒超�?    );

    TThread.Synchronize(nil, procedure
    begin
      Results := ParseTestOutput(Output);
      HandleTestResults(Results, ScriptCode);
      // 清理临时文件
      TFile.Delete(ScriptPath);
    end);
  end);
end;

function TFormMain.ExecuteProcess(const Command: string;
  out Output: string; TimeoutSecs: Integer): Integer;
var
  Process : TProcess;  // 使用 Delphi FMX 跨平台进程调�?begin
  // Windows: CreateProcess
  // macOS/Linux: posix_spawn �?popen
  // 建议封装�?TProcessHelper 类处理跨平台差异
  // 捕获 stdout + stderr 合并输出
end;
```

### 5.3 运行命令构建

```pascal
function TFormMain.BuildRunCommand(Lang: TSourceLanguage;
  const ScriptPath: string): string;
begin
  case Lang of
    slPython:     Result := Format('python "%s"', [ScriptPath]);
    slJavaScript: Result := Format('node "%s"', [ScriptPath]);
    slTypeScript: Result := Format('ts-node "%s"', [ScriptPath]);
    slGo:         Result := Format('go run "%s"', [ScriptPath]);
    slJava:       Result := Format('java "%s"', [ChangeFileExt(ScriptPath, '')]);
    slCSharp:     Result := Format('dotnet script "%s"', [ScriptPath]);
    slRuby:       Result := Format('ruby "%s"', [ScriptPath]);
    slPHP:        Result := Format('php "%s"', [ScriptPath]);
    slSwift:      Result := Format('swift "%s"', [ScriptPath]);
    slRust:       Result := Format('cargo script "%s"', [ScriptPath]);
  else
    raise Exception.Create('不支持的语言');
  end;
end;
```

### 5.4 测试结果解析

```pascal
type
  TScenarioResult = record
    ID     : string;
    Passed : Boolean;
    Detail : string;
  end;

  TTestResults = record
    ScenarioResults : array of TScenarioResult;
    OverallPassed   : Boolean;
    RawOutput       : string;
    ExecutionMS     : Integer;
  end;

function TFormMain.ParseTestOutput(const Output: string): TTestResults;
var
  Lines : TStringList;
  Line  : string;
  SR    : TScenarioResult;
begin
  Result.RawOutput := Output;
  Lines := TStringList.Create;
  try
    Lines.Text := Output;
    for var i := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[i]);
      // 解析 "S001: PASS" �?"S001: FAIL"
      if Line.Contains(': PASS') or Line.Contains(': FAIL') then
      begin
        SR.ID     := Trim(Line.Substring(0, Line.IndexOf(':')));
        SR.Passed := Line.Contains(': PASS');
        Result.ScenarioResults := Result.ScenarioResults + [SR];
      end
      // 解析最终结�?      else if Line.StartsWith('OVERALL:') then
        Result.OverallPassed := Line.Contains('PASS');
    end;
  finally
    Lines.Free;
  end;
end;
```

---

## 6. 模块五：自动修复循环（智能赛马）

### 6.1 模型等级定义

```pascal
const
  // 模型名称根据实际接入�?AI 服务调整
  MODEL_TIER1 = 'claude-haiku-4-5';    // 快速，低成�?  MODEL_TIER2 = 'claude-sonnet-4';     // 标准
  MODEL_TIER3 = 'claude-opus-4';       // 最�?
type
  TModelTier = (mtTier1, mtTier2, mtTier3);
```

### 6.2 修复循环主逻辑

```pascal
procedure TFormMain.HandleTestResults(const Results: TTestResults;
  const TestScript: string);
begin
  if Results.OverallPassed then
  begin
    // 验证通过
    FTestResults := Results;
    SetState(vsPassed);
    PrepareOutputs;
  end
  else
  begin
    // 验证失败，进入修复循�?    Inc(FRetryCount);

    case FRetryCount of
      1: begin
           ShowProgress('验证未通过，AI 正在修复代码（第1轮）...');
           FixAndRetry(mtTier1, Results);
         end;
      2: begin
           ShowProgress('仍未通过，升级模型重试（�?轮）...');
           FixAndRetry(mtTier2, Results);
         end;
      3: begin
           ShowProgress('再次尝试（第3轮，最强模型）...');
           FixAndRetry(mtTier3, Results);
         end;
    else
      // 3轮用完，最终失�?      SetState(vsFailed);
      ShowFailureReport(Results);
    end;
  end;
end;

procedure TFormMain.FixAndRetry(Tier: TModelTier; const Results: TTestResults);
var
  FailedScenarios: string;
begin
  // 整理失败场景�?AI
  FailedScenarios := '';
  for var SR in Results.ScenarioResults do
    if not SR.Passed then
      FailedScenarios := FailedScenarios +
        Format('- %s: %s' + #10, [SR.ID, SR.Detail]);

  TTask.Run(procedure
  var
    FixPrompt   : string;
    FixedCode   : string;
    NewScript   : string;
    ModelName   : string;
  begin
    ModelName := GetModelName(Tier);

    FixPrompt := Format(
      'The following %s code failed verification.' + #10 +
      #10 +
      'Failed scenarios:' + #10 +
      '%s' + #10 +
      #10 +
      'Contract:' + #10 +
      '%s' + #10 +
      #10 +
      'Original code:' + #10 +
      '```%s' + #10 +
      '%s' + #10 +
      '```' + #10 +
      #10 +
      'Fix the code so ALL scenarios pass. Output ONLY the fixed code.',
      [LanguageToString(FSourceLang),
       FailedScenarios,
       ContractToYAML(FContract),
       LanguageToString(FSourceLang),
       FSourceCode]
    );

    FixedCode := CallAI(FixPrompt, ModelName);
    FFixedCode := FixedCode;  // 保存修复后的代码

    // 重新生成测试脚本并运�?    NewScript := GenerateTestScriptFromCode(FixedCode);

    TThread.Synchronize(nil, procedure
    begin
      RunTestScript(NewScript);
    end);
  end);
end;
```

### 6.3 失败报告界面

```pascal
procedure TFormMain.ShowFailureReport(const Results: TTestResults);
begin
  // 显示失败详情面板
  // 内容�?  // 1. 哪些场景失败�?  // 2. 原始错误输出
  // 3. [手动修改代码后重新验证] 按钮
  // 4. [查看 AI 最后一次修复尝试] 按钮
  // 5. [放弃，重新上传] 按钮
  PanelFailure.Visible := True;
  LblFailedScenarios.Text := BuildFailureSummary(Results);
  MemoRawOutput.Text := Results.RawOutput;
end;
```

---

## 7. 模块六：代码文件输出

### 7.1 输出选项界面

验证通过后弹出输出选项�?
```
┌─────────────────────────────────────────�?�? �?验证通过！选择输出方式               �?├─────────────────────────────────────────�?�? 代码文件�?                            �?�? �?原文�?+ 封存标记注释               �?�? �?AI 修正后的新版�?                  �?�?                                        �?�? �?覆盖源文�?                         �?�? �?另存为新文件（推荐）                �?�?                                        �?�?             [确认输出]                 �?└─────────────────────────────────────────�?```

### 7.2 封存标记注释生成

```pascal
function TFormMain.AddSealMark(const SourceCode: string): string;
const
  SEAL_TMPL =
    '# ══════════════════════════════════════�? + #10 +
    '# DeepDevLite 验证封存标记' + #10 +
    '# Verified by DeepDevLite v1.0' + #10 +
    '# 报告编号 Report ID : %s' + #10 +
    '# 验证时间 Verified  : %s' + #10 +
    '# 封存哈希 SHA-256   : %s' + #10 +
    '# 契约文件 Contract  : %s' + #10 +
    '# ══════════════════════════════════════�? + #10;
var
  SealComment: string;
begin
  SealComment := Format(SEAL_TMPL, [
    FReport.ReportID,
    FormatDateTime('yyyy-mm-dd hh:nn:ss', FReport.VerifiedAt),
    FReport.SealHash,
    ExtractFileName(FContractFilePath)
  ]);

  // 根据语言选择注释符号
  case FSourceLang of
    slPython, slRuby:
      Result := SealComment + #10 + SourceCode;
    slJavaScript, slTypeScript, slGo, slJava, slCSharp, slSwift, slKotlin, slRust:
      Result := SealComment.Replace('#', '//') + #10 + SourceCode;
    slPHP:
      Result := '<?php' + #10 +
                SealComment.Replace('#', '//') + #10 +
                SourceCode.Replace('<?php', '');
  else
    Result := SealComment + #10 + SourceCode;
  end;
end;
```

### 7.3 文件保存

```pascal
procedure TFormMain.SaveOutputCode(UseFixedCode, OverwriteSource: Boolean);
var
  OutputCode : string;
  OutputPath : string;
  SaveDlg    : TSaveDialog;
begin
  if UseFixedCode and (FFixedCode <> '') then
    OutputCode := AddSealMark(FFixedCode)
  else
    OutputCode := AddSealMark(FSourceCode);

  if OverwriteSource then
    OutputPath := FSourcePath
  else
  begin
    SaveDlg := TSaveDialog.Create(nil);
    try
      SaveDlg.FileName := ChangeFileExt(
        ExtractFileName(FSourcePath),
        '_verified' + ExtractFileExt(FSourcePath)
      );
      SaveDlg.Filter := 'Source Files|*' + ExtractFileExt(FSourcePath);
      if SaveDlg.Execute then
        OutputPath := SaveDlg.FileName
      else
        Exit;
    finally
      SaveDlg.Free;
    end;
  end;

  TFile.WriteAllText(OutputPath, OutputCode, TEncoding.UTF8);
  ShowMessage('代码文件已保存：' + ExtractFileName(OutputPath));
end;
```

---

## 8. 模块七：契约文件输出�?yaml�?
```pascal
function TFormMain.ContractToYAML(const Contract: TContract): string;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Add('# DeepDevLite 契约文件');
    SL.Add('# 生成时间: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Contract.CreatedAt));
    SL.Add('# 确认时间: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Contract.ConfirmedAt));
    SL.Add('---');
    SL.Add('contract:');
    SL.Add(Format('  title: "%s"', [Contract.Title]));
    SL.Add(Format('  language: "%s"', [LanguageToString(Contract.Language)]));
    SL.Add(Format('  purpose: "%s"', [Contract.Purpose]));
    SL.Add('  scenarios:');

    for var S in Contract.Scenarios do
    begin
      SL.Add(Format('    - id: %s', [S.ID]));
      SL.Add(Format('      desc: "%s"', [S.Desc]));
      SL.Add(Format('      type: %s', [ScenTypeToString(S.ScenType)]));
      SL.Add(Format('      input: "%s"', [S.Input]));
      SL.Add(Format('      expected: "%s"', [S.Expected]));
    end;

    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

procedure TFormMain.SaveContractFile;
var
  ContractPath: string;
begin
  ContractPath := ChangeFileExt(FSourcePath, '.contract.yaml');
  TFile.WriteAllText(ContractPath, ContractToYAML(FContract), TEncoding.UTF8);
  FContractFilePath := ContractPath;
end;
```

---

## 9. 模块八：封存记录

```pascal
uses System.Hash, System.DateUtils;

type
  TSealRecord = record
    ReportID    : string;
    SourceFile  : string;
    SourceHash  : string;   // 源文件哈�?    SealHash    : string;   // 整体封存哈希
    SealedAt    : TDateTime;
    ModelUsed   : string;
    RetryCount  : Integer;
    ContractFile: string;
  end;

function TFormMain.GenerateSealRecord: TSealRecord;
var
  Raw: string;
begin
  Result.ReportID     := FReport.ReportID;
  Result.SourceFile   := ExtractFileName(FSourcePath);
  Result.SourceHash   := THashSHA2.GetHashString(FSourceCode);
  Result.SealedAt     := Now;
  Result.ModelUsed    := GetModelName(TModelTier(FRetryCount));
  Result.RetryCount   := FRetryCount;
  Result.ContractFile := ExtractFileName(FContractFilePath);

  // 整体封存哈希：源文件哈希 + 契约 + 时间
  Raw := Result.SourceHash
       + ContractToYAML(FContract)
       + DateTimeToStr(Result.SealedAt);
  Result.SealHash := THashSHA2.GetHashString(Raw);
end;

procedure TFormMain.SaveSealRecord(const Seal: TSealRecord);
var
  SL          : TStringList;
  SealPath    : string;
begin
  SL := TStringList.Create;
  try
    SL.Add('# DeepDevLite 封存记录');
    SL.Add(Format('report_id    : %s', [Seal.ReportID]));
    SL.Add(Format('source_file  : %s', [Seal.SourceFile]));
    SL.Add(Format('source_hash  : %s', [Seal.SourceHash]));
    SL.Add(Format('seal_hash    : %s', [Seal.SealHash]));
    SL.Add(Format('sealed_at    : %s', [DateTimeToStr(Seal.SealedAt)]));
    SL.Add(Format('model_used   : %s', [Seal.ModelUsed]));
    SL.Add(Format('retry_count  : %d', [Seal.RetryCount]));
    SL.Add(Format('contract_file: %s', [Seal.ContractFile]));

    SealPath := ChangeFileExt(FSourcePath, '.seal.txt');
    SL.SaveToFile(SealPath, TEncoding.UTF8);
  finally
    SL.Free;
  end;
end;
```

---

## 10. AI 模型调用规范

### 10.1 统一调用接口

```pascal
type
  TAIProvider = (apClaude, apOpenAI, apGemini, apCustom);

  TAIConfig = record
    Provider   : TAIProvider;
    APIKey     : string;
    BaseURL    : string;    // 自定义端�?    TimeoutSec : Integer;
  end;

function TFormMain.CallAI(const Prompt, ModelName: string): string;
var
  HTTP     : THTTPClient;
  Request  : TStringStream;
  Response : IHTTPResponse;
  JSON     : TJSONObject;
begin
  HTTP := THTTPClient.Create;
  try
    HTTP.ConnectionTimeout := FAIConfig.TimeoutSec * 1000;
    HTTP.ResponseTimeout   := 120000;  // 2分钟

    // 构建请求体（�?Claude API 为例�?    JSON := TJSONObject.Create;
    try
      JSON.AddPair('model', ModelName);
      JSON.AddPair('max_tokens', TJSONNumber.Create(4096));
      var MsgArray := TJSONArray.Create;
      var MsgObj := TJSONObject.Create;
      MsgObj.AddPair('role', 'user');
      MsgObj.AddPair('content', Prompt);
      MsgArray.Add(MsgObj);
      JSON.AddPair('messages', MsgArray);

      Request := TStringStream.Create(JSON.ToString, TEncoding.UTF8);
      try
        HTTP.CustomHeaders['x-api-key']         := FAIConfig.APIKey;
        HTTP.CustomHeaders['anthropic-version']  := '2023-06-01';
        HTTP.ContentType := 'application/json';

        Response := HTTP.Post(FAIConfig.BaseURL + '/v1/messages', Request);

        if Response.StatusCode = 200 then
          Result := ExtractAIText(Response.ContentAsString)
        else
          raise Exception.CreateFmt('AI 调用失败: %d %s',
            [Response.StatusCode, Response.ContentAsString]);
      finally
        Request.Free;
      end;
    finally
      JSON.Free;
    end;
  finally
    HTTP.Free;
  end;
end;

function TFormMain.ExtractAIText(const ResponseJSON: string): string;
var
  JSON    : TJSONObject;
  Content : TJSONArray;
begin
  JSON := TJSONObject.ParseJSONValue(ResponseJSON) as TJSONObject;
  try
    Content := JSON.GetValue<TJSONArray>('content');
    Result  := Content.Items[0].GetValue<string>('text');
  finally
    JSON.Free;
  end;
end;
```

### 10.2 AI 配置界面

设置页面提供�?- API Key 输入框（密文显示�?- Provider 选择（Claude / OpenAI / 自定义）
- 自定�?BaseURL 输入
- 三个模型等级的模型名称配�?- 连接测试按钮

---

## 11. 本地环境检�?
### 11.1 启动时检�?
```pascal
type
  TEnvStatus = record
    Lang      : TSourceLanguage;
    Available : Boolean;
    Version   : string;
    Command   : string;
  end;

procedure TFormMain.DetectLocalEnvironments;
const
  CHECK_CMDS: array[0..6] of record
    Lang: TSourceLanguage; Cmd: string; VersionFlag: string;
  end = (
    (Lang: slPython;     Cmd: 'python';  VersionFlag: '--version'),
    (Lang: slJavaScript; Cmd: 'node';    VersionFlag: '--version'),
    (Lang: slTypeScript; Cmd: 'ts-node'; VersionFlag: '--version'),
    (Lang: slGo;         Cmd: 'go';      VersionFlag: 'version'),
    (Lang: slJava;       Cmd: 'java';    VersionFlag: '-version'),
    (Lang: slCSharp;     Cmd: 'dotnet';  VersionFlag: '--version'),
    (Lang: slRuby;       Cmd: 'ruby';    VersionFlag: '--version')
  );
var
  Output  : string;
  Status  : TEnvStatus;
begin
  FEnvStatuses := [];
  for var C in CHECK_CMDS do
  begin
    Status.Lang      := C.Lang;
    Status.Command   := C.Cmd;
    ExecuteProcess(C.Cmd + ' ' + C.VersionFlag, Output, 5);
    Status.Available := Output <> '';
    Status.Version   := Trim(Output.Split([#10])[0]);
    FEnvStatuses := FEnvStatuses + [Status];
  end;
end;
```

### 11.2 环境缺失提示

当用户上传某种语言文件，但本地未检测到对应运行时：

```
┌─────────────────────────────────────────────�?�? ⚠️ 未检测到 Node.js 运行环境               �?�?                                            �?�? 验证 JavaScript 代码需�?Node.js�?        �?�? 请安装后重试，或切换到已安装语言�?         �?�?                                            �?�? [前往 nodejs.org]        [仍然继续]        �?└─────────────────────────────────────────────�?```

---

## 12. 窗体与状态机设计

### 12.1 主窗体布局

```
┌─────────────────────────────────────────────────────────�?�? DeepDevLite                              [设置] [关于]   �?├──────────────┬──────────────────────────────────────────�?�?             �?                                         �?�? 文件�?     �? 主工作区（根据状态切换内容）             �?�? TTreeView   �?                                         �?�? 180px       �? vsIdle:         拖拽上传引导界面         �?�?             �? vsAnalyzing:    进度动画                 �?�?             �? vsContractReady: 契约编辑�?             �?�?             �? vsRunningTest:  实时日志输出             �?�?             �? vsFixing:       修复进度（N/3�?         �?�?             �? vsPassed:       输出选项面板             �?�?             �? vsFailed:       失败报告面板             �?�?             �?                                         �?├──────────────┴──────────────────────────────────────────�?�? 状态栏：当前文�?| 语言 | 状�?| 重试次数              �?└─────────────────────────────────────────────────────────�?```

### 12.2 状态切�?
```pascal
procedure TFormMain.SetState(State: TVerifyState);
begin
  FCurrentState := State;

  // 隐藏所有内容面�?  PanelIdle.Visible          := False;
  PanelAnalyzing.Visible     := False;
  PanelContract.Visible      := False;
  PanelRunning.Visible       := False;
  PanelPassed.Visible        := False;
  PanelFailed.Visible        := False;

  // 显示对应面板
  case State of
    vsIdle:          PanelIdle.Visible      := True;
    vsAnalyzing,
    vsGeneratingTest: PanelAnalyzing.Visible := True;
    vsContractReady: PanelContract.Visible  := True;
    vsRunningTest,
    vsFixing:        PanelRunning.Visible   := True;
    vsPassed:        PanelPassed.Visible    := True;
    vsFailed:        PanelFailed.Visible    := True;
  end;

  UpdateStatusBar;
end;
```

### 12.3 进度日志（运行时实时输出�?
```pascal
procedure TFormMain.AppendLog(const Msg: string);
begin
  TThread.Synchronize(nil, procedure
  begin
    MemoLog.Lines.Add(Format('[%s] %s',
      [FormatDateTime('hh:nn:ss', Now), Msg]));
    MemoLog.GoToTextEnd;  // 自动滚动到底�?  end);
end;
```

---

## 13. 开发顺序建�?
| 阶段 | 内容 | 优先�?|
|------|------|--------|
| **�?�?* | 数据模型 + 状态机骨架 + 主窗体布局 | 🔴 核心 |
| **�?�?* | 文件输入三种方式 + 语言检�?+ 本地环境检�?| 🔴 核心 |
| **�?�?* | AI 调用接口 + 契约分析 + 契约编辑�?| 🔴 核心 |
| **�?�?* | 测试脚本生成 + 本地执行 + 结果解析 | 🔴 核心 |
| **�?�?* | 自动修复循环�?轮赛马）| 🟡 重要 |
| **�?�?* | 代码文件输出 + 契约文件 + 封存记录 | 🟡 重要 |
| **�?�?* | 验证报告（PDF/PNG�? 朋友圈卡片（�?Dev-Spec.md）| 🟡 重要 |
| **�?�?* | 设置页面 + UI 打磨 + 跨平台测�?| 🟢 完善 |

---

## 附录 A：支持语言列表

| 语言 | 扩展�?| 运行命令 | 测试框架建议 |
|------|--------|----------|-------------|
| Python | .py | python | 内联 assert |
| JavaScript | .js | node | 内联 console |
| TypeScript | .ts | ts-node | 内联 console |
| Go | .go | go run | 内联 fmt |
| Java | .java | java | JUnit 内联 |
| C# | .cs | dotnet script | 内联 Console |
| Ruby | .rb | ruby | 内联 puts |
| PHP | .php | php | 内联 echo |
| Swift | .swift | swift | 内联 print |
| Rust | .rs | cargo script | 内联 println! |
| Dart | .dart | dart | 内联 print |
| Kotlin | .kt | kotlin | 内联 println |

## 附录 B：输出文件命名规�?
| 文件 | 命名规则 | 示例 |
|------|----------|------|
| 封存代码 | `原名_verified.ext` | `login_verified.py` |
| 契约文件 | `原名.contract.yaml` | `login.contract.yaml` |
| 封存记录 | `原名.seal.txt` | `login.seal.txt` |
| 验证报告 | `DeepDevLite_报告ID.pdf` | `DeepDevLite_PRG-20260220-0042.pdf` |
| 朋友圈卡�?| `DeepDevLite_Card_日期.png` | `DeepDevLite_Card_20260220.png` |
