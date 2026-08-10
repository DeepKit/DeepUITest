# DeepFlow 开发任务清单

> 更新日期：2026-08-10
>
> 当前状态：**DeepFlow v1.1 发布就绪 + 金路径闭环达成 + 六角色 LLM 真绿验证 + 104/104 测试全绿 + 可鉴 Web MVP 治理闭环（T10～T14）**

---

## 待办

| 编号 | 任务 | 优先级 |
|------|------|--------|
| T15 | 分享卡片导出质量优化：wrapText 4 行硬限截断、insight 行高重叠、canvas 固定高度内容溢出 | P2 |
| T16 | 真流式体验优化：上游讯飞 GLM 非增量流式（deltas=1，已知限制非代码 bug），候选方案为前端分片逐字渲染或切换流式模型 | P3 |
| T17 | WiseGateway 治理决策：计划任务 WiseGateway_Supervisor 已禁用（与手动启动争端口），需正式化启动方式（恢复 supervisor 或固化手动） | P2 |
| T18 | 可鉴 tests/ 补 T13/T14 自动化用例（流式 SSE + 历史持久化/复盘/删除/清空） | P3 |
| T19 | DeepInsight（洞见·思维显影室）× DeepFlow 集成：T19a 数据层已完成（个人决策数据服务端持久化 4a2bb003）；余项：五段显影 workflow / X 光片 skill / 树洞模式 / 跨会话记忆成长对比 | P1 **已完整交付** ✅ (4a2bb003 + 4269fc85) — xray/树洞/跨会话成长三功能全部完成

已完成项已移入 history.md / 下方"已完成里程碑"速览。

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
| Streaming Follow-up | T13：追问流式输出 SSE（client.py stream + /llm/chat/stream + 前端逐字显影 + 降级兜底），网关停摆根因定位并恢复（8460b9e0） | Completed |
| Decision History | T14：决策历史与复盘（localStorage 持久化 + 历史面板 + 一键回放 + 删除/清空），3 缺陷修复见 bugfix.md BUG-2026-036~038（5b31c355） | Completed |
| Data Persistence | T19a：个人决策数据服务端持久化（Skills SQLite CRUD + 前端同步/导出导入 + 端口探测），为 DeepInsight 集成奠基（4a2bb003） | Completed |


### DeepInsight × DeepFlow 集成评估结论 (2026-08-10)

> 问题：D:\_Progs\02Business\DeepInsight（洞见·思维显影室）软件功能可否通过 DeepFlow 实现？

**结论：可以，且已有可鉴 MVP 实证。** DeepInsight 基础版核心承诺（每周一决策/思维显影/可回看胶片）与可鉴已验证能力高度同构，DeepFlow 作为 workflow 运行时 + Skills 服务可承接全部核心能力，FMX 桌面壳保留为薄客户端或转 Web 形态。

| DeepInsight 功能 | DeepFlow 承接方式 | 实证状态 |
|------------------|--------------------|----------|
| 六 NPC（主持人/决策教练/架构师/诘问者/心理镜子/旁观者） | 可鉴六角色推演（coach/critic/mirror/observer/aggregator/film_generator）一一对应 | ✅ 已验证 |
| 决策胶片 | film_generator + 胶片视觉化（T10） | ✅ 已验证 |
| 脑内 X 光片（第三人称自我觉察） | 新增 X-ray skill（第三人称洞察生成），prompt 复用可鉴六角色模式 | 🔧 待实现 |
| 五段显影流程（问题→方案→风险→觉察→决策，可提前结束/跳过） | DeepFlow workflow JSON 编排（分支/条件/提前终止为核心能力） | 🔧 待实现 |
| 树洞模式（轻量陪伴 + 按需分析） | /llm/chat 轻量对话 workflow + 按钮触发 X 光片 | 🔧 待实现 |
| 跨会话记忆/旁观者成长对比 | DeepFlow Memory 系统（03.15 设计）+ Session 模块；一期可先 localStorage（T14 已验证） | 🔧 待实现 |
| @角色名点名发言 | 多轮对话 role 参数指定角色 | 🔧 待实现 |
| 桌面 FMX UI | 不重复实现：DeepInsight 降级为薄客户端调 Skills HTTP API，或迁入可鉴 Web 形态 | 方案已定 |

与三体架构（OCGS 定框架 + DeepFlow 执行 + DeepInsight 良知）一致：DeepInsight 定位"良知/觉察层"，其显影执行能力由 DeepFlow 承接，避免两套并行实现。


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

## 已完成里程碑 (本会话)

| 任务 | 内容 | Commit |
|------|------|--------|
| T19a | 个人决策数据服务端持久化（Skills SQLite CRUD + 前端同步/导出导入） | `4a2bb003` |
| T19b | 脑内 X 光片 skill + /llm/xray 端点（跨会话历史注入、温和第三人称观察） | `4269fc85` |
| T19c | 树洞模式（前端入口 + 陪伴对话 + 按需生成 X 光片分析） | `4269fc85` |
| T19d | 跨会话成长对比（历史摘要注入，识别旧模式与新成长） | `4269fc85` |

---

## 优先级说明

- **TASK-01xx**: 正名遗留项
- **P0**: 紧急阻塞性问题
- **P1**: MVP 必需
- **P2**: 完整功能
- **P3**: 维护优化
