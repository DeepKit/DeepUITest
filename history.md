# 工作历史记录
> 已完成任务的归档

---

## 2026-05 周期：Delphi 13 迁移 + 全局重命名 + LLM 模块优化

### 编译状态 — 全部通过（15 个主程序）

| 项目 | 状态 |
|------|------|
| DeepBase CLI | ✅ 编译通过 |
| DeepBaseRun | 编译通过 |
 DeepBaseTray | ✅ 编译通过 |
| DeepCompare | ✅ 编译通过 |
| DeepInput | ✅ 编译通过 |
| DeepCharset | ✅ 编译通过 |
| DeepConfig | ✅ 编译 |
| DeepMoveC | ✅ 编译通过 |
| DeepClip | ✅ 编译通过 |
| DeepSync | ✅ 编译通过 |
| DeepForge | ✅ 编译通过 |
| DeepStory | ✅ 编译通过 |
| DeepInsight | ✅ 编译通过 |
| DeepSVG | ✅ 编译通过 |
| DeepForgeLite | ✅ 编译通过 |
| AssayerProxy | ✅ 编译通过（UniBase → DeepBase 全量替换） |
|Shine | ✅ 编译通过（添加 Flow/Legacy/VTV 路径） |

### 全局名称替换（305 个文件）
- UniBase → DeepBase（含命名空间）
- OmniSync → DeepSync / WiseInput → DeepInput
- progeeLite → DeepForgeLite / progee2 → DeepForge / ClipVault → DeepClip
- DeBorn → DeepRenew / ShineOps → DeepShine / TouchStone → DeepCompare
- uniSVG → DeepSVG / ConfigBuild → DeepConfig / TransSuccess → DeepCharset
- MoveC → DeepMoveC / Insight → DeepInsight / Story → DeepStory
- 修复 "History" 被误替换为 "HiDeepStory"（128 个文件）
- Touch.* 命名空间残留修复（41 个文件）

### 编译修复
- compile_all.bat 路径配置修复
- DeepBaseTray 循环依赖修复
- DeepCompare Touch.*/TouchHotkeys/TouchDB/TouchLLM 引用修复
- DeepConfig 编码损坏文件修复
- DeepC UTF-8 断损坏修复（备份恢复）
- DeepSync 行合并损坏修复（103 个文件从备份恢复）
- DeepForge 从备份恢复（244 个文件）
- DeepStory 从备份恢复（65 个文件）+ 内部方法名修复
- DeepInsight 从备份恢复（96 个文件）
- DeepSVG 从备份恢复（127 个文件）+ CEF4Delphi 路径
- DeepForgeLite 从备份恢复（26 个文件）

### SQLite 数据库产品名更新（5 个配置库）

### 图标统一（17 产品）
- 统一设计：深蓝灰背景 #1C2B3A + 圆角矩形 + 各产品专属符号和颜色
- 生成脚本：`assets/icons/gen_icons.py`（Python + Pillow）
- 部署脚本：`assets/icons/patch_res.py`（直接修改 .res 文件）
- 已更新 20 个 .res 文件

### DeepBase.LLM 模块优化完成
- 新增 `DeepBase.LLM.Proxy.pas` — 代理客户端，实现 ILLMClient，通过 HTTP 转发到 AssayerProxy
- 修改 `DeepBase.LLM.Service.pas` — LLM() 全局函数加入自动探测逻辑
- 修复 Features 目录 LLM 模块编码损坏
- 编译验证通过
- 集成测试通过（Python mock proxy server，6 个场景全部通过）

### DeepBase Bug Fixes P0/P1/P2（19 项全部完成）

**P0 — 架构级：**
- LLM Schema 统一：表定义合并到 `Core/DeepBase.Schema.pas` 的 `EnsureLLMSchema`
- 跨平台 SecretStore：`Core/DeepBase.Security.SecretStore.pas`，支持 Windows/macOS/Linux

**P1 — 并发/正确性：**
- LLM Streaming Transport：扩展 Transport/HTTP 层支持 SSE 流式传输
- IntentClarification StartSession 字段消费修复
- IntentClarification Engine 并发锁（全局 + 每 session 两级锁）
- IntentClarification Provider 状态隔离（L2/L3 移除实例字段，改用 session context）
- BrowserAutomation ResponseWaiter 消息解析修复
- BrowserAutomation Registry 锁粒度优化
- DeepShell EventBus 生命周期（Shutdown + OnDispatchError）
- DeepShell Theme/Localization 主线程安全分发
- Graph.Dijkstra 负权重拒绝 + GetNeighbors 快照返回

**P2 — 可维护性：**
- 注释编码损坏修复
- DeepFlow Pause/Resume + 优先队列二分查找插入
- DeepShell Settings 通知抽象（IShellNotification）
- DeepShell 菜单状态运行时刷新
