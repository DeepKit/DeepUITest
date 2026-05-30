# ArtifactOS 开发前准备

> 目标：让新开发者在不触碰生产发布的前提下，完成环境、数据库、测试和任务边界确认，然后只从可验证的小任务开始开发。

## 0. 开发原则

- ArtifactOS 不是 MVP 项目；当前目标是可发布、可追溯、可校正、可反哺的完整媒体产出物操作系统。
- 真实发布由既有系统兜底；ArtifactOS 开发默认走 `shadow` / `simulation_only` / `manual-review`。
- ArtifactOS 不直接控制浏览器会话；浏览器自动化属于 PublishingRuntime / media_publish。
- PostgreSQL 测试必须使用 `artifactos_test`，不要使用 `progee_db_test`。
- 开发任务必须能被测试、脚本或清单验证；不能只完成文档级闭环。

## 1. 必读文档

### 总体与边界

| 路径 | 用途 |
|---|---|
| `README.md` | 文档索引和产品总定义 |
| `docs/01.[蓝图]-产品蓝图-Blueprint.md` | 产品愿景、阶段边界、硬约束 |
| `docs/02.[蓝图]-系统架构-Architecture.md` | 系统架构、media_publish 边界、PG 存储边界 |
| `docs/03.[蓝图]-实施路线图-Roadmap.md` | Phase 1A 范围、开工顺序、运行模式 |
| `docs/24.[数据]-数据库模型与治理-Database.md` | PostgreSQL schema、约束、迁移顺序 |
| `tasks.md` | 已完成任务和剩余产品裁决 |

### 按开发方向补读

| 方向 | 必读 |
|---|---|
| Amy Desk / 工作台 | `docs/15.[交互]-Amy工作台-Amy-Desk.md`, `docs/17.[交互]-前夜审阅与影子运行-Evening-Shadow.md`, `backend/amy_desk.py` |
| 发布 / PublishingRuntime | `docs/13.[流程]-多平台发布-Publishing.md`, `config/phase1a/legacy_media_publish_discovery.md`, `backend/diagnostics/publishing_runtime_bridge.py` |
| 数据库 / 契约 | `docs/24.[数据]-数据库模型与治理-Database.md`, `db/migrations/`, `config/phase1a/db_state_20260527.md` |
| 测试 / QA | `tests/run_all_tests.py`, `tests/test_p2_comprehensive.py`, `tests/test_publish_chain.py`, `config/phase1a/shadow_run_7d_checklist.md` |
| SourcePack | `docs/07.[模型]-SourcePack装载-Loading.md`, `config/phase1a/sourcepack_import_summary.md`, `db/migrations/025_sourcepack_core_files.sql` |

## 2. 本地工具与依赖

### 必需

- Git。
- Python 3.11+，当前脚本使用标准库和 `psycopg2`。
- PostgreSQL 15+，本机测试目标为 `artifactos_test`。
- Delphi 13.1 / Compiler 37.0，用于 Delphi 主程序和 DUnitX 测试。
- DeepBase 源码目录，默认相对路径为 `..\..\DeepBase`，见 `build.bat`。

### Python 依赖

当前仓库没有统一依赖文件。测试和后端脚本至少需要：

```bash
python -m pip install psycopg2-binary
```

如果需要运行 media_publish 相关检查，还需要在 media_publish 项目自身环境中安装它的依赖，包括 Playwright / browser runtime；具体以 `D:\_Progs\.BetterCiv\tools\media_publish` 项目为准。

### Delphi 编译

默认编译入口：

```bash
./build.bat
```

带运行时冒烟：

```bash
./build.bat --run
```

`build.bat` 会寻找：

- `C:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\dcc64.exe`
- 或 `D:\Program Files (x86)\Embarcadero\Studio\37.0\bin64\dcc64.exe`

DeepBase 默认路径：

```text
..\..\DeepBase
```

如果本机路径不同，先确认 `build.bat` 中 `DEEPBASE` 设置，不要把个人绝对路径提交为团队默认。

## 3. 数据库准备

### 数据库分工

| 数据库 | 用途 |
|---|---|
| `artifactos` | 正式业务库 |
| `artifactos_test` | ArtifactOS 独立测试库 |
| `progee_db_test` | 非 ArtifactOS 测试库，不要用于本项目测试 |

ArtifactOS 与 PublishingRuntime 共享同一个 PostgreSQL 实例，但通过 schema / 表契约隔离：

| Schema | 职责 |
|---|---|
| `artifactos` | ArtifactOS 业务对象、质量门禁、影子运行、发布包 |
| `media_publish` | 发布任务、平台账号会话、runtime command 等发布执行契约 |
| `legacy_bridge` | 旧系统导入、差异卡、外部引用 |

### 连接环境变量

Python 脚本默认读取：

```bash
export ARTIFACTOS_DB_HOST=127.0.0.1
export ARTIFACTOS_DB_PORT=5432
export ARTIFACTOS_DB_NAME=artifactos_test
export ARTIFACTOS_DB_USER=fuyi01
export ARTIFACTOS_DB_PASS=''
```

Windows bash 会话中也使用上面的 `export` 形式。不要把真实密码提交进仓库。

### 迁移文件

迁移目录：

```text
db/migrations/
```

当前迁移文件为 `001_schema_init.sql` 到 `027_publish_runtime_contract.sql`。开始任何数据库任务前，先确认目标库已经应用到对应迁移版本。

当前仓库还没有统一迁移 runner。临时执行方式应由负责人确认后再运行，例如按编号对 `artifactos_test` 应用 SQL。不要对 `artifactos` 正式库直接试跑新迁移。

建议在补齐 runner 前使用这个核对清单：

- [ ] 目标库是 `artifactos_test`。
- [ ] 已备份或可重建。
- [ ] 按文件编号顺序执行。
- [ ] 执行后确认 `artifactos`、`media_publish`、`legacy_bridge` schema 存在。
- [ ] 执行后运行 `python tests/run_all_tests.py`。
- [ ] 若修改发布契约，额外检查 Amy Desk accounts 页和 PublishingRuntime bridge。

## 4. 测试准备

### Python 自动测试

总入口：

```bash
python tests/run_all_tests.py
```

该脚本目标是 `artifactos_test`，不会真实发布。它会检查 SourcePack、蓝图、会议协议、状态机规则、legacy refs、shadow runs、RealPublishGate 等基础状态。

单项测试入口：

```bash
python tests/smoke_integration.py
python tests/test_state_machine_full.py
python tests/test_p2_comprehensive.py
python tests/test_publish_chain.py
python tests/shadow_run_multiday.py
python tests/shadow_run_review_report.py
```

### Delphi 测试

Delphi DUnitX 入口：

```text
tests/ArtifactOSTests.dpr
tests/ArtifactOSTests.dproj
```

测试文件：

```text
tests/ArtifactOS.Tests.E2EChain.pas
tests/ArtifactOS.Tests.QualityGate.pas
tests/ArtifactOS.Tests.StateMachine.pas
tests/ArtifactOS.Tests.ShadowRun.pas
tests/ArtifactOS.Tests.LegacyImport.pas
```

先确保 `build.bat` 可通过，再运行 Delphi 测试。

### Day0 / 7 天影子运行

当前 Day0 报告：`config/phase1a/day0_dry_run_report.md`。

已通过：

- PostgreSQL 连接。
- `artifactos_test` 表存在。
- SourcePack SPL2 装载。
- media_publish 源码定位。
- media_publish 可导入。
- legacy 系统定位。

未通过：

- `media_publish doctor`。
- Hermes directory found。

7 天验收清单：`config/phase1a/shadow_run_7d_checklist.md`。

开发前至少要确认 Day0 未通过项是否与当前任务相关。如果任务涉及发布、浏览器会话、微信/Hermes/Amy Desk 降级链路，必须先处理或显式标记阻塞。

## 5. PublishingRuntime / media_publish 准备

默认 media_publish 根目录：

```text
D:\_Progs\.BetterCiv\tools\media_publish
```

可用资料：

- `config/phase1a/legacy_media_publish_discovery.md`
- `backend/diagnostics/publishing_runtime_bridge.py`
- `backend/amy_desk.py`
- `db/migrations/027_publish_runtime_contract.sql`

当前边界：

- ArtifactOS 写发布意图和读取状态。
- PublishingRuntime / media_publish 执行浏览器自动化。
- 一个持久浏览器会话对应一个 `(platform_id, account_id)`。
- ArtifactOS 不在自己的代码里重试真实发布。

开始发布集成任务前确认：

- [ ] `MEDIA_PUBLISH_ROOT` 是否指向正确目录。
- [ ] media_publish 能被当前 Python 解释器导入。
- [ ] `media_publish doctor` 或等价检查通过。
- [ ] `media_publish.platform_account_session` 已迁移。
- [ ] `media_publish.runtime_command` 已迁移。
- [ ] 任务是否仅限 zhihu；当前 bridge 的 `publish_article()` 只支持 zhihu。
- [ ] 非 zhihu adapter 是复用归档代码还是重写，已经有明确裁决。

## 6. Amy Desk / 工作台准备

当前实现：

```text
backend/amy_desk.py
```

它是 Python 服务端渲染 HTML 的最小工作台，不是 React/Vue 项目。开始 UI 任务前确认：

- [ ] 是否继续使用服务端渲染 HTML。
- [ ] 如需交互，是用 vanilla JS、HTMX/Alpine，还是维持纯 HTML 表单。
- [ ] 所有状态变更是否只写入 ArtifactOS / media_publish 的契约表。
- [ ] 是否需要 PublishingRuntime 回写 `platform_account_session` 后才能验收。
- [ ] 手机/桌面视图是否都要满足 `docs/15` 和 `docs/17`。

可立即做的小任务：

- Today Desk 页面增加只读状态信息。
- Accounts 页面展示更多 `platform_account_session` 字段。
- DailyReport / EveningWorkPage 的静态详情页。
- 将不可操作原因显示为明确的人类可读状态。

需要先裁决或补契约的任务：

- 十键规则按钮的真实状态变更。
- WebSocket / 实时轮询。
- 发布命令的跨平台执行。
- DailyReportDetailView 的最终渲染协议。

## 7. 可立即认领的任务

这些任务边界相对清楚，适合新开发者开始：

### 文档与开发体验

- 补 Python 依赖文件或环境说明。
- 补迁移 runner 或迁移执行脚本，但只默认指向 `artifactos_test`。
- 把 Day0 未通过项拆成可执行检查。
- 将 `tests/run_all_tests.py` 的依赖和失败排查写清楚。

### 测试

- 为 `media_publish.runtime_command` 增加只读契约检查。
- 为 `platform_account_session` 增加迁移存在性检查。
- 为 RealPublishGate 的 blocked 状态增加回归测试。
- 把硬编码本机路径的 SourcePack 测试改为可配置路径。

### 后端 / 数据库

- 核对 `001` 到 `027` 迁移和 `docs/24` 的一致性。
- 增加 `platform_account` 归一化表方案，但执行前需要设计裁决。
- 补 `media_publish` schema 的约束检查。
- 增加只读诊断脚本，输出当前 DB readiness。

### Amy Desk

- 增加只读状态页。
- 增加 Day0 / shadow run readiness 面板。
- 增加发布不可用原因展示。
- 增加 accounts 页面筛选和排序。

### PublishingRuntime 集成

- 完善 zhihu 单平台 session key 诊断。
- 增加 `MEDIA_PUBLISH_ROOT` / `MEDIA_PUBLISH_RUNTIME_ROOT` 检查。
- 将 `media_publish doctor` 结果结构化写入诊断报告。
- 明确非 zhihu 平台显示为 unsupported，而不是静默失败。

## 8. 需要先裁决的事项

不要在没有裁决时直接实现这些方向：

| 事项 | 影响 |
|---|---|
| 影子运行 vs 平行运行 | 影响 Day1-Day7 验收、发布状态、真实平台动作边界 |
| Phase 1A 表数 | 影响迁移收敛、表设计、schema hardening |
| “不做 MVP”条款修正 | 影响范围表达和发布前可用性标准 |
| 前端交互技术方案 | 影响 Amy Desk 的实现方式和测试方式 |
| 非 zhihu adapter 策略 | 影响 PublishingRuntime 集成路径 |
| 迁移 runner 标准 | 影响新人是否能安全初始化 DB |

## 9. 开工前自检

新开发者在认领任务前完成：

- [ ] 已读本文件和对应方向文档。
- [ ] 已确认任务属于“可立即认领”还是“需先裁决”。
- [ ] 已配置 `ARTIFACTOS_DB_*`，且目标库是 `artifactos_test`。
- [ ] `python tests/run_all_tests.py` 的当前结果已记录。
- [ ] 如涉及 Delphi，`./build.bat` 当前结果已记录。
- [ ] 如涉及发布，`media_publish doctor` 当前结果已记录。
- [ ] 如涉及 UI，已明确如何手工打开页面验证。
- [ ] 如涉及数据库，已明确迁移编号、目标 schema、回滚/重建方式。
- [ ] 不会触发真实发布，除非任务明确要求并经过人工批准。

## 10. 交付前自检

提交开发结果前完成：

- [ ] 改动范围只覆盖任务边界。
- [ ] 没有把凭据、cookie、浏览器 profile、`.media_publish/` 运行数据提交进仓库。
- [ ] Python 测试或相关单项测试已运行。
- [ ] Delphi 编译或相关 DUnitX 测试已运行，若任务涉及 Delphi。
- [ ] UI 任务已在浏览器中验证，若任务涉及 Amy Desk。
- [ ] 发布任务没有绕过 RealPublishGate。
- [ ] 文档中的命令、路径、schema 名称与代码一致。
- [ ] 剩余阻塞点已写清楚，不用“已完成”掩盖未裁决事项。
