# 试点：DeepSpec 端到端烟测（任务 6.3）

> 时间：2026-05-16
> 程序：`d:\_Progs\02Business\DeepSpec\bin\Win64\Debug\DeepSpec.exe`

## 测试设施改动（一次性）

`DeepSpec/src/app/DeepSpec.Commands.pas` 新增两个 Debug 命令，仅供本次烟测：

| 命令 ID | 描述 | 触发的 AIEH 路径 |
|---------|------|------------------|
| `deepspec.debug.inject-convert-error` | Debug: Inject EConvertError (elAutoFix path) | `elAutoFix` —— **静默写日志，无对话框** |
| `deepspec.debug.inject-generic-error` | Debug: Inject generic Exception (elAIAnalyze path) | `elAIAnalyze` —— **弹友好 MessageDlg** |

两个命令归 `Debug` 分类，从命令面板可见。

## 自动化部分（已完成）

| 检查点 | 结果 |
|--------|------|
| DeepSpec.exe 启动后进程存活 ≥ 10 秒 | ✅ PID 36596，常驻 40.9 MB |
| 启动期间无 unhandled exception 让进程崩 | ✅ |
| `InstallAIErrorHandler` 调用本身不阻塞 `Application.Initialize` 与 `Application.Run` | ✅（间接证明：进程 alive） |

→ 印证 **Property 11**（Bootstrap 自身异常被吞掉）和 **Property 1**（Install 后置条件，至少不让宿主死）。

## 手动验证清单（待用户执行）

请按下面顺序操作 DeepSpec.exe，验证 AIEH 端到端串通：

### 路径 A：elAIAnalyze（友好 MessageDlg）

1. 双击启动 `d:\_Progs\02Business\DeepSpec\bin\Win64\Debug\DeepSpec.exe`
2. 等到主窗体出来
3. **Ctrl+P** 打开命令面板（或菜单里找 Debug 分类）
4. 选 **`Debug: Inject generic Exception (elAIAnalyze path)`**
5. **预期**：弹出一个 mtWarning 风格的 MessageDlg，内容形如：
   - 如果 LLM 已配过且能联通：会有一句 LLM 生成的中文友好原因 + 建议
   - 如果 LLM 未配置 / 不可达：会有兜底文案，类似 `系统遇到问题：Pilot smoke: forced generic exception for AI analysis`
6. **验证 1**：MessageDlg 标题是 `Warning`，正文中文，不是英文 stack trace。✅ 表示 R6.1 / R6.4 通过
7. 点 OK 关闭。验证 DeepSpec 没崩，可以继续操作。

### 路径 B：elAutoFix（静默路径）

1. 同一个会话中，**Ctrl+P** 再开命令面板
2. 选 **`Debug: Inject EConvertError (elAutoFix path)`**
3. **预期**：**没有任何对话框**。AIEH 把 `EConvertError` 归为 `elAutoFix`，仅 `Logger.Warn` 一条记录。
4. **验证 2**：界面上看不到任何弹窗，DeepSpec 继续正常响应。✅ 表示分类器（R 隐式）+ SilentMode 配置（R2.1）的非 SilentMode 分支都对

### 路径 C：AutoFix JSONL（可选，需 `--autofix-mode`）

1. 关闭 DeepSpec
2. 命令行启动：
   ```cmd
   DeepSpec.exe --autofix-mode
   ```
3. 同样跑路径 B 的 EConvertError 注入
4. **预期**：检查 `%LocalAppData%\DeepBase\autofix\` 目录（或 DeepSpec 项目的 `.deepspec/autofix/` 之类的位置，具体看 AutoFix.ErrorRecorder 当前配置），应该有 JSONL 文件，最新一条记录与你刚注入的 EConvertError 对应。
5. **重要**：`--autofix-mode` 下 AutoFix.VclHook 会**接管** Application.OnException 并**抑制** AIEH 的 MessageDlg 链——这是 VclHook.pas 的设计意图，写在它的注释里：
   > "When AutoFix mode is active, this hook records and suppresses the Application.OnException chain (no dialog is shown)."

   所以路径 C 下你**不会**看到 MessageDlg，但 AutoFix JSONL 会被填上。这与 design 文档 Property 5（confluence）的字面要求略有不同 —— AutoFix 在 autofix 模式下**故意不链式调用** AIEH，只单方记录。这是 DeepBase 既有的契约，本特性沿用。

### 反馈格式

把验证 1、验证 2、（可选）路径 C 的结果回报即可。如果路径 A 弹的不是中文友好文案而是英文异常，说明 LLM 桥接 + AIEH 降级走错了，需要排查。

## 试点结论

**6.3 部分通过**：

- 自动化部分：✅
- 手动部分：等用户执行后回报

待用户路径 A / B 反馈通过后，本任务完成；后续 6.4 检查点照走。

## 烟测后清理

**决策（用户）**：DeepSpec.Commands.pas 里两个 Debug 命令**保留为永久排错入口**，不在试点后删除。理由是日后排查 AIEH 链路问题（任何下游程序都可能用类似 pattern 复制）有现成参考。

为方便维护，这两个命令的位置在：
- 文件：`02Business/DeepSpec/src/app/DeepSpec.Commands.pas`
- 标记：源码注释中的 `Debug commands — pilot smoke test for AIErrorHandler integration` 一段
- 命令 ID：`deepspec.debug.inject-convert-error` / `deepspec.debug.inject-generic-error`

后续如果有人想批量化"AIEH 烟测"作为发布前 checklist，可以把这一段抽出来做成 `DeepBase.AIErrorHandler.Diag.pas` 之类的诊断单元，让任何 Deep* 程序一键引入。**本 spec 不做此抽象**。
