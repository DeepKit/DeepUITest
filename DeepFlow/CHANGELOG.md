# UniFlow Changelog

All notable changes to UniFlow Workflow Engine are documented in this file.

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
- Chinese docs: 快速入�? 工作流格�? Skill开�? 部署指南
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

---

**UniFlow Version**: 1.0.0
**Minimum DeepBase Version**: 1.0.0
**Generated**: 2025-12-08
