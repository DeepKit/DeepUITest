# Delphi 程序开发约定指南（AI 可执行版）

> **版本**: 3.0  
> **更新**: 2026-05-14  
> **基线**: Delphi 13.1 Florence / Compiler 37 / DeepBase / Windows VCL 优先  
> **定位**: 给 AI 和开发者执行的 Delphi 桌面软件开发硬约束。每条关键规则必须能被编译、脚本、测试或审查验证。

---

## 0. 总原则

新 Delphi 桌面软件默认遵守：

```text
DeepBase 优先；
Delphi 13.1 语法优先；
Windows 桌面软件 VCL 优先；
目录二级受控；
AI 修改必须经过 PowerShell 门禁、编译和测试。
```

一句话：

```text
用 DeepBase 承担基础设施；
用 VCL 发挥 Delphi 原生桌面优势；
用 Delphi 13.1 写现代、类型安全、可维护代码；
用可执行门禁约束 AI。
```

本指南替代旧的 UniBase / Assayer 项目约定。新项目和重构项目默认使用 DeepBase。旧项目中仍存在 UniBase 时，应在迁移计划中逐步替换，不应在新代码中继续扩散 UniBase API。

---

## 1. AI 自检流程

AI 每次改 Delphi 代码前必须执行：

```text
1. 读取本文件前 80 行，确认版本为 3.0。
2. 确认项目基线：Delphi 13.1 / DeepBase / VCL 或 FMX。
3. 读取目标文件 interface uses 和 implementation uses。
4. 判断目标文件所在目录和架构层。
5. 修改前运行相关检查脚本。
6. 修改后运行 check-all、编译、测试。
7. 汇报修改文件、检查结果、未运行项和风险。
```

AI 禁止：

- 在不确认项目基线的情况下套用旧 UniBase / FMX 规则；
- 编造 Delphi 不存在的语法，例如 C# 风格 `async/await`；
- 在 UI 线程写长耗时 LLM、网络、扫描、数据库任务；
- 绕过 DeepBase Security 保存密钥；
- 直接修改 DeepBase 底层适配器；
- 为了快速实现而自建已有 DeepBase 能力。

---

## 2. Delphi 13.1 基线

### 2.1 编译器和平台

标准基线：

```text
RAD Studio 13.1 Florence
Compiler: 37.0
Conditional symbol: VER370
Primary platform: Windows Win64
Optional platform: Win32 / Windows ARM64EC / FMX cross-platform
```

编译器入口不得写死旧路径。优先通过 `%BDS%` 或环境脚本发现：

```powershell
$BdsBin = Join-Path $env:BDS 'bin'
& (Join-Path $BdsBin 'dcc64.exe')
```

平台矩阵：

| 平台 | 编译器 | 何时要求 |
|---|---|---|
| Win64 | `dcc64` / MSBuild Win64 | 默认必须 |
| Win32 | `dcc32` / MSBuild Win32 | 项目声明支持时 |
| Windows ARM64EC | `dccarm64ec` | 项目声明支持时 |
| macOS / Linux / iOS / Android | 对应 FMX 工具链 | FMX 跨平台项目声明支持时 |

### 2.2 推荐编译门禁

```powershell
cmd /c "`"$env:BDS\bin\rsvars.bat`" && msbuild MyApp.dproj /t:Build /p:Config=Debug /p:Platform=Win64"
```

门禁：

- 编译错误：0；
- 新增 warning：0；
- W1057 / W1058 编码相关 warning：0；
- hint 可以有基线，但新增不得增加；
- 发布前至少跑 Release Win64。

---

## 3. DeepBase 基础设施硬约束

### 3.1 标准初始化

`.dpr` 标准入口：

```delphi
program MyApp;

uses
  Vcl.Forms,
  DeepBase.Manager,
  DeepBase.Persistence.Manager.FireDAC,
  App.MainForm in 'src\app\App.MainForm.pas' {MainForm};

begin
  DeepBase.InitializeOrRaise;
  try
    Application.Initialize;
    Application.MainFormOnTaskbar := True;
    Application.CreateForm(TMainForm, MainForm);
    Application.Run;
  finally
    DeepBase.Finalize;
  end;
end.
```

规则：

- 必须引用 `DeepBase.Persistence.Manager.FireDAC`，否则 DB1 连接适配器可能未注册；
- 初始化失败用 DeepBase 异常和日志处理，不吞异常；
- 关闭时调用 `DeepBase.Finalize`；
- 不在业务窗体里重复做框架初始化。

### 3.2 包依赖顺序

推荐包顺序：

```text
DeepBaseCore
DeepBaseServices
DeepBasePersistence
DeepBaseFeatures
DeepBaseVCL / DeepBaseFMX
dclDeepBaseVCL / dclDeepBaseFMX
```

规则：

- 运行时项目不得依赖 `dclDeepBaseVCL` 或 `dclDeepBaseFMX`；
- 需要 LLM、Commerce、BrowserAutomation、Speech、AutoUpdate 时接 `DeepBaseFeatures`；
- 新 VCL 桌面工具优先接 `DeepBaseVCL` 和 DeepShell；
- 不在下游项目私改 DeepBase Core / LLM / DB 适配层。

### 3.3 root.txt 和 ConfigDB

DeepBase 唯一外部配置文件是：

```text
root.txt
```

规则：

- `root.txt` 位于 EXE 同目录；
- 第一行是项目根目录绝对路径；
- 禁止 INI 段落、JSON、相对路径、引号；
- DeepBase 自动定位 `{AppName}Config.db`；
- 配置、布局、MRU、主题、语言、日志、Secret、LLM 配置、账号授权状态进入 DB1 ConfigDB。

检测：

```powershell
$root = Get-Content .\root.txt -TotalCount 1
if ($root -notmatch '^[A-Za-z]:\\') { throw 'root.txt must contain absolute Windows path' }
```

---

## 4. DB1 / DB2 / DB3 / DB4 分层

| 数据库 | 位置 | 用途 | 禁止 |
|---|---|---|---|
| DB1 ConfigDB | 本地 SQLite | DeepBase 配置、日志、i18n、FormState、MRU、Hotkeys、Secrets、LLM 配置和调用历史 | 生产用户、订单、支付流水、业务主数据 |
| DB2 本地业务库 | 本地 SQLite | 单机业务数据、缓存、离线数据 | 支付密钥、生产后端数据 |
| DB3 远程业务库 | PostgreSQL/MySQL/其他 | 多端共享业务数据 | 绕过统一 Repository / DB facade |
| DB4 生产后端库 | 服务端 | 用户、身份、商品、订单、支付、权益、通知原文 | 客户端直连 |

硬规则：

- 客户端不直连 DB4；
- 客户端不保存支付密钥；
- 客户端不自行把订单改成 `paid`；
- 业务数据不塞进 DB1；
- 项目规格文件、AI 工件、可提交项目产物不塞进 DB1，应进入项目目录。

---

## 5. Security / Secret

敏感信息统一走：

```delphi
DeepBase.Security.SaveSecret('LLM.Default.ApiKey', ApiKey);
ApiKey := DeepBase.Security.LoadSecret('LLM.Default.ApiKey');
```

规则：

- Windows 使用 DPAPI 用户作用域；
- 跨平台使用 UBS2；
- API Key、Token、Speech Key、支付相关密钥不得明文写入 Settings、日志、业务表、INI、JSON；
- 禁止自制密码学；
- SHA 可用于校验和摘要，但不得把弱哈希当密码保护；
- 禁止硬编码密钥、连接串、服务端管理 token。

检测建议：

```powershell
$patterns = 'password|passwd|secret|token|apikey|api_key|access_token|refresh_token|User ID=|Password='
Get-ChildItem src -Recurse -Include *.pas,*.dpr,*.inc |
  Select-String -Pattern $patterns -CaseSensitive:$false
```

命中后必须人工判断，不允许 AI 自行忽略。

---

## 6. DeepBase LLM 规范

下游只走 DeepBase LLM facade / API。

禁止：

- 私改 `DeepBase.LLM*.pas`；
- 私改 SQLite / PostgreSQL 统一适配层；
- 明文保存 LLM API Key；
- UI 线程同步调用长耗时 LLM；
- 自行发明模型 tier 名称。

五槽模型：

| 槽位 | tier | 用途 |
|---|---|---|
| 聪明 | `TierSmart` / `smart` | 高质量推理、复杂任务 |
| 平衡 | `TierBalanced` / `balanced` | 默认处理 |
| 快速 | `TierFast` / `fast` | 低延迟轻量任务 |
| 生图 | `TierImageGen` / `image_gen` | 文生图 |
| 图片兜底 | `TierImageFallback` / `vision_fallback` | 视觉失败兜底 |

示例：

```delphi
Store.SetTierModels(string(TierSmart), ['gpt-4.1']);
Store.SetTierModels(string(TierBalanced), ['gpt-4.1-mini']);
Store.SetTierModels(string(TierFast), ['gpt-4.1-nano']);
Store.SetTierModels(string(TierImageGen), ['gpt-image-1']);
Store.SetTierModels(string(TierImageFallback), ['gpt-4.1-mini']);
```

UI 线程规则：

```text
LLM 请求必须后台执行；
UI 只显示进度、取消、结果；
异常必须回到统一日志和状态系统。
```

---

## 7. Commerce / 账号 / 权限

桌面端账号、授权、付费升级、更新优先使用：

- `TDeepKitSafeClient`
- `TDeepBaseDesktopLifecycle`
- `DeepBase.Commerce.Permissions`
- `DeepBase.Commerce.UpgradeFlow`

规则：

- 云端账号由 `deepkit.top` 或项目指定 DeepKit 后端提供；
- 客户端不自建账号系统；
- 客户端不直连 DB4；
- 生产禁止 `TInMemoryCommerceStorage`；
- 付费功能入口统一用 `HasFeature`、`RequireFeature`、`ConsumeQuota`、`RefreshLicenseSnapshot`；
- 第一版免费功能不得强制登录，除非产品明确要求云端服务。

---

## 8. BrowserAutomation / WebView2

浏览器自动化统一使用：

- `DeepBase.BrowserAutomation`
- `DeepBase.Browser.*`
- `DeepBase.Browser.Engine.WebView2`

适用：

- 内嵌 HTML / Markdown / 文档预览；
- OAuth / 登录页面；
- 可视化图谱；
- 需要 JS Bridge 的交互审阅页；
- 自动化测试或辅助外部网页操作。

规则：

- 默认后端 WebView2；
- LLM 流式输出等待使用 `TBrowserResponseWaiter`，禁止固定 `Sleep`；
- 选择器失败用 `DeepBase.Browser.Selectors` 自愈；
- DOM 失败可用 `DeepBase.Browser.Vision` 兜底；
- JS 注入模板进入 `js_scripts` 表，通过 `DeepBase.Browser.ScriptStore` 管理；
- 生产 WebView2 用户数据目录必须显式指定，避免进程锁冲突。

---

## 9. DeepShell VCL 新程序规范

Windows VCL 工具软件默认从 DeepShell 起步：

```delphi
type
  TMainForm = class(TDeepMainForm)
  protected
    procedure RegisterServices; override;
    procedure RegisterCommands; override;
    procedure RegisterProviders; override;
  end;
```

规则：

- 不从空 `TForm` 重复搭工具栏、日志、设置、MRU、布局；
- 主窗体只负责注册 Services / Commands / Providers；
- 业务内容通过 Provider 注入；
- 状态和日志走 DeepBase / DeepShell 统一接口；
- 高风险命令声明 `RiskLevel`、`GateKey`、`PurposeKey`；
- 设置页只追加业务配置；
- 需要主工作区时返回 Frame、HTML、WebView2 adapter 或自定义控件。

---

## 10. Delphi 13.1 现代语法规范

### 10.1 三元 if 表达式

允许用于短表达式：

```delphi
Caption := if IsAdmin then 'Admin' else 'User';
```

禁止：

- 嵌套三元表达式；
- 在三元表达式里做副作用操作；
- 替代复杂 `if begin end` 分支。

### 10.2 NameOf

用于符号名，替代手写字符串：

```delphi
Logger.Info(NameOf(TUser.Name));
```

禁止用于业务文案和用户可见文本。

### 10.3 is not / not in

```delphi
if Sender is not TButton then Exit;
if C not in ['A'..'Z'] then Exit;
```

优先用于提高可读性。

### 10.4 noreturn

```delphi
procedure Fail(const Msg: string); noreturn;
begin
  raise Exception.Create(Msg);
end;
```

`noreturn` 方法不得存在正常返回路径。

### 10.5 PUSHOPT / POPOPT

仅在必须临时改变编译开关时使用，且必须成对出现：

```delphi
{$PUSHOPT W+}
...
{$POPOPT}
```

---

## 11. 类型系统规范

### 11.1 泛型集合

优先使用：

- `System.Generics.Collections.TList<T>`
- `TObjectList<T>`
- `TDictionary<TKey,TValue>`
- `TArray<T>`

规则：

- `TObjectList<T>` 必须明确 `OwnsObjects`；
- `TDictionary<string, T>` 必须说明大小写敏感性；
- 不返回所有权不明的裸对象列表；
- 公共 API 中避免过深嵌套泛型；
- 新代码禁止使用非泛型 `TList` 承载业务对象。

### 11.2 class / record / interface

| 类型 | 适用 |
|---|---|
| class | 有身份、生命周期、继承、多态 |
| record | 值语义、小型 DTO、不可变值对象 |
| interface | 服务契约、依赖注入、可替换实现 |

managed record 可定义 `Initialize` / `Finalize` / `Assign`，但禁止在其中做 UI、线程、网络、数据库和重 IO。

### 11.3 Attribute / RTTI

规则：

- Attribute 只用于序列化、ORM、DI、测试、命令注册等元数据；
- 不用 Attribute 承载业务流程；
- Attribute 类名以 `Attribute` 结尾；
- 依赖 RTTI 的类型必须明确 RTTI 设置或 `$M+`；
- 不假设所有类型都有完整 RTTI。

---

## 12. 匿名方法、闭包与异步

Delphi 没有 C# 风格 `async/await`。AI 禁止编造类似语法。

允许：

- `TTask.Run`
- `IFuture<T>`
- `TParallel`
- DeepBase WorkerQueue / Resilience async

规则：

- UI 线程不得 `Sleep`、`WaitFor`、同步网络请求、同步 LLM；
- 后台任务更新 UI 必须 `TThread.Queue` 或 `TThread.Synchronize`；
- 匿名方法捕获 `Self` 前必须确认生命周期；
- 异步闭包不得捕获即将释放的局部对象；
- 异步异常必须捕获、记录并反馈到 UI 状态；
- 长任务必须有取消机制。

示例：

```delphi
TTask.Run(
  procedure
  begin
    try
      DoLongWork;
      TThread.Queue(nil,
        procedure
        begin
          Status.Info('Done');
        end);
    except
      on E: Exception do
        DeepBase.Logger.Error('Background task failed', E, 'Worker');
    end;
  end);
```

---

## 13. Unicode、编码与文件 IO

源码规则：

- `.pas/.dpr/.inc`：UTF-8 with BOM；
- `.dfm/.fmx`：优先 IDE 保存，人工编辑只允许文本格式；
- 禁止 ANSI 中文源码；
- 出现 W1057 / W1058 直接失败；
- `string` 默认为 UnicodeString。

文件 IO：

```delphi
TFile.ReadAllText(Path, TEncoding.UTF8);
TFile.WriteAllText(Path, Text, TEncoding.UTF8);
```

禁止：

- 依赖系统默认 ANSI code page；
- 新代码使用 `AnsiString`、`ShortString`、`PAnsiChar`，除非是旧 DLL 或外部协议边界；
- 把 Unicode 字符当单字节处理。

字符集合判断使用：

```delphi
if CharInSet(C, ['A'..'Z']) then ...
```

---

## 14. 桌面软件技术路线

默认路线：

```text
Windows 原生桌面：VCL
跨平台 UI：FMX
复杂 HTML / 文档 / 图谱：WebView2
高性能自绘 / 图表：Skia
大规模树表：VirtualTreeView
```

总原则：

```text
Delphi 桌面软件应优先发挥 VCL 的原生 Windows 能力、
设计时组件化能力和高响应速度优势；
只有原生控件不适合表达时，才引入 WebView2、Skia 或自绘方案。
```

---

## 15. VCL 桌面开发规范

### 15.1 Delphi / VCL 的优势

开发 Windows 桌面软件时，Delphi 的优势是：

- 原生 Windows 控件和消息模型；
- 快速启动和低运行时负担；
- Form Designer 设计时效率；
- 组件化复用；
- 强类型事件和属性系统；
- 直接系统集成；
- Win32 / Win64 / ARM64EC 编译能力；
- 调试、部署、维护成本低。

### 15.2 设计时优先

优先在 `.dfm` 中创建：

- Form；
- Frame；
- Menu；
- Toolbar；
- ActionList；
- ImageList；
- StatusBar；
- Panel；
- Splitter；
- PageControl；
- 常规输入控件和按钮。

禁止大量运行时手搓常规 UI。运行时创建只允许：

- 动态插件 UI；
- 虚拟化列表项；
- 运行期不可预知的动态表单；
- 明确标注 `RUNTIME-ALLOWED` 的封装工厂。

### 15.3 Action 体系

菜单、工具栏、按钮、快捷键、右键菜单优先绑定 `TAction`。

`TAction` 统一管理：

- Caption；
- Hint；
- Enabled；
- Checked；
- Shortcut；
- 图标；
- 权限状态。

### 15.4 Frame 体系

规则：

- 大窗口拆成 `TFrame`；
- Form 负责布局和生命周期；
- Frame 负责局部 UI 和交互；
- Controller / Service 负责业务；
- DataModule 管理非 UI 组件。

### 15.5 大数据控件

大树、大表、日志、文件树、需求树优先：

```text
VirtualTreeView
```

不要让标准 `TTreeView` / `TListView` 承载大量数据导致卡顿。

### 15.6 WebView2 / Skia / SVG

WebView2 适用：

- HTML / Markdown 预览；
- 文档审阅；
- OAuth；
- 图谱；
- 复杂网页能力。

WebView2 不适用：

- 普通业务表单；
- 常规设置页；
- 主导航；
- 可用原生控件轻松表达的界面。

Skia 适用：

- 图表；
- 自定义绘制；
- 矢量预览；
- 高质量渲染。

SVG 适用：

- 高 DPI 图标；
- 深浅主题图标；
- 工具栏和菜单图标。

### 15.7 Windows 系统集成

桌面软件可按需支持：

- 托盘；
- Jump List；
- 文件关联；
- 右键菜单；
- 剪贴板；
- 拖放；
- 全局热键；
- 通知；
- ShellExecute；
- COM / OLE；
- Credential Manager；
- 注册表。

必须避免：

- 业务逻辑散落在系统事件里；
- Shell 命令拼接未转义用户输入；
- 高权限操作无确认。

### 15.8 DPI、主题和发布

规则：

- 支持 Per-Monitor DPI；
- 设计时检查 100% / 125% / 150% / 200%；
- 图标优先 SVG；
- 暗色模式策略明确；
- 安装包考虑 WebView2 Runtime；
- 发布版本必须有版本号、签名、更新策略、卸载清理、日志目录和崩溃报告方案。

---

## 16. 目录结构规范

目录允许二级，但必须受控。

总规则：

```text
一级目录固定；
二级目录白名单；
三级目录默认禁止。
```

### 16.1 一级目录

```text
src/          主程序源码
packages/     DeepBase / 可复用包
tests/        DUnitX / 集成测试 / 测试资源
resources/    图标、语言包、模板、SQL、DFM/FMX资源
samples/      示例工程
docs/         项目文档
scripts/      构建、检查、迁移脚本
tools/        本项目专用工具
build/        构建输出，可忽略
bin/          可执行输出，可忽略
```

### 16.2 src 二级目录

```text
src/
  app/
  views-vcl/
  views-fmx/
  controllers/
  models/
  data/
  services/
  core/
  adapters/
```

规则：

- 目录表达架构层，不表达临时任务；
- 禁止 `common`, `misc`, `old`, `new`, `backup`, `temp`, `rewrite`, `ai`；
- `views-vcl` 只能引用 `Vcl.*`；
- `views-fmx` 只能引用 `FMX.*`；
- 公共业务逻辑放 `controllers/services/models/core`；
- DeepBase 包不放进业务 `src/`。

### 16.3 单元命名

推荐命名空间前缀：

```text
App.*
View.*
Frame.*
Ctrl.*
Model.*
Data.*
Service.*
Core.*
Adapter.*
DeepBase.*
```

示例：

```text
View.Main.pas
Frame.RequirementTree.pas
Ctrl.Project.pas
Model.RequirementNode.pas
Data.ProjectRepo.pas
Service.Scan.pas
Core.PathRules.pas
Adapter.DeepKit.pas
```

---

## 17. 分层和 uses 规则

推荐方向：

```text
View/Frame  -> Ctrl, Model DTO, UI 库
Ctrl        -> Service, Model
Service     -> Data, Model, Core, DeepBase facade
Data        -> Model, Core, FireDAC, DeepBase DB facade
Model       -> System.*
Core        -> System.*，禁止 UI，谨慎 DB
Adapter     -> 外部 SDK + Model/Core
```

禁止：

- Model uses View / Ctrl / Data / Service；
- Data uses View / Ctrl；
- Ctrl uses Vcl / FMX / FireDAC；
- Service uses Vcl / FMX；
- Core uses 业务 View / Ctrl；
- Package 反向引用 App 工程单元；
- View 直接操作 DB；
- View 直接引用全局 DataModule。

---

## 18. Form / Frame 大小限制

| 指标 | 新建文件 | 存量迁移中 |
|---|---:|---:|
| Form / Frame `.pas` 行数 | 500 | 3000 |
| private 字段数 | 10 | 15 |
| 方法数 | 20 | 30 |
| 单方法行数 | 50 | 80 |
| 未标注运行时控件创建 | 0 | 0 |

规则：

- 超标 Form 禁止继续追加业务代码；
- 应拆到 Frame、Controller、Service；
- 大方法拆分；
- 运行时控件创建必须集中封装并标注 `RUNTIME-ALLOWED`。

---

## 19. 全局状态和依赖注入

禁止在 interface 部分声明可变全局变量：

```delphi
var
  MainForm: TMainForm;   // VCL 自动变量除 .dpr / 主窗体单元外不扩散
  DM: TDataModule;       // 禁止业务代码直接引用
```

规则：

- 业务服务通过构造函数注入；
- UI 通过 Controller / Service 接口访问业务；
- DataModule 只做组件容器，不做全局业务入口；
- 跨模块状态放服务或模型，不放全局变量。

---

## 20. 异常、日志和诊断

禁止：

```delphi
try
  ...
except
end;
```

最低要求：

```delphi
except
  on E: Exception do
    DeepBase.Logger.Warn('ModuleName failed: ' + E.Message, 'ModuleName');
end;
```

更推荐：

```delphi
except
  on E: Exception do
    DeepBase.Logger.Error('Scan failed', E, 'DeepSpec.Scan');
end;
```

规则：

- 后台任务异常必须记录；
- UI 层不直接展示内部异常细节；
- 用户可见错误用友好文案；
- 诊断日志保留技术细节；
- 发布版应有崩溃报告方案，优先 madExcept 或项目已验证方案。

---

## 21. 数据库访问规则

View 和 Controller 不直接写 SQL。

允许：

- Data / Repository 层访问 FireDAC；
- Service 通过 Repository 访问数据；
- DeepBase DB facade / DoQry / Repository 统一管理查询。

禁止：

- UI 层 `TFDQuery`；
- UI 层 `SQL.Text :=`；
- 字符串拼接 SQL；
- 未参数化查询；
- 全局 DM 被 View 直接调用。

---

## 22. 资源和第三方库

优先使用已安装和框架已有能力。

常用库：

| 库 | 用途 | 规则 |
|---|---|---|
| DeepBase | 基础设施 | 默认优先 |
| VirtualTreeView | 大树 / 大表 | VCL 大数据首选 |
| SVGIconImageList | SVG 图标 | 高 DPI 图标 |
| Skia4Delphi / 内置 Skia | 图表 / 自绘 | 不重写普通控件 |
| DUnitX | 单元测试 | 测试默认 |
| madExcept | 崩溃诊断 | 发布建议 |
| WebView2 / BrowserAutomation | HTML / 网页 / JS Bridge | 不替代普通 UI |

内存管理：

- Delphi 13.1 默认使用 RTL 内置内存管理；
- 内存诊断优先 `ReportMemoryLeaksOnShutdown`、madExcept、FastMM5 或项目已验证方案；
- FastMM4 仅用于明确兼容的旧 Win32 场景。

---

## 23. 质量门禁

指南必须配套工具，而不是只靠文字。

推荐结构：

```text
quality.json
tools/quality/check-all.ps1
tools/quality/check-architecture.ps1
tools/quality/check-encoding.ps1
tools/quality/check-exceptions.ps1
tools/quality/check-security.ps1
tools/quality/check-size.ps1
tools/quality/build-delphi.ps1
tools/quality/test-dunitx.ps1
```

唯一入口：

```powershell
pwsh -File tools/quality/check-all.ps1 -ProjectRoot . -Mode Changed
pwsh -File tools/quality/check-all.ps1 -ProjectRoot . -Mode Full
```

报告必须包含：

```text
PASS/FAIL
rule_id
file
line
severity
fix_hint
```

### 23.1 P0 必须失败

- 编译失败；
- 测试失败；
- 非 UTF-8 BOM；
- 新增 W1057 / W1058；
- View 直连 DB；
- Controller 引用 UI；
- 空 except；
- 裸 SQL；
- 硬编码密钥；
- 全局 DM 引用；
- UI 线程同步 LLM / Sleep / WaitFor。

### 23.2 P1 警告但需说明

- Form 超行数；
- 方法过长；
- 新增依赖；
- 运行时创建控件但带 `RUNTIME-ALLOWED`；
- diff 超 200 行；
- `.pas/.dfm/.fmx` 混合提交。

### 23.3 P2 建议

- uses 排序；
- 日志上下文不足；
- 重复代码；
- 命名不理想；
- 目录可读性差。

---

## 24. PowerShell 检测示例

### 24.1 UTF-8 BOM

```powershell
$files = Get-ChildItem src -Recurse -Include *.pas,*.dpr,*.inc
foreach ($file in $files) {
  $bytes = [IO.File]::ReadAllBytes($file.FullName)
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  if (-not $hasBom) { Write-Error "ENC001 $($file.FullName) missing UTF-8 BOM" }
}
```

### 24.2 View 直连 DB

```powershell
$files = Get-ChildItem src\views-vcl,src\views-fmx -Recurse -Include *.pas -ErrorAction SilentlyContinue
$pattern = 'TFDConnection|TFDQuery|FDConnection|SQL\.Text\s*:=|ExecSQL'
$files | Select-String -Pattern $pattern
```

### 24.3 空 except

```powershell
Get-ChildItem src -Recurse -Include *.pas |
  Select-String -Pattern 'except\s*(//.*)?$' -Context 0,3
```

此规则建议后续升级为 Delphi parser，避免 grep 误报。

### 24.4 Git diff

```powershell
git diff --check
git diff --numstat
git status --porcelain
```

---

## 25. 提交规范

规则：

- 单轮改动建议 ≤ 200 行，超过需说明；
- `.pas` 与 `.dfm/.fmx` 尽量分开提交；
- 删除方法体前搜索引用；
- 不重排无关代码；
- 不做无关格式化；
- 每次提交前运行 `check-all.ps1`、编译、测试。

提交信息：

```text
<类型>：<中文简述>

<具体变更列表>
验证: <命令和结果>
风险: <剩余风险或无>
```

---

## 26. 反模式速查

| 规则 | 反模式 | 修复 |
|---|---|---|
| ARCH001 | View 直连 DB | 经 Controller / Service / Repository |
| ARCH002 | Controller 引用 UI | 移到 View 或抽接口 |
| ARCH003 | 全局 DM | 构造函数注入 |
| UI001 | God Form | 拆 Frame / Controller |
| UI002 | 大量运行时控件 | 设计时或控件工厂 |
| DB001 | 裸 SQL / 字符串拼接 SQL | 参数化 / Repository / DoQry |
| EXC001 | 空 except | Logger + 处理策略 |
| SEC001 | 硬编码密钥 | DeepBase.Security |
| ASYNC001 | UI 线程 Sleep / WaitFor | TTask / WorkerQueue |
| LLM001 | UI 同步 LLM | DeepBase LLM async / 后台任务 |
| CFG001 | 散落 INI/JSON 配置 | root.txt + DB1 ConfigDB |
| COM001 | 客户端直连 DB4 | 后端 HTTP / SafeClient |

---

## 27. FMX 跨平台支持

有的软件需要跨平台时，可以使用 FMX，但 FMX 不是 Windows 桌面默认选择。

### 27.1 何时选择 FMX

适合：

- 同一套 UI 需要覆盖 Windows / macOS；
- 移动端 iOS / Android；
- 视觉和动画强于原生桌面控件；
- 项目明确声明跨平台优先。

不适合：

- 只做 Windows 专业工具；
- 重度依赖 Windows 原生控件和系统集成；
- 大型数据表格、复杂树表、传统 MDI/工具窗；
- 需要最强 Windows 原生体验。

### 27.2 FMX 设计时优先

FMX 项目优先在 `.fmx` 中设计：

- Form；
- Frame；
- Layout；
- Button；
- Edit；
- Memo；
- List；
- StyleBook；
- TabControl。

运行时创建控件只允许：

- 动态列表项；
- 可虚拟化 UI；
- 插件式 UI；
- 明确标注 `RUNTIME-ALLOWED`。

### 27.3 FMX 目录

FMX UI 放：

```text
src/views-fmx/
```

规则：

- `views-fmx` 允许 uses `FMX.*`；
- `views-fmx` 不允许 uses `Vcl.*`；
- 公共逻辑放 `controllers/services/models/core`；
- VCL 和 FMX 不共享 Form / Frame 单元；
- 共享模型不得依赖 UI 框架。

### 27.4 FMX 跨平台注意事项

必须显式处理：

- 文件路径分隔符和沙盒目录；
- 字体差异；
- DPI / 缩放；
- 触控和鼠标交互差异；
- 平台权限；
- 网络权限；
- 本地存储路径；
- OpenSSL / 证书；
- 输入法；
- 系统浏览器打开方式；
- 深色模式和主题差异。

### 27.5 FMX 与 DeepBase

FMX 项目仍应使用：

- DeepBase Core；
- DeepBase Services；
- DeepBase Persistence；
- DeepBase Features；
- DeepBase FMX；
- DeepBase Security；
- DeepBase LLM；
- DeepBase Commerce；
- DeepBase Resilience。

跨平台 Secret 使用 UBS2。不要因为跨平台而退回明文配置。

### 27.6 FMX 发布门禁

FMX 项目必须按声明平台编译和测试：

```text
Windows Win64
macOS
Android
iOS
Linux（如项目声明）
```

只声明 Windows 的 FMX 项目不自动视为跨平台项目。

---

## 28. 版本记录

```text
v3.0
- 升级到 Delphi 13.1 / Compiler 37。
- 默认 DeepBase，旧 UniBase 规则降级为迁移对象。
- Windows 桌面默认 VCL。
- 目录允许二级，但白名单受控。
- 新增 DeepBase LLM / Commerce / BrowserAutomation / DeepShell 规范。
- 新增 PowerShell 质量门禁方向。
- 末尾新增 FMX 跨平台支持。
```

