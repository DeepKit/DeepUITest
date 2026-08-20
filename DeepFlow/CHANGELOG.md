# DeepFlow Changelog

All notable changes to DeepFlow Workflow Engine are documented in this file.
## [可鉴 v1.0.0] - 2026-08-11

### Added - 六角色决策治理闭环
- **六角色并行推演**：coach/critic/mirror/observer 四视角 + aggregator 聚合共识，LLM 驱动的真实认知增强
- **胶片生成**：决策思维胶片输出，强调过程而非结论（哲学合规）
- **视觉化呈现**：洞察卡、权衡对比、情绪谱、决策成熟度可视化
- **行业场景模板**：战略/投资/人事/采购四场景知识库，差异化 Prompt 注入

### Added - T13/T14 追问流式与历史持久化
- **流式追问**：胶片后继续对话，SSE 实时推送新推演结果
- **服务端持久化**：治理历史记录 SQLite WAL 存储，支持 CRUD、导出/导入、跨浏览器同步
- **端口自适应**：Skills 服务 8001/8002 双实例探测绕行，自动选择可用路由（封版审计：8001 幽灵进程问题解决）

### Added - T19 DeepInsight×DeepFlow 集成
- **脑内 X 光片**（decision/treehole 双模式）：第三人称自我觉察分析，识别核心执着/旧模式/成长点
- **跨会话成长对比**：结合历史会话摘要，指出与以往相比的差异或成长
- **树洞模式**：轻量倾诉陪伴，随时生成温和诚实的 X 光片反馈
- **服务端持久化**：个人决策数据统一由 Skills /governance/history CRUD 管理

### Added - T20 WiseGateway 多家族 LLM 治理
- **call_by_name 统一网关**：通过 WiseGateway 8000 调用不同模型家族（GPT/GLM/Kimi/Qwen/等）
- **llm/families 映射表**：返回 8 个家族 LLM 可用名称，供前端动态选择
- **多模型会诊能力**：支持按名调用特定家族 LLM，不强制绑定 GPT 链

### Fixed - 降级容错机制
- **真实绿验证**：所有 LLM skill 非模板降级，degraded=False 保证真实推理
- **截断降级诊断**：finish_reason=length → llm_response_truncated，明确记录降级原因
- **四角色并发超时优化**：timeout 90s+ 线程池并发，整体链路 ~90s

### Testing & Quality
- **E2E 测试**：Python aiohttp 端到端测试套件（kejian_e2e_test.py）
- **压力测试**：批量并发调用工具（stress_test.py）
- **v2 冒烟测试**：T13-T20 新功能覆盖（kejian_v2_smoke_test.py），10/10 全绿
- **样本生成器**：100+ 真实决策场景库（generate_samples.py）

### Operations
- **start_skills.bat**：端口自适应启动（8001 优先绑定，失败自动尝试 8002）
- **前端健康探测**：两轮探测（持久化路由→health），自动选择可用技能服务实例
- **SQLite WAL**：治理历史数据库写入日志模式，避免跨请求阻塞



## [1.1.0] - 2026-08-08

### Added - Insight Gold Path MVP P0
- **Decision Coaching** - Six-role multi-view analysis for decision support (coach/critic/mirror/observer)
- **Aggregation Engine** - Intelligent synthesis of multi-perspective insights with LLM-powered summarization
- **Film Generator** - Decision思维胶片 output emphasizing process over conclusions (philosophy-compliant)
- **Parallel Role Fork** - Concurrent four-view reasoning workflow compatible with workflow engine forks

### Fixed - Green Path Authenticity (防假绿机制)
- **LLM Output Parsing** - Enhanced JSON extraction with code fence support (` ```json ... ````)
- **Decay Detection** - Automatic fallback to templates when LLM returns non-JSON (prevents "fake green" outputs)
- **Aggregator Expansion** - Increased `max_tokens` to 8192, added input compression to prevent truncation errors
- **Decoy Prevention** - All six roles now verified as real LLM calls (degraded=False), no template fallback in normal scenarios

### Improved - Performance & Reliability
- **Timeout Configuration** - Default timeout increased to 120s for LLM skill execution
- **Concurrent Execution** - Thread pool for parallel role inference (4 workers max)
- **API Contract** - Changed `skill` field to `skill_name` in `/skills/execute` endpoint

### Testing & Demo
- **End-to-End Demo** - Python demo script (`Examples/Integration/goldpath_demo.py`) validates complete gold path
- **Degradation Test** - Unit tests verify all six roles work normally with degraded=False
- **Delphi Tests** - All 104 tests passing successfully

### Statistics
- **Verifcation Result**: ✅ Six roles 100% true LLM calls, 0% template degradation
- **Performance**: ~20-35s per role, total pipeline ~90s with concurrent execution

---

## [1.0.0] - 2025-12-08

### Added - Core Engine
- **Workflow Definition** - JSON-based workflow schema with steps, conditions, loops, parallel
- **Workflow Executor** - Step execution, branching, error handling, retry policies
- **Workflow Context** - Variable scoping, expression evaluation, template filters
- **Workflow State** - Instance management, snapshots, event logging

### Added - Event Sourcing
- **Event Store** - Append-only event storage with replay capability
- **Snapshots** - Periodic state snapshots for fast recovery
- **Event Replay** - Full state reconstruction from events

### Added - Multi-Tenant Support
- **Tenant Isolation** - Separate data and execution contexts per tenant
- **Quota Management** - Resource limits and usage tracking
- **Tenant Console** - Web-based tenant management UI

### Added - Plugin System
- **Plugin Interface** - `IUniFlowPlugin` for extensibility
- **Plugin Loader** - Dynamic BPL loading with dependency resolution
- **Plugin Registry** - Centralized plugin management

### Added - AI Integration
- **LLM Adapter** - Integration with DeepBase.LLM (OpenAI/Claude/Azure/Ollama)
- **Smart Retry** - AI-powered failure analysis and retry strategies
- **Anomaly Detection** - ML-based workflow anomaly detection
- **NL Workflow Gen** - Natural language to workflow conversion
- **Recommendation** - Intelligent workflow suggestions

### Added - Cloud Native
- **Kubernetes** - Deployment manifests and Helm charts
- **Istio** - Service mesh integration
- **OpenTelemetry** - Distributed tracing support

### Added - Skills
- **Python Skills** - HTTP client, data transformer, code executor
- **Node.js Skills** - JSON transform, text processing, file utils
- **Skill Client** - HTTP-based skill invocation

### Added - Web Tools
- **Visual Editor** - Drag-and-drop workflow designer
- **Analytics Dashboard** - Execution metrics and visualizations
- **Tenant Console** - Multi-tenant management interface

### Added - Storage Backends
- **SQLite** - Default embedded storage
- **PostgreSQL** - Production-grade storage
- **RabbitMQ/Kafka** - Message queue integration

### Added - Security
- **Expression Sanitizer** - Injection prevention
- **Audit Logging** - Sensitive data masking
- **Rate Limiting** - Request throttling
- **SSRF Protection** - Internal IP filtering

### Fixed - Security Vulnerabilities (P0)
- TASK-2100: Sandbox escape in code_executor.py
- TASK-2101: SSRF in http-request.js
- TASK-2102: JSON parse exceptions in node-types.js
- TASK-2103: Error message information leakage
- TASK-2104: Storage operation feedback
- TASK-2105~2109: Code quality and XSS fixes

### Fixed - Bug Fixes (125 total)
- Critical: 1
- High: 95
- Medium: 22
- Low: 7

### Documentation
- English docs: Quick Start, Workflow Format, Skills Development, Deployment
- Chinese docs: 快速入门，工作流格式，Skill 开发，部署指南
- API Reference
- Architecture Design docs (30+ documents)

### Statistics
- **Total Lines**: ~112,000+
- **Pascal Source**: 64 files, ~74,000 lines
- **Python Skills**: 4 files, ~1,450 lines
- **Node.js Skills**: 7 files, ~1,100 lines
- **Web Editor**: 11 files, ~4,500 lines
- **Tests**: ~6,000 lines

---

## Known Limitations

### Pending Optimizations (P2/P3)
- TASK-1100~1103: Architecture hardening
- TASK-1200~1202: Core performance optimization
- TASK-1300~1306: Infrastructure hardening
- TASK-1400~1403: Database improvements
- TASK-1500~1503: Business module refactoring
- TASK-1600~1603: Resilience optimization
- TASK-1700~1703: Architecture support
- TASK-1802~1803: Code consistency audit

These are optimization tasks and do not affect core functionality.

---

## Upgrade Notes

### From Pre-release
1. Update workflow JSON schema to v1.0 format
2. Migrate event store if using custom backend
3. Review security configurations

### API Changes
- Use `DeepBase.LLM` instead of `UniFlow.AI.LLMClient`
- Error codes follow `{Source}/{Category}/{Specific}` format
- Skill request field changed from `skill` to `skill_name`

---

**DeepFlow Version**: 1.1.0
**Minimum DeepBase Version**: 1.0.0
**Generated**: 2026-08-08
