# DeepFlow 开发任务清单

> 更新日期：2026-08-09
>
> 当前状态：**DeepFlow v1.1 发布就绪 + 金路径闭环达成 + 六角色 LLM 真绿验证 + 104/104 测试全绿**

---

## 待办

无待办任务。所有 TASK-01xx 系列工单（TASK-0101 ~ TASK-0104）已全部完成。

---

## 已完成里程碑

### 可鉴决策操作系统 MVP (2026-08-09)

| 模块 | 内容 | 状态 |
|------|------|------|
| Brand Archive | 产品定位文档（OCGS+DeepFlow+DeepInsight 三体架构） | Completed |
| Web MVP | 单页应用 + 品牌样式 + 六角色推演逻辑 | Completed |
| Skills Integration | 参数契约修正 + 字段映射 + 胶片渲染 | Completed |
| Virus Loop | 品牌水印 + 分享卡片 + 邀请链接 | Completed |
| E2E Tests | Python 端到端测试套件（kejian_e2e_test.py） | Completed |
| Load Test | 批量压力测试工具（stress_test.py） | Completed |
| Samples | 决策样本库生成器（100+ scenarios） | Completed |
| Documentation | README + API 文档 | Completed |
| Follow-up Chat | 胶片后继续追问（对话式治理，/llm/chat 多轮） | Completed |
| Scenario Templates | 行业决策场景模板：战略/投资/人事/采购四场景知识库，四角色 prompt 差异化注入（T8） | Completed |
| LLM Stability | T9：LLM_TIMEOUT 40s→90s（消除随机超时降级）+ 截断降级诊断（finish_reason=length → llm_response_truncated，六 skill 全覆盖） | Completed |
| Film Visual | T10：胶片视觉化升级，visual fields 契约 + 前端视觉组件 + 分享卡片洞察内容（e9a47ec9） | Completed |
| UI Fix | T11：聚合区 [object Object] 渲染修复（itemText 智能提取）+ film 变量作用域缺陷（881ff0fc） | Completed |
| Scenario Expansion | T12：行业场景模板扩展——新增医疗/法律/教育/家庭四场景四角色聚焦（34dfa198） | Completed |


### 核心开发里程碑 (2024-12 ~ 2025-12)

| 里程碑 | 内容 | 状态 |
|--------|------|------|
| M1 | 核心框架 (Phase 1-3) | 已完成 |
| M2 | 完整流程 (Phase 4-6) | 已完成 |
| M3 | 生产就绪 (Phase 7-8) | 已完成 |
| P2 | 可选增强 (Audit/Metrics/Skills/Editor) | 已完成 |
| P3 | 维护任务 (SQLite/WebSocket/CI/Docs) | 已完成 |
| P4-A | DeepBase 集成 | 已完成 |
| P4-B | 中文文档 | 已完成 |
| P4-C | Event Sourcing | 已完成 |
| P4-D | 分析与可视化 | 已完成 |
| P4-E | 性能优化 | 已完成 |
| P4-F | 多租户支持 | 已完成 |
| P4-G | 插件系统 | 已完成 |
| P5-A | 生产加固 | 已完成 |
| P5-B | 功能增强 | 已完成 |
| P5-C | 平台集成 | 已完成 |
| P6-A | 云原生支持 | 已完成 |
| P6-B | AI 增强 | 已完成 |

### DeepFlow 正名 (2026-08-06)

| 任务 | 内容 | 状态 |
|------|------|------|
| 文档正名 | 73 篇 .md UniFlow 转 DeepFlow, 两层命名 UpFlow/deepFlow | 已完成 |
| 代码 unit 改名 | 68 个 .pas unit/program/uses 全改 DeepFlow.* | 已完成 |
| schema URI 纠正 | $id uniflow:// 转 deepflow://, author/URL 同步 | 已完成 |
| 03.07 自指修复 | 标题/对比表/命名约定修正 | 已完成 |
| 术语表扩写 | 02.07 补 UpFlow/deepFlow 条目 | 已完成 |
| ADR 备案 | ADR-002 已批准 | 已完成 |
| 冗余清理 | 3 个冗余 prompt 删除 + Editor favicon | 已完成 |
| 类型标识符重命名 | 25 个文件 477 处 TUniFlowXxx→TDeepFlowXxx, 零残留 | 已完成 (commit fb6fbadf) |

### 2026-08-07: UTF-8 损坏修复

| 任务 | 内容 | 状态 |
|------|------|------|
| TASK-0102 | 39 个 .pas 文件 UTF-8 损坏修复 | 已完成 |
| BUG-2026-007 | 39 个文件评论中文损坏：git checkout HEAD 恢复 | 已完成 (commit ea96fdc6) |
| tools/utf8-fix-analyzer.py | UTF-8 损坏检测工具 | 已完成 |

### 2026-08-07: 构建配置完成

| 任务 | 内容 | 状态 |
|------|------|------|
| TASK-0103 | DeepBase 外部依赖路径配置 | 已完成 |
| DeepFlow.dpk | DeepFlow 运行时包文件 | 已完成 |
| DeepFlow.dproj | MSBuild 项目配置（含 DeepBase Core 搜索路径） | 已完成 |

### 2026-08-07: Delphi 编译完整修复里程碑

| 任务 | 内容 | 状态 |
|------|------|------|
| TASK-0104 | Source\*所有.pas 文件 Delphi 37 dcc32 编译通过 | 已完成 (零 Error) |
| fix-nlwf | NLWorkflowGen.pas implicit forward + trailing comma | 已完成 |
| fix-utf8 | 128 处代码字符串 UTF-8 损坏批量修复 | 已完成 |
| fix-reco | Recommendation.pas TComparer/API mismatch 修复 | 已完成 |
| fix-rabbitmq | RabbitMQ.pas 接口声明顺序修复 | 已完成 |
| fix-kafka | Kafka.pas cross-unit reference + E2251 cascade | 已完成 |
| fix-benchmark | Benchmark.pas Tests API 不匹配修复 | 已完成 |
| fix-e2e | E2E.pas Tests API 不匹配修复 | 已完成 |
| fix-executor | Executor.pas Uses/WillRaise/TTask.Run 修复 | 已完成 |
| dcu-search-path | 添加 dcu 到 -U 搜索路径 | 已完成 |

### 2026-08-07~08: DUnitX 测试驱动修复里程碑 (44→104 全绿)

| 任务 | 内容 | 状态 |
|------|------|------|
| TASK-0105 | DUnitX 测试运行器建立（DeepFlow.Tests.Runner.dpr + XML 报告 + 逐 fixture 运行） | 已完成 |
| TASK-0106 | Executor 测试 55/55（SetVariable 重定向/AsString 标量/表达式防嵌套/Start 保留输出/并行捕获修复/Mock 加锁） | 已完成 |
| TASK-0107 | E2E 测试 29/29（Guard expression 守卫 + length 过滤器 + Session 定时器死锁 + 编译路径补 Source\Session） | 已完成 |
| TASK-0108 | Benchmark 测试 20/20（TMemoryMonitor 匿名线程悬垂句柄 + LargeContext/LeakDetection JSON 泄漏修复） | 已完成 |
| 测试总闸 | 104/104 通过，0 失败/0 泄漏/0 错误 | 已完成 (2026-08-08) |

### 2026-08-08: Python Skill 服务真实联调里程碑

| 任务 | 内容 | 状态 |
|------|------|------|
| TASK-0109 | Skills 服务依赖修复（补装 litellm/structlog/RestrictedPython/packaging，修复损坏 packaging 安装） | 已完成 |
| TASK-0110 | 创建缺失 llm/client.py（LiteLLM 异步聊天客户端 + LLMConfig + ChatResult） | 已完成 |
| TASK-0111 | Python Skill Service 启动验证：/health、/skills、/skills/execute 沙箱执行 5050、安全拦截 import os 拒绝 | 已完成 |
| TASK-0112 | Delphi E2E 演示程序（DeepFlowSkillE2E.pas）：Health/ListSkills/沙箱执行/安全拦截四连验证 | 已完成 |
| 联调成果 | Delphi TSkillClient ↔ Python FastAPI 全链路打通；修复 2 个真实契约 bug（见 bugfix.md BUG-2026-031/032） | 已完成 |
| 回归验证 | 修改 Skill.Types/Client 后全量 104/104 仍全绿 | 已完成 |
| LLM 真调 | /llm/chat 需要有效 OPENAI_API_KEY（当前环境网络受限，代码路径已就绪待真实 key） | 待真 key |

### 2026-08-08: 金路径闭环 + 发布就绪（v1.1.0）

| 任务 | 内容 | 状态 |
|------|------|------|
| TASK-0113 | LLM 链路修复（KIRO_API_KEY + DEFAULT_LLM_MODEL + LLM_BASE_URL 环境变量；Skills 服务重启后 /llm/chat 真实可用） | 已完成 |
| TASK-0114 | 防假绿机制（六角色 system prompt 强制 JSON + _parse_response 围栏提取 + raw_analysis 检测主动降级） | 已完成 |
| TASK-0115 | 聚合器扩容（max_tokens 8192 + _compact_view 输入压缩，修复真实数据截断降级） | 已完成 |
| TASK-0116 | 金路径端到端演示（goldpath_demo.py 并行四视角 + 聚合 + 胶片 + 产物落盘） | 已完成 |
| 发布验证 | Delphi 编译 64/64 + 测试 104/104 + 六角色 LLM 真绿 degraded=False + 端到端胶片产出 | 已完成 (2026-08-08) |
| 版本 | CHANGELOG 更新至 v1.1.0 | 已完成 |

---

## 相关文档

- `history.md` - 开发历史详细记录
- `bugfix.md` - Bug 修复详细记录
- `ADR/ADR-002-术语纠正与 unit 改名.md` - 正名决策记录
- `tools/verify-term-rename.py` - 术语一致性检查脚本
- `tools/utf8-fix-analyzer.py` - UTF-8 损坏检测工具
- `DeepFlow.dpk` - DeepFlow 运行时包文件
- `DeepFlow.dproj` - MSBuild 项目配置
- `docs/zh/` - 中文文档

---

## 优先级说明

- **TASK-01xx**: 正名遗留项
- **P0**: 紧急阻塞性问题
- **P1**: MVP 必需
- **P2**: 完整功能
- **P3**: 维护优化

| T14 | 决策历史与复盘：localStorage 持久化 + 历史面板 + 一键回放 + 删除/清空（兑现可复盘承诺） | 已完成 (2026-08-10) |
