# DeepUITest.017 - FMX 探针策略

> 状态：开发文档初版
> 用途：明确 VCL 与 FMX 两种 UI 框架的控件定位策略差异，冻结 FMX 探针方案

---

## 1. 问题本质

VCL 和 FMX 在 UI 控件定位上有根本性差异：

```text
VCL：每个控件独立 HWND
  → EnumChildWindows / FindWindowEx 可遍历所有子控件
  → GetWindowText / SendMessage 可读写控件状态
  → Runner 无需目标程序配合即可做结构级断言

FMX：整个窗口只有一个 HWND，控件是 GPU 纹理
  → EnumChildWindows 返回空或不完整
  → GetWindowText 无法获取 FMX 控件文本
  → Runner 必须依赖其他机制定位和操作 FMX 控件
```

---

## 2. 四种可选方案

### 方案 A：FMX 内嵌 HTTP 探针（推荐）

仿 AutoFix 的 ErrorRecorder/VclHook 模式，提供一个可选的 `DeepBase.UITest.FmxProbe` 单元：

```pascal
uses DeepBase.UITest.FmxProbe;

begin
  TFmxProbe.Install;
  Application.Initialize;
  ...
end.
```

Install 仅当命令行含 `--uitest-probe-port=<port>` 时激活，在目标 FMX 程序里启动一个 `localhost:<port>` 的 HTTP 服务：

| 端点 | 方法 | 功能 |
|------|------|------|
| `/tree` | GET | 返回全部控件的 StyleName × ClassName × AbsoluteRect × Visible JSON |
| `/tap` | POST | `{"name":"BtnSave"}` → 模拟 OnClick |
| `/state?name=xxx` | GET | 查询指定控件 Text/Enabled/Visible/Focused/AbsoluteRect |

优势：
- 和 AutoFix 集成模式一致（`*.Install` + 命令行开关 + 可控开销）
- 不依赖目标程序是否启用了 Accessibility
- 控件定位可达 StyleName 级别
- 零外部依赖（Indy TIdHTTPServer 或 HTTP.SYS）
- ~250 行代码

劣势：
- 需要目标 FMX 程序引入 `DeepBase.UITest.FmxProbe` 单元
- GUI 控件树遍历只能发生在主线程

### 方案 B：MS UI Automation (UIA)

通过 Windows Accessibility API 操作 FMX 控件。

```text
能用 UIA 找到的：TButton, TEdit, TCheckBox 等标准控件
经常找不到的：TLayout, TImage, TRectangle, 自定义 Style 控件
```

Delphi FMX 的 Accessibility 实现在大部分控件上是自动生成的（基于控件类型映射），但在复杂自绘控件上不完整。不适合作为 MVP 主策略，可作为辅助定位手段。

### 方案 C：固定坐标回放

记录/回放控件的绝对屏幕坐标。

```text
优势：无需目标程序配合
劣势：分辨率变化、窗口移动、DPI 缩放、多显示器 → 全坏
```

不可作为正式测试策略，只适合开发阶段临时验证。

### 方案 D：编译期 .fmx 解析

解析 `.fmx` 文件中的控件定义，生成静态清单文件（`controls-index.json`），Runner 读取后按 StyleName + 估算坐标定位。

```text
优势：无需运行时配合
劣势：控件的运行时位置可能与设计时不同（动态布局、Anchors、Align）
      无法获取运行时状态（Visible/Enabled 的当前值）
```

可作为方案 A 的离线补充（给 AI 生成测试配置时提供控件清单），不能替代运行时探针。

---

## 3. 推荐策略

```text
VCL 项目 → DeepUITestProbe.exe + Win32 控件枚举  （MVP-1 即可用）
FMX 项目 → DeepBase.UITest.FmxProbe              （方案 A，MVP-6 实现）
```

| 框架 | 定位方式 | 操作方式 | Runner 依赖 |
|------|---------|---------|------------|
| VCL | EnumChildWindows / FindWindow | SendInput / SendMessage | 无需目标配合 |
| FMX | FmxProbe HTTP API | HTTP POST /tap | 需 `TFmxProbe.Install` |

---

## 4. FmxProbe 代码量估计

```text
HTTP Server 创建        ~50 行
控件树递归遍历          ~80 行
/tap 模拟点击            ~60 行
/state 状态查询          ~40 行
命令行解析 + Install     ~30 行
────────────────────────────
合计                    ~260 行
```

---

## 5. 对 MVP 路线的影响

```text
MVP-1~MVP-4：只做 VCL，用 DeepUITestProbe.exe。
MVP-6（原"FMX 支持增强"）：
  旧描述：TestId / Name / StyleName / OnClick / LiveBindings / 黄灯规则
  新描述：实现 DeepBase.UITest.FmxProbe，FmxProbe.Install 集成模式，
          控件树 HTTP API，模拟点击，状态断言。
          配合 DeepDev / DeepSync / DeepInsight / Assayer 等 FMX 项目。
```

AutoFix 已集成到所有 FMX 项目（DeepDev, DeepDevLite, DeepSync, DeepInsight, DeepRenewFMX, Assayer_FMX），FmxProbe 可以复用同样的 `*.Install` 集成模式。

---

*文档版本：v1.0 · 2026-05-27*
