# DeepRKey 任务清单

> 产品版本: v0.2.0-beta | 更新日期: 2026-06-21

---

## 当前版本: v0.2.0-beta

### 🔴 Critical — 安全修复 (P0)

> ✅ 全部完成 (T-436 ~ T-441 已移入 history.md)

### 🟠 High — 稳定性修复 (P1)

> ✅ 全部完成 (T-442 ~ T-448 已移入 history.md)

### 🟡 Medium — 改进项 (P2)

> ✅ 全部完成 (T-449 ~ T-455 已移入 history.md)

### 审阅验证备注

- 2026-06-20 五专家分别审阅 Win32/Hook、IPC 并发、VCL/UI、测试构建、架构性能。
- 已执行现有单元测试：`bin\DeepRKey.Tests.exe`，结果 180 passed / 0 failed。
- 已执行自动化测试套件 (`tests/manual/run_all_automated.ps1`)：**31 PASS / 0 FAIL / 2 SKIP (100% 通过率)**
  - 2 SKIP: Calculator (UWP 重定向器) + VS Code (未安装)
- 未执行 `test-integration.bat`：脚本仍依赖旧 `%TEMP%\DeepRKey_IPC.txt`，且会启动并强制结束 GUI 进程，需先按 T-453 更新。
- 手动测试脚本已创建但待人工执行: edge_case_test.ps1 / compatibility_matrix_test.ps1 / accessibility_test.ps1

### 🔵 Low — 清理优化 (P3)

> ✅ 全部完成 (T-430 ~ T-434 已移入 history.md)

---

## 待办任务

### 架构改进 (v0.3.0 候选)

| # | 任务 | 优先级 | 工时 | 说明 |
|---|------|--------|------|------|
| T-501 | **启动时间架构优化** — 使用原生 Win32 API 重写启动路径，绕过 VCL 700ms 初始化开销 | P3 | 20h | 见 T-010a 分析 |

### 测试覆盖 (P2)

> 自动化测试已执行通过 (31 PASS / 0 FAIL / 2 SKIP)。手动脚本待人工执行。

| # | 任务 | 优先级 | 工时 | 说明 |
|---|------|--------|------|------|
| T-011 | **边缘场景测试** — 自动化 + 手动脚本 | P2 | ✅ | 自动通过；手动: 睡眠/锁屏/DPI/RDP |
| T-012 | **兼容性矩阵** — 自动化 + 手动脚本 | P2 | ✅ | 自动通过；手动: 右击标题栏验证 |
| T-013 | **无障碍测试** — 脚本已创建 | P2 | ✅ | 待人工执行: 键盘/高对比度/触摸目标 |

---

## 已完成

### T-201/202/203: DeepBase 完整集成 (2026-06-21)

- [x] 创建 `DeepRKey.DeepBaseAdapter.pas` — 三个适配器类 (Config/Logger/I18n) 委托到 `UBConfig`/`UBLogger`/`UBI18n`
- [x] 修改 `Bootstrap.pas` — `USE_DEEPBASE` 条件编译路径，创建真实适配器，`Finalize` 调用 `DeepBase.Finalize`
- [x] 更新 .dproj / build.bat — 添加 DeepBase 搜索路径和单元引用
- [x] Stub + DeepBase 双构建验证 — 均编译通过，无错误
- [x] T-202 Config 持久化 — 读写委托到 DeepBase SQLite 后端
- [x] T-203 日志集成 — Info/Warn/Error/Debug 委托到 DeepBase.Logger

### T-011: 边缘场景处理器实现 (2026-06-21)

- [x] `WM_POWERBROADCAST` — `PBT_APMRESUMEAUTOMATIC` 唤醒后调用 `Coordinator.OnSystemResume`
- [x] `WM_WTSSESSION_CHANGE` — 注册 `WTSRegisterSessionNotification`，处理锁屏/解锁/远程连接事件
- [x] `WM_DPICHANGED` — DPI 变化时重新枚举窗口并触发 hook 重评估
- [x] 真实 `GetDpiAwareness` — 动态加载 `GetWindowDpiAwarenessContext` + `GetProcessDpiAwareness` 回退
- [x] `Coordinator.ReenumerateAllWindows` — 系统事件后重新扫描并注入菜单
- [x] 180/180 单元测试通过

### T-304: Dark Mode 支持 (2026-06-21)

- [x] DFM 硬编码颜色清理 — 4 个窗体 `clBtnFace` → `clWindow`，`clGray` → `clGrayText`
- [x] `QuerySystemDarkMode` — 读取注册表 `AppsUseLightTheme` 检测系统暗色模式
- [x] `ApplyTheme` — 启动时根据配置/系统主题选择 VCL 样式 (Windows10 Dark / Carbon)
- [x] TitlebarButton 主题感知 — 暗色模式下调整图标/背景颜色
- [x] SettingsForm 主题选择器 — 动态 ComboBox 列出 System/Light + 可用 VCL 样式
- [x] LoadSettings/SaveSettings — 读写 `UI.Theme` 配置项

### T-500: 线程级 Hook 架构 (2026-06-21)

- [x] 创建 `HookController.pas` — 自实现线程安全队列 (`THookInstallQueue`)，替换 `TThreadedQueue<T>` (Delphi 13.1 构造函数不兼容)
- [x] 修改 `Coordinator.pas` — 替换全局 hook 为 HookController，WinEventProc 按线程安装/卸载 hook
- [x] 32 位路由 — `IsProcess32Bit` 检测 WOW64 进程，通过 HelperManager 路由到 Helper32
- [x] 更新 SettingsForm — Hook 状态显示线程数/活跃数
- [x] 更新 .dproj — 添加 HookController 单元引用
- [x] 性能验证 — CPU 从 ~15% 降至 0.57% (avg) / 1.42% (max)，通过率 86.7% (13/15)
- [x] BUG-049 修复 — CLI IPC 诊断返回 N/A：WM_COPYDATA wParam 类型不匹配 + UTF-16 编码问题 + 单向传输

### v0.2.0-beta 性能优化 (2026-06-21)

- [x] T-010: 性能基准测量 — 创建 performance_benchmark.ps1，测量 9 项指标，通过率 77.8% (7/9)
- [x] T-010a: 启动时间优化 — 实现延迟初始化架构，托盘图标优先显示 (638ms，受 VCL 框架 700ms 初始化开销限制)
- [x] T-010b: 空闲 CPU 优化 — 根因分析确认全局 WH_CALLWNDPROC hook 导致 13-27% CPU；Hook DLL 优化改善 35-50% (CPU 降至 9-18%)
- [x] T-010c: Hook DLL 大小优化 — 64-bit DLL 100KB → 97.5KB，使用 Windows API + Release 编译
- [x] T-010d: 完整性能测试套件 — 创建 performance_test_suite.ps1，15 项指标，通过率 53.3% (8/15)，CPU 受架构限制

### v0.2.0-beta 五专家审阅修复 (2026-06-20)

> 已移入 history.md (T-436 ~ T-455)

### v0.2.0 功能 (2026-06-17 → 2026-06-19)

> 已移入 history.md

### v0.2.0 Bug 修复 (2026-06-19)

> 已移入 history.md

### v0.1.0 (2026-06-09 → 2026-06-17)

> 已移入 history.md

---

## 统计

| 类别 | 数量 |
|------|------|
| ✅ 已完成 (T-500) | 1 |
| ✅ 已完成 (DeepBase 集成) | 3 |
| ✅ 已完成 (边缘场景处理器) | 1 |
| ✅ 已完成 (Dark Mode) | 1 |
| ✅ 已完成 (性能优化) | 5 |
| ✅ 已完成 (测试脚本) | 3 |
| 🏗️ 架构改进 (v0.3.0) | 1 |
| 🧪 手动测试 (待人工执行) | 3 |
| **总待办** | **4** |
