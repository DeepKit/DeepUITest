# DeepRKey 测试报告

> 版本: v0.2.0-beta
> 日期: 2026-06-21
> 状态: 自动化测试 100% 通过

---

## 测试概览

| 测试类型 | 数量 | 通过 | 失败 | 跳过 | 通过率 |
|----------|------|------|------|------|--------|
| 单元测试 (DUnitX) | 180 | 180 | 0 | 0 | 100% |
| 自动化测试套件 | 33 | 31 | 0 | 2 | 100%* |
| 手动测试 | 3 脚本 | — | — | — | 待人工执行 |

> *排除 2 个 SKIP (Calculator UWP + VS Code 未安装)

---

## 单元测试 (DUnitX)

```
bin\DeepRKey.Tests.exe
```

- **测试数量**: 180
- **通过**: 180
- **失败**: 0
- **覆盖模块**:
  - Bootstrap (初始化/配置)
  - Coordinator (窗口跟踪/Hook 管理)
  - HookEligibilityPolicy (准入策略)
  - WindowTracker (窗口枚举/过滤)
  - SystemMenu (菜单操作)
  - IPC (MMF/Pipe 通信)
  - CommandLine (CLI 解析)

---

## 自动化测试套件 (8 阶段)

```powershell
.\tests\manual\run_all_automated.ps1
```

### 阶段详情

| # | 阶段 | 测试数 | 通过 | 说明 |
|---|------|--------|------|------|
| 1 | 单元测试 | 2 | 2 | DUnitX 测试运行 + 数量验证 |
| 2 | 构建产物 | 6 | 6 | EXE/DLL 存在 + 大小检查 |
| 3 | 启动 & IPC | 2 | 2 | 进程启动 + IPC 窗口 < 6s |
| 4 | CLI 诊断 | 6 | 6 | 日志验证 Bootstrap/Coordinator/IPC/GUID + health-check + help |
| 5 | 暂停/恢复 | 3 | 3 | IPC 命令往返 (--pause/--resume/--toggle) |
| 6 | 窗口检测 | 5 | 3 | Notepad ✅, Calculator SKIP, VS Code SKIP, 窗口/线程跟踪 ✅ |
| 7 | 性能快照 | 3 | 3 | 内存 < 100MB + CPU 时间 > 0 + 空闲 CPU < 5% |
| 8 | Dark Mode | 6 | 6 | 注册表检测 + VCL 样式 + 日志条目 |

### 关键指标

| 指标 | 值 | 目标 | 状态 |
|------|------|------|------|
| 单元测试通过 | 180 | >= 180 | ✅ |
| IPC 窗口出现 | < 2s | < 6s | ✅ |
| EXE 大小 | ~8.5 MB | > 5 MB | ✅ |
| Hook DLL 64-bit | 97.5 KB | < 100 KB | ✅ |
| Hook DLL 32-bit | 61.5 KB | > 10 KB | ✅ |
| 内存使用 | ~23 MB | < 100 MB | ✅ |
| 空闲 CPU | ~0.03% | < 5% | ✅ |
| VCL 暗色样式 | Carbon/OnyxBlue 等 | >= 1 | ✅ |

### SKIP 原因

| 测试 | 原因 | 备注 |
|------|------|------|
| Calculator launches | `calc.exe` 在现代 Windows 上是 UWP 重定向器，启动后立即退出 | 系统限制，非 DeepRKey 问题 |
| VS Code (Electron) launches | VS Code 未安装 | 可选依赖 |

---

## 手动测试 (待执行)

### 运行方式

```powershell
# 一键启动所有手动测试
.\tests\manual\run_manual_tests.ps1

# 或单独运行：
.\tests\manual\edge_case_test.ps1
.\tests\manual\compatibility_matrix_test.ps1
.\tests\manual\accessibility_test.ps1
```

### 测试场景

| 脚本 | 场景数 | 描述 |
|------|--------|------|
| `edge_case_test.ps1` | 5 | 锁屏/解锁、睡眠/唤醒、混合 DPI、快速用户切换、RDP |
| `compatibility_matrix_test.ps1` | 5 | Win32 原生、VCL、WPF、Electron、UWP 应用兼容性 |
| `accessibility_test.ps1` | 4 | 键盘导航、托盘键盘访问、高对比度模式、触摸目标 |

### 前置条件

- DeepRKey.exe 必须正在运行
- Notepad 可用 (大多数测试需要)
- 多显示器 (DPI 测试可选)
- 第二个 Windows 用户账户 (用户切换测试可选)

---

## 性能优化结果 (T-500)

线程级 Hook 架构显著降低了 CPU 使用率：

| 指标 | 优化前 | 优化后 | 改善 |
|------|--------|--------|------|
| 空闲 CPU (avg) | 14.46% | **0.57%** | 96% ↓ |
| 空闲 CPU (max) | 18.3% | **1.42%** | 92% ↓ |
| 长期 CPU (avg 30s) | 16.38% | **0.15%** | 99% ↓ |

---

## 已知限制

1. **启动时间**: ~638ms (目标 < 300ms) — 受 VCL 框架 700ms 初始化开销限制
   - 延迟初始化架构已实现，托盘图标优先显示
   - 完全优化需要原生 Win32 重写 (T-501，延期至 v0.3.0)

2. **Calculator 兼容性**: `calc.exe` 在现代 Windows 上是 UWP 应用重定向器
   - 无法通过常规方式启动和跟踪
   - 这是 Windows 系统限制，非 DeepRKey 问题

3. **VS Code 测试**: 需要系统安装 VS Code 才能执行 Electron 兼容性测试

---

## 测试文件清单

```
tests/
├── manual/
│   ├── run_all_automated.ps1      # 8 阶段自动化测试 (31 tests)
│   ├── run_manual_tests.ps1       # 手动测试启动器
│   ├── edge_case_test.ps1         # 边缘场景 (5 scenarios)
│   ├── compatibility_matrix_test.ps1  # 兼容性矩阵 (5 app types)
│   ├── accessibility_test.ps1     # 无障碍测试 (4 sections)
│   └── automated_report_*.txt     # 自动化测试报告 (自动生成)
├── DeepRKey.Tests.dpr             # DUnitX 测试项目
└── DeepRKey.Tests.exe             # 编译后的测试可执行文件
```

---

## 总结

DeepRKey v0.2.0-beta 的测试覆盖率达到预期目标：

- ✅ **180+ 单元测试** 全部通过
- ✅ **自动化测试套件** 100% 通过 (排除环境限制导致的 SKIP)
- ✅ **性能优化** CPU 使用率降低 96-99%
- 🔄 **手动测试** 脚本已创建，待人工执行

下一步：
1. 执行手动测试脚本
2. 根据手动测试结果修复发现的问题
3. v0.3.0 考虑 T-501 启动时间优化
