# 第三方组件兼容性矩阵

> 最后更新：2026-05-09
> 规则：阻塞状态为 ⚠ 的组件,依赖它的项目不启动正式迁移

---

## 状态说明

- ✅ 已确认兼容,可用
- ⚠ 待确认/待安装
- ❌ 不兼容,需替代方案
- 🔄 正在升级中

---

## 矩阵

| 组件 | 12.3 版本 | 13.1 目标版本 | 状态 | 阻塞项目 | 备注 |
|---|---|---|---|---|---|
| **Skia4Delphi** | 6.x | 7.1.0 | ⚠ 待安装 | DeepBase + 12 个下游 | DeepBase CLI 构建未暴露 Skia unit 错误；IDE 安装仍待人工 |
| **CEF4Delphi** | 旧版 | CEF4Delphi-131 | ⚠ 待确认 | DeepSVG, DeepMoveC | 项目目录已有 131 引用 |
| **WebView4Delphi** | - | 13.1 兼容版 | ⚠ 待确认 | DeepCompare, DeepMoveC | 需确认版本号 |
| **mORMot2** | - | 13.1 兼容 | ⚠ 待确认 | Assayer | 关键路径 |
| **madCollection** | BDS23 | BDS24 (13.1) | ⚠ 待安装 | DeepSVG, DeepCharset | 替代 madExcept |
| **SynEdit** | - | 13.1 重编 | ⚠ 待重编 | DeepStory, DeepConfig, DeepCharset | 需手动重编 |
| **VirtualTreeView** | - | 13.1 重编 | ⚠ 待重编 | DeepConfig, DeepLaunch, DeepCharset | 需手动重编 |
| **Python4Delphi** | - | 13.1 重编 | ⚠ 待重编 | DeepConfig, DeepCharset | 需手动重编 |
| **TreeSitter** | 自维护 | 重编 | ⚠ 待重编 | DeepRenew | 自维护绑定 |
| **FireDAC** | 随 IDE | 随 IDE | ✅ | DeepBase/Persistence | DeepBase 13.1 Persistence/VCL/FMX/测试已通过 |
| **Indy** | 随 IDE | 随 IDE | ✅ | 多个 | 无需额外操作 |
| **System.Net.HttpClient** | 随 IDE | 随 IDE + SSE | ✅ | DeepBase, Assayer, DeepCompare | DeepBase LLM proxy 验证通过；原生 SSE 替换后续评估 |

---

## 按组阻塞分析

### Group A（Skia/CEF 图形密集型）
- 阻塞项：Skia 7.1.0, CEF4Delphi-131, WebView4, madCollection
- 最早可启动：Skia + CEF 就绪后

### Group B（LLM/流式网络）
- 阻塞项：mORMot2, WebView4
- 最早可启动：mORMot2 就绪后

### Group C（IDE 类 & 编辑器）
- 阻塞项：SynEdit（DeepStory 需要）
- 最早可启动：DeepDev 无额外阻塞,DeepStory 等 SynEdit

### Group D（配置/工具/多组件）
- 阻塞项：VTV + SynEdit + P4D（三件套全部就绪才启动 DeepConfig）
- 最早可启动：三件套就绪后

---

## 更新日志

| 日期 | 变更 |
|---|---|
| 2026-05-09 | 初始化矩阵 |
| 2026-05-09 | 同步 DeepBase 13.1 CLI 验证状态；Skia IDE 安装仍待人工确认 |
