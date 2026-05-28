# Deep* 系列 Delphi 13.1 迁移总纲

> 覆盖范围:17 个 Deep* 项目(DeepBase + 16 个下游)
> 源环境:Delphi 12.3 Athens (BDS 23.0)
> 目标环境:Delphi 13.1 Florence (BDS 37.0)
> 目标目录:`D:\Program Files (x86)\Embarcadero\Studio\37.0`

---

## 1. 迁移目标

1. 所有 Deep* 项目在 Delphi 13.1 下 Clean + Build 全部通过,Warning 全部清零或登记白名单
2. 全部第三方组件切换到 13.1 兼容版本并统一版本号
3. 在新代码中启用 13.1 的现代语法,并按清单重构老代码中高频的过时模式
4. 通过 steering 文件让 AI 在后续所有开发中默认遵循 13.1 规范
5. 在关键子系统(SSE 流、Skia 渲染)做 PoC,量化升级收益
6. 编译脚本、CI、发布流水线全部切到 13.1

## 2. 环境与路径统一

**统一入口脚本**:`02Business/scripts/env/delphi-13.1.bat`

```bat
@echo off
REM ===== Delphi 13.1 Florence 环境变量 =====
set BDS=D:\Program Files (x86)\Embarcadero\Studio\37.0
set BDSVERSION=37.0
set BDSCOMMONDIR=%PUBLIC%\Documents\Embarcadero\Studio\37.0
call "%BDS%\bin\rsvars.bat"
set DCC64="%BDS%\bin\dcc64.exe"
set DCC32="%BDS%\bin\dcc32.exe"
set MSBUILD="%FrameworkDir%\msbuild.exe"
```

**所有 `compile_*.bat` 首行统一**为 `call "%~dp0\scripts\env\delphi-13.1.bat"`,不再各自写版本号。

保留 `scripts/env/delphi-12.3.bat` 作为回退入口。

## 3. 第三方组件兼容性矩阵

| 组件 | 12.3 版本 | 13.1 目标 | 就绪 | 阻塞项目 |
|---|---|---|---|---|
| Skia4Delphi | 6.x | 7.1.0 | ✅ | 12+ |
| CEF4Delphi | 13x | CEF4Delphi-131 | ✅ | DeepSVG / DeepMoveC |
| WebView4Delphi | - | 13.1 兼容版 | ⚠ 待确认 | DeepCompare / DeepMoveC |
| mORMot2 | - | 13.1 | ⚠ 待确认 | Assayer |
| madCollection | BDS23 | BDS24(13.1) | ✅ | DeepSVG / DeepCharset |
| SynEdit | - | 13.1 重编 | ⚠ 待确认 | DeepStory / DeepConfig / DeepCharset |
| VirtualTreeView | - | 13.1 重编 | ⚠ 待确认 | DeepConfig / DeepLaunch / DeepCharset |
| Python4Delphi | - | 13.1 重编 | ⚠ 待确认 | DeepConfig / DeepCharset |
| TreeSitter(自维护) | - | 重编 | - | DeepRenew |

**规则**:阻塞状态为 ⚠ 的组件,依赖它的项目先停在 "pre-flight" 阶段,不启动正式迁移,直到组件就绪。

每组 AI 启动项目前先读本矩阵,矩阵文件将放在 `02Business/docs/delphi-13-migration/COMPATIBILITY.md`,升级过程中持续更新。

## 4. 13.1 语法现代化清单

AI 在重构或新写代码时,按以下映射处理。不要求一次清空老代码,但**新写代码必须用新模式**,老代码按任务范围逐步重构。

### 4.1 推荐替换

| 旧模式(12.3 及更早) | 新模式(13.1) | 场景 |
|---|---|---|
| `if Cond then X := A else X := B;` | `X := if Cond then A else B;` | 条件赋值、函数实参 |
| `var X: Integer; begin X := ...;` | `var X := ...;`(inline var + 推断) | 局部变量 |
| 手写 SSE 解析(逐行拼接 `data:`) | `TNetHttpClient` SSE API | LLM 流式、订阅推送 |
| 临时用 `TStringList` 盛几项 | `TArray<string>` | 小量字符串集合 |
| `try ... finally X.Free; end;`(短生命周期) | 智能指针 / 管理记录 | 栈局部对象 |
| 代码里手算 DPI 缩放 | DFM 96 DPI 保存 + VCL Styles Hooks | 自定义 Skia 控件 |
| `TBitmap.LoadFromFile`(SVG/矢量) | `TSkImage.MakeFromEncodedFile` / Skia SVG | 图形资源 |
| `AnsiString` / `PAnsiChar`(非互操作) | `string` + `TEncoding.UTF8` | 一切新代码 |
| `{$IFDEF VER340}` 特定版本号 | `{$IF CompilerVersion >= 37}` | 兼容分支 |
| 老 VCL 主题自定义绘制 | Windows 11 新样式(6 款) | 启动器、工具类 UI |

### 4.2 禁用/弃用

- ❌ 不再使用 madExcept BDS23 版本(统一 madCollection 新版)
- ❌ 不引用旧 `VCL.Skia.*` / `FMX.Skia.*` 路径(Skia 7.1.0 做了重组,按新 unit 名引用)
- ❌ 不手写 SSE/WebSocket chunk 解析(有官方 API)
- ❌ 新代码不写 `with X do ...`
- ❌ 不用 `TEncoding.ANSI` 处理网络/文件 IO

### 4.3 Warning 策略

- 13.1 编译器可能对未初始化变量、隐式类型转换更严
- 每个项目迁移后,Warning 数量记入 DoD
- **零新增 Warning**,老 Warning 清零或登记进项目的 `.kiro/specs/delphi-13-migration/warning-whitelist.md`

## 5. AI 约束(Steering 文件)

三层结构,覆盖全局 → 领域 → 项目:

```
02Business/<project>/.kiro/steering/
├── delphi-13-global.md            # 默认加载 — 版本、路径、编译器开关
├── delphi-13-syntax.md            # 默认加载 — 语法清单(含 before/after 示例)
├── skia-7.1-conventions.md        # fileMatch: "**/*Skia*.pas,**/*Graphic*.pas"
├── sse-streaming-pattern.md       # fileMatch: "**/LLM*.pas,**/Stream*.pas"
└── migration-checklist.md         # inclusion: manual — # 手动引用
```

**谁负责**:
- 阶段 0(基础设施)中,由 orchestrator 为每个项目生成一份同模板的 steering,项目差异通过 `fileMatch` 控制
- 后续每个项目 AI 迁移时,steering 会自动生效,不需要额外记忆

**模板源**:`02Business/docs/delphi-13-migration/steering-templates/`(阶段 0 创建)

## 6. 四阶段路线图

### 阶段 0 — 基础设施(在 DeepBase 之前完成)
- 建 `scripts/env/delphi-13.1.bat` 和回退脚本
- 建 `COMPATIBILITY.md` 并完成组件盘点
- 建 steering 模板
- 手动安装 Skia 7.1.0、CEF4Delphi-131、madCollection 到 13.1

### 阶段 1 — 核心依赖
- **DeepBase**(必须首先完成,所有下游基石)
- DoD:Core / VCL / FMX / Persistence / Features / Services 六个 bpl 全部可 Build 且所有 Tests 通过

### 阶段 2 — 高收益项目(4 组并行触发起点)
- Assayer / DeepSVG / DeepDev / DeepMoveC(每组 AI 先做本组优先级最高的一个,验证流程)

### 阶段 3 — 中等项目
- DeepCompare / DeepStory / DeepConfig / DeepInsight / DeepLaunch / DeepShine / DeepRenew / DeepCharset

### 阶段 4 — 小型项目跟随
- DeepSync / DeepClip / DeepDevLite / DeepInput(跟随本组其它项目完成后顺带迁移)

## 7. 四组并行分配(16 个非 DeepBase 项目)

**分组原则**:
- 每组 4 个项目,复杂度大致平衡
- 每组包含 1 个大型 + 1 个中型 + 1-2 个小型,按组内从大到小顺序执行
- 组间在第三方组件上有差异,避免等组件阻塞多个组
- 前提条件:所有组必须等 DeepBase 阶段 1 完成后才启动

### Group A — Skia/CEF 图形密集型
聚焦渲染/浏览器嵌入类

1. **DeepSVG**(大)— Skia 7.1.0 + CEF4Delphi-131 + DFM 96 DPI
2. **DeepMoveC**(中)— CEF + WebView4,已是 D13 先锋项目,用于验证
3. **DeepShine**(中)— Skia 渲染,多 Apps 组合
4. **DeepClip**(小)— Skia 小工具

### Group B — LLM/流式网络
聚焦 SSE、REST 流式、LLM 协议

1. **Assayer**(大)— SSE 原生替换 + mORMot2 + 64-bit IDE 收益
2. **DeepCompare**(中大)— WebView4 + SSE + Skia 图表
3. **DeepInsight**(中)— REST 客户端现代化
4. **DeepInput**(小)— 输入辅助,LLM 轻集成

### Group C — IDE 类 & 编辑器
聚焦 SynEdit、VTV、LSP

1. **DeepDev**(大)— FMX + Skia + LSP 集成项目
2. **DeepStory**(中)— SynEdit + Win64 + 30+ 写作服务
3. **DeepDevLite**(小)— DeepDev 轻量版,跟随主项
4. **DeepSync**(小)— 同步工具,依赖相对独立

### Group D — 配置/工具/多组件
聚焦 VTV + SynEdit + P4D + Win11 样式

1. **DeepConfig**(大)— VCL+FMX 双框架 + P4D + VTV + SynEdit
2. **DeepCharset**(中)— SynEdit + VTV + Skia + P4D + madCollection
3. **DeepLaunch**(中)— Win11 新样式 + VTV + Skia
4. **DeepRenew**(中)— TreeSitter + VCL+FMX 双版本

### 组内执行顺序

每组 AI 拿到分组后:
1. 先读本总纲 + 组内第一个项目的 `.kiro/specs/delphi-13-migration/tasks.md`
2. 按组内优先级顺序逐个项目执行(从 1 到 4)
3. 前一个项目 DoD 未达成前,不启动下一个

## 8. 每项目 DoD(完成标准)模板

每个项目的 tasks.md 末尾都有"完成标准"章节。通用项:

- [ ] 所有 dpk / dproj / groupproj 在 13.1 下 Clean + Build 成功
- [ ] 所有编译脚本迁到新的 `delphi-13.1.bat` 入口
- [ ] 第三方组件全部 13.1 版本,BPL 已 Install
- [ ] Warning 数量 ≤ 迁移前水平,或新增项全部登记白名单
- [ ] 单元测试 / 集成测试全绿
- [ ] 发布包冒烟测试通过(手动运行一次主流程)
- [ ] 至少 1 处代码采用 13.1 新语法作为样板(ternary / inline var / SSE 等按项目特点选)
- [ ] `.kiro/steering/delphi-13-*.md` 三件套到位
- [ ] `CHANGELOG.md` 或 `docs/d13-migration-notes.md` 记录迁移要点

## 9. 回退机制

- 每个项目在升级前打 git tag:`pre-d13-<project>`
- 升级在分支 `upgrade/delphi-13` 进行,验证通过后再合回主分支
- `.dproj` 先复制为 `.dproj.12.bak`
- 失败回退:`git checkout pre-d13-<project>` + 切回 `delphi-12.3.bat`

## 10. 工作流约定

- 每个项目的任务包在 `<project>/.kiro/specs/delphi-13-migration/tasks.md`
- AI 按 tasks.md 的 checkbox 顺序执行,每完成一项立即更新状态
- 遇到阻塞(组件未就绪、编译错误超过 2 轮 fix 仍失败),停下并向人类报告,不擅自跳过
- 每组 AI 独立推进,组间不要互相依赖(DeepBase 之外)
- 所有迁移产物(改动的 dproj / 新 steering / 新 bat)一并提交到该项目仓库,commit 信息前缀 `[d13]`

## 11. 关键风险

- 第三方组件等待是最大风险,Group B 的 mORMot2、Group C 的 SynEdit、Group D 的 P4D 都是关键路径
- Win64 IDE 的 64-bit 工具链切换可能引入链接器差异,DeepStory / Assayer 注意
- Skia 7.1.0 部分 unit 路径改动,DeepBase/FMX 子包需要修 uses
- CEF4Delphi-131 版本与旧版 API 不完全兼容,DeepSVG / DeepMoveC 有改动量

## 12. 参考文档

- `COMPATIBILITY.md` — 组件兼容矩阵(持续更新)
- `steering-templates/` — steering 文件模板
- 各项目的 `.kiro/specs/delphi-13-migration/tasks.md` — 该项目实际任务
