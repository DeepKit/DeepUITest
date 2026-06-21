# DeepRKey 构建指南

> 设计基线: v0.6
> 更新日期: 2026-06-21

## 前置条件

### 必需

- **Windows 10/11 x64**
- **Delphi 13.1** (RAD Studio 37.0) 安装于 `D:\Program Files (x86)\Embarcadero\Studio\37.0`
- **Git**

### 编译器说明

| 编译器 | 路径 | 用途 |
|--------|------|------|
| `dcc64.exe` | `%BDS%\bin\dcc64.exe` | **Delphi 64 位编译器**（主程序 + Hook DLL） |
| `dcc32.exe` | `%BDS%\bin\dcc32.exe` | **Delphi 32 位编译器**（32 位 Hook DLL + Helper） |
| `bcc64.exe` | `%BDS%\bin\bcc64.exe` | C++ Builder 64 位编译器（本项目不使用） |

> ⚠️ `bcc64.exe` 是 C++ Builder 编译器，编译 `.pas`/`.dpr` 必须使用 `dcc64.exe`/`dcc32.exe`。

### Delphi 13.1 新语法约定

本项目使用 Delphi 13.1 (Compiler 37.0) 的现代语法特性：

| 特性 | 示例 | 适用范围 |
|------|------|----------|
| **内联变量声明** | `var x := 42;` `var s := 'hello';` | 全局使用 |
| **类型推断 for 循环** | `for var item in collection do` | 全局使用 |
| **记录方法** | `procedure TMyRecord.DoSomething;` | Domain 层 |
| **字符串助手** | `s.IsEmpty` `s.Contains('x')` `s.StartsWith('a')` | 主程序、Helper |
| **泛型集合** | `TList<T>` `TDictionary<K,V>` `TObjectDictionary<K,V>` | 主程序、Helper |
| **匿名方法** | `procedure begin ... end` `TThread.CreateAnonymousThread(...)` | Application 层 |
| **并行库** | `TParallel.For` (PPL) | 仅在非 Hook 路径 |
| **RTTI 增强** | `{$RTTI EXPLICIT ...}` 显式控制 | 全局使用 |

> **禁止用于 Hook DLL 的特性**：字符串、泛型、匿名方法、TObject、堆分配（`GetMem`/`New`/`Create`）。Hook DLL 严格遵循 `docs/02.技术方案.md` §9 的 ABI 约束。

### USE_DEEPBASE 构建（内部/商业版本）

- `DeepBaseCore.bpl` + `DeepBaseCore.dcp`（已编译）
- `DeepBaseServices.bpl` + `DeepBaseServices.dcp`（已编译）
- `DeepBasePersistence.bpl` + `DeepBasePersistence.dcp`（已编译）
- `DeepBaseVCL.bpl` ⚠️ **需要编译**（如未编译，强制使用 USE_STUB 构建）
- AI 集成参考：`D:\_Progs\02Business\DeepBase\docs\00.quickstart.AI集成总览-ai-one-file.md`

### USE_STUB 构建（开源版本）

- 无额外依赖。使用 VCL 自带的 `TTrayIcon`、SQLite/INI、ResourceString。

## 编译

### 环境脚本

```powershell
call "D:\_Progs\02Business\scripts\env\delphi-13.1.bat"
```

### 64 位主程序

```powershell
# USE_STUB（推荐，无 DeepBase 依赖）
dcc64 DeepRKey.dpr -B -DUSE_STUB

# USE_DEEPBASE（需要 DeepBase BPL 已编译）
dcc64 DeepRKey.dpr -B -DUSE_DEEPBASE
```

### 64 位 Hook DLL

```powershell
dcc64 HookDLL\DeepRKeyHook64.dpr -B -$RTTI EXPLICIT -$OPTIMIZATION ON -$STACKFRAMES OFF
```

### 32 位 Hook DLL

```powershell
dcc32 HookDLL\DeepRKeyHook32.dpr -B -$RTTI EXPLICIT -$OPTIMIZATION ON -$STACKFRAMES OFF
```

### 32 位 Helper

```powershell
dcc32 Helper32\DeepRKey32.dpr -B
```

### 构建矩阵

| 目标 | 编译器 | 条件定义 | 输出 |
|------|--------|----------|------|
| DeepRKey64.exe (Stub) | dcc64 | USE_STUB | bin\DeepRKey.exe |
| DeepRKey64.exe (DeepBase) | dcc64 | USE_DEEPBASE | bin\DeepRKey.exe |
| DeepRKeyHook64.dll | dcc64 | WIN64 | bin\DeepRKeyHook64.dll |
| DeepRKeyHook32.dll | dcc32 | (无) | bin\DeepRKeyHook32.dll |
| DeepRKey32.exe | dcc32 | (无) | bin\DeepRKey32.exe |

## 首次运行

### root.txt

在 exe 所在目录创建 `root.txt`，第一行为 DeepBase 根路径（仅 USE_DEEPBASE 需要）：

```
D:\_Progs\02Business
```

USE_STUB 构建不需要 `root.txt`。

### 首次启动

1. 双击 `DeepRKey.exe`
2. 托盘图标出现（Stub < 300ms, DeepBase < 500ms）
3. 右键托盘图标 → 查看菜单
4. 右键任意窗口标题栏或按 Alt+Space → 体验增强菜单

### 首次运行引导

程序启动后会自动弹出引导提示，内容包括：
- 如何呼出增强菜单（右键标题栏 / Alt+Space）
- **Alt+Space 与 PowerToys Run 热键冲突说明**（如检测到 PowerToys 运行）
- 暂停/退出/排除列表/隐私说明
- 设置中可开启标题栏叠加按钮作为备用入口

## 常见问题

### 构建失败

| 症状 | 原因 | 解决 |
|------|------|------|
| `No DB connection adapter registered` | 缺少 `DeepBase.Persistence.Manager.FireDAC` | 加入 `.dpr` 的 uses |
| `ConfigDB not found` | `root.txt` 路径不对 | 检查 `root.txt` 第一行路径 |
| `DeepBaseVCL not found` | VCL 包未编译 | 使用 USE_STUB 构建 |
| `unit X compiled with a different version of Y` | DeepBaseVCL 源码与 BPL 版本冲突 | 使用 USE_STUB 构建 |
| `[dcc64 Fatal Error] E2202 Required package not found` | DeepBase BPL 不在搜索路径 | 检查环境脚本中的 BPL 路径 |

### 运行时问题

| 症状 | 原因 | 解决 |
|------|------|------|
| SmartScreen 阻止运行 | 开发阶段未签名 | 点击"更多信息"→"仍要运行" |
| AV 软件拦截 Hook DLL | 未签名 DLL 注入 | 添加排除规则；发布前 EV 签名 |
| 托盘图标不出现 | 启动失败 | 检查日志（OutputDebugString 或 DeepBase.Logger） |
| 右键菜单无增强项 | Hook 未安装或准入策略排除 | 检查目标窗口是否有 WS_SYSMENU；查看 SkipReason 日志 |
| Alt+Space 呼出 PowerToys Run | 热键冲突 | 在 PowerToys Run 设置中更改热键；或使用右键标题栏/托盘菜单/标题栏按钮 |

## 测试

### 单元测试（180+ 测试，每次提交）

```powershell
# 编译并运行 DUnitX 测试
dcc64 tests\DeepRKey.Tests.dpr -B
bin\DeepRKey.Tests.exe
# 预期输出: 180 passed, 0 failed, 180 total
```

### 自动化测试套件（31 PASS / 0 FAIL / 2 SKIP）

```powershell
# 完整 8 阶段自动化测试（需要桌面会话）
.\tests\manual\run_all_automated.ps1
```

测试阶段：
1. **单元测试** — 180+ DUnitX 测试
2. **构建产物** — EXE/DLL 文件大小验证
3. **启动 & IPC** — 进程启动 + IPC 窗口就绪 (< 6s)
4. **CLI 诊断** — 通过日志文件验证 Bootstrap/Coordinator/IPC/GUID
5. **暂停/恢复** — IPC 命令往返测试
6. **窗口检测** — Notepad/Calculator/VS Code 启动 + 窗口跟踪
7. **性能快照** — 内存 < 100MB, 空闲 CPU < 5%
8. **Dark Mode/Theme** — 注册表检测 + VCL 样式可用性

> **注意**: Calculator 和 VS Code 在某些系统上不可用，自动标记为 SKIP。

### 手动测试（需要人工交互）

```powershell
# 一键启动所有手动测试
.\tests\manual\run_manual_tests.ps1

# 或单独运行：
.\tests\manual\edge_case_test.ps1         # 睡眠/锁屏/DPI/RDP
.\tests\manual\compatibility_matrix_test.ps1  # Win32/VCL/WPF/Electron/UWP
.\tests\manual\accessibility_test.ps1     # 键盘/高对比度/触摸
```

### 集成测试（夜间层，需要桌面会话）

```powershell
# 需要管理员权限 + 交互式桌面
dcc64 tests\DeepRKey.IntegrationTests.dpr -B
tests\DeepRKey.IntegrationTests.exe --test-mode
```

### 测试模式

测试模式下，以下参数可配置以加速��试：

- Heartbeat 间隔：500ms（默认 5s）
- Hook DLL 心跳超时：5s（默认 30s）
- TTL 空闲超时：10s（默认 120s）