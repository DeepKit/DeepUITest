# InkFlow v2 开发任务清单

> **状态**：Pre-M0/M0/M1/M2/M3 核心门禁已通过；M4 review baseline 已完成本地验证
> **最后更新**：2026-07-05

---

## P0 决策归档（13 个）

以下问题已经拍板，作为 Pre-M0 与 M0 的实现约束保留。新开发不再围绕这些问题重复讨论；若实现中发现文档与代码不可同时满足，先修本文和正式设计文档，再继续开发。

### 数据库设计问题（5 个）

#### D1. `writer_model_pool` JSON 校验策略

**问题**：
- `writer_model_pool` 是 JSON array，但未校验元素是否为有效字符串
- 未校验元素是否重复（`["gpt-4", "gpt-4"]` 能通过但无意义）
- 未校验 `jury_model_pool` 与 `writer_model_pool` 是否有交集（P0-4 要求裁判模型 ≠ 写手模型）

**建议方案**：
- 应用层校验（推荐）：在 `ProjectValidator` 类中校验
- 或在 `writing_projects` 触发器中校验（DB 层难以表达复杂逻辑）

**决策状态**：已决策。

**最终决策**：
- DB 层只做底线校验：`json_valid(pool)`、`json_type(pool)='array'`、`json_array_length(pool) >= draft_count`、`jury_model_pool` 长度不低于 `jury_model_pool_min`。
- 应用层 `ProjectConfigValidator` 做完整校验：数组元素必须是非空唯一字符串；`writer_model_pool` 与 `jury_model_pool` 默认无交集。
- 如果供应商有限必须允许重叠，排除当前 draft 的 `writer_model` 后仍必须有至少 3 个可用 jury model。

---

#### D2. `checkpoint.shot_id` NULL 语义

**问题**：
- `shot_id` 在 checkpoint 中可为 NULL（session 级 checkpoint 不绑特定 shot）
- 但 FK 约束要求非 NULL 时必须在 `writing_shots` 中存在
- 未明确：NULL 的 shot_id 是否允许？如果允许，FK 约束如何处理？

**建议方案**：
```sql
-- 方案 A：允许 NULL，FK 约束自动忽略 NULL
shot_id TEXT,  -- 可为 NULL
FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id)  -- NULL 时 FK 不检查

-- 方案 B：添加格式校验
shot_id TEXT CHECK (shot_id IS NULL OR shot_id LIKE '%@%'),
```

**决策状态**：已决策。

**最终决策**：
- 允许 `writing_session_checkpoints.shot_id` 为 `NULL`；`NULL` 表示 session/phase 级 checkpoint，不绑定具体 shot。
- 非 `NULL` 时必须满足 `shot_id LIKE '%@%'`，并由 FK 指向 `writing_shots(shot_id)`。

---

#### D3. `jury_raw_scores` 裁判-写手模型隔离校验

**问题**：
- 文档说"按 draft 动态排除写手模型"，但未在 DB 层强制
- 如果写手模型意外进入 jury，DB 层无法拦截

**建议方案**：
- 应用层在 `literary_jury.dispatch` 时校验（推荐）
- 落库后审计查询：
```sql
-- 审计查询：裁判模型 ≠ 写手模型
SELECT r.draft_id, r.judge_model, d.writer_model
FROM writing_jury_raw_scores r
JOIN writing_drafts d ON r.draft_id = d.draft_id
WHERE r.judge_model = d.writer_model;
```

**决策状态**：已决策。

**最终决策**：
- `literary_jury.dispatch` 必须按 draft 动态排除该 draft 的 `writer_model`。
- DB 增加 trigger，在写入 `writing_jury_raw_scores` 时阻止 `judge_model = writing_drafts.writer_model`。
- 测试保留落库后 JOIN 审计查询，要求结果为空。

---

#### D4. `shot_revisions.is_current` 更新逻辑

**问题**：
- 文档说"封版后读 is_current"，但未说明何时设置 `is_current=1`
- 如果多个 revision 的 `is_current=1`，VIEW 会返回多行
- 未明确：是否有触发器或应用层逻辑保证每 shot 恰一个 `is_current=1`？

**建议方案**：
```python
# 应用层逻辑（text_repository.write_revision / hard seal 分支）
def seal_revision(self, revision_id: int) -> None:
    shot_id = self._get_shot_id(revision_id)
    with self.db.transaction():
        self.db.execute(
            "UPDATE writing_shot_revisions SET is_current = 0 WHERE shot_id = ?",
            (shot_id,)
        )
        self.db.execute(
            "UPDATE writing_shot_revisions SET is_current = 1 WHERE revision_id = ?",
            (revision_id,)
        )
```

**决策状态**：已决策。

**最终决策**：
- 只允许 `TextRepository` 在硬封版事务中设置 `is_current=1`。
- 事务内先清同 shot 旧 `is_current`，再设置目标 revision。
- DB 加 partial unique index：每个 `shot_id` 最多一个 `is_current=1`。

---

#### D5. 时间字段格式统一约定

**问题**：
- 所有 `created_at`、`evaluated_at` 等时间字段类型为 `TEXT`，但未明确格式
- 可选：ISO 8601、Unix timestamp、SQLite datetime

**建议方案**：
- 统一使用 ISO 8601 格式（`YYYY-MM-DDTHH:MM:SS.sssZ`），UTC 时区
- 在 `design-v2.md §1.4` 或 `implementation-contract-v1.md §2` 开头统一约定

**决策状态**：已决策。

**最终决策**：
- 所有时间字段统一 UTC ISO 8601：`YYYY-MM-DDTHH:MM:SS.sssZ`。
- 应用层统一通过 `now_utc_iso()` 写入；不使用 SQLite 本地时间函数作为业务时间源。

---

### Python 应用设计问题（4 个）

#### E1. `MetaContract` 与 `writing_projects` 的关系

**问题**：
- `MetaContract` 是 pydantic schema，对应 `writing_meta_contracts` 表
- 但 `writing_projects` 表也有运营参数（`shot_quality_floor` 等）
- 未明确：应用层如何加载完整的项目配置？

**可选方案**：
- 方案 A：`MetaContract` 包含 `writing_projects` 的字段（冗余，不推荐）
- 方案 B：分开加载，`ProjectConfig = MetaContract + WritingProject`（推荐）
- 方案 C：`MetaContract` 不再存在，全部在 `writing_projects`（破坏性变更）

**建议方案**：
```python
@dataclass
class ProjectConfig:
    project: WritingProject  # 从 writing_projects 加载
    meta_contract: MetaContract  # 从 writing_meta_contracts 加载
    chapter_specs: list[ChapterSpec]  # 从 writing_chapter_specs 加载

    @classmethod
    def load(cls, project_id: int, db: Database) -> 'ProjectConfig':
        project = db.fetchone("SELECT * FROM writing_projects WHERE project_id = ?", (project_id,))
        meta = db.fetchone("SELECT * FROM writing_meta_contracts WHERE project_id = ?", (project_id,))
        specs = db.fetchall("SELECT * FROM writing_chapter_specs WHERE project_id = ?", (project_id,))
        return cls(
            project=WritingProject.from_row(project),
            meta_contract=MetaContract.from_row(meta),
            chapter_specs=[ChapterSpec.from_row(s) for s in specs]
        )
```

**决策状态**：已决策。

**最终决策**：
- 采用方案 B：`ProjectConfig = WritingProject + MetaContract + ChapterSpecs`。
- 运营参数只在 `writing_projects`，不塞回 `MetaContract`。
- `MetaContract` 保留文学/世界观/风格契约；质量阈值和运行阈值从 `WritingProject` 读取。

---

#### E2. `orchestrator.process_shot` 函数签名

**问题**：
- 文档说"orchestrator 入口只收 `(shot_id, run_id)`"
- 但未定义完整的函数签名和前置条件

**建议方案**：
```python
def process_shot(shot_id: str, run_id: int) -> None:
    """
    处理单个 shot 的完整流水线。
    
    Pre-condition:
    - shot_id 必须在 writing_shots 中存在
    - shot_id 必须能从 DB 反查到 session_id
    - shot_id 格式必须为 {logical}@{run}
    - shot_status 不能是终态（hard_sealed/failed）
    
    Post-condition:
    - shot_status 推进到下一个合法状态
    - 所有中间结果落库（drafts/scores/aggregates）
    - 如果失败，shot_status 转为 failed 或保持不变（可重试）
    
    Raises:
    - IllegalTransitionError: shot_status 已是终态
    - ShotNotFoundError: shot_id 不存在
    - SessionMismatchError: shot_id 不属于 session_id
    """
```

**决策状态**：已决策。

**最终决策**：
- shot 级 orchestrator 入口只收 `(shot_id, run_id)`，不传 `session_id`。
- `session_id` 从 `writing_shots` / `writing_runs` 反查并校验，避免调用方把错误 session 传入。

---

#### E3. `text_repository` 完整 API

**问题**：
- 文档说"text_repository 三重隔离"，但未定义完整 API

**最终接口**：
```python
class TextRepository:
    """正文真相源隔离（铁律 5）。"""
    
    def read_current_text(self, shot_id: str, run_id: int) -> str:
        """读取当前正文。业务调用只允许走 v_current_text 语义。"""
        ...

    def write_revision(
        self, shot_id: str, run_id: int, text: str,
        source_revision_id: int | None = None,
        seal: Literal["none", "shot_soft", "chapter_hard"] = "none",
    ) -> int:
        """写入 revision；仅 chapter_hard 分支设置 is_current。"""
        ...

    def is_hard_sealed(self, shot_id: str, run_id: int) -> bool:
        """判断 shot 是否已有硬封版当前正文。"""
        ...
```

**决策状态**：已决策。

**最终决策**：
- 公开 API 保持最小面：`read_current_text`、`write_revision`、`is_hard_sealed`。
- 不公开 `get_revision`、`get_revision_history`、`get_text_by_revision_id` 等绕过封版语义的接口；审计查询只能放在测试/诊断工具中，不进入业务模块。

---

#### E4. 错误类型层次定义

**问题**：
- 文档提到多种错误，但未定义错误层次

**建议方案**：
```python
# src/ink/errors.py

class InkError(Exception):
    """Base error for all InkFlow errors."""

# 状态机相关错误
class StateError(InkError):
    """状态机相关错误的基类。"""

class IllegalTransitionError(StateError):
    """非法状态转移。"""

class TerminalStateError(StateError):
    """终态无出边。"""

# 并发相关错误
class ConcurrencyError(InkError):
    """并发相关错误的基类。"""

class ConcurrentModificationError(ConcurrencyError):
    """乐观锁 CAS 失败。"""

# 质量相关错误
class QualityError(InkError):
    """质量相关错误的基类。"""

class QualityGateFailedError(QualityError):
    """质量门禁未通过。"""

class QualityFloorNotMetError(QualityError):
    """质量地板未达标。"""

# 数据相关错误
class DataError(InkError):
    """数据相关错误的基类。"""

class ShotNotFoundError(DataError):
    """shot_id 不存在。"""

class SessionMismatchError(DataError):
    """shot_id 不属于 session_id。"""

# 配置相关错误
class ConfigError(InkError):
    """项目配置或模型池配置错误的基类。"""

class ModelPoolValidationError(ConfigError):
    """模型池配置非法。"""

# LLM 相关错误
class LLMError(InkError):
    """LLM 调用相关错误的基类。"""

class LLMUnavailableError(LLMError):
    """必须使用的模型层级不可用。"""
```

**决策状态**：已决策。

**最终决策**：
- 建 `src/ink/errors.py`，统一错误根类 `InkError`。
- 错误层级包括 `StateError`、`ConcurrencyError`、`QualityError`、`DataError`、`ConfigError`、`LLMError`。

---

### 测试策略问题（4 个）

#### F1. 单元测试 vs 集成测试边界

**问题**：
- 未明确哪些是单元测试、哪些是集成测试、哪些是端到端测试

**建议方案**：
```
单元测试（70%）：
- 单个 dataclass 的 unpack() 正确性
- 单个 gate 的判定逻辑（mock DB）
- 单个状态转移的合法性（mock DB）
- 路径：tests/unit/

集成测试（25%）：
- orchestrator 完整流水线（mock LLM，真实 DB）
- text_repository 封版逻辑（真实 DB）
- jury 评分聚合（真实 DB）
- 路径：tests/integration/

端到端测试（5%）：
- 完整 6 章写作（mock LLM 默认；真实 LLM 手动或 nightly）
- 崩溃恢复（模拟崩溃）
- 导入/导出（真实文件）
- 路径：tests/e2e/
```

**决策状态**：已决策。

**最终决策**：
- unit：纯逻辑、schema、lint、自包含函数，不依赖真实 DB。
- integration：真实 SQLite + mock LLM，覆盖 orchestrator、repository、jury 聚合、resume。
- e2e：CLI 全流程，默认 mock LLM；真实 LLM 测试不进入默认 CI，只作为手动或 nightly 验收。

---

#### F2. 测试数据生成策略（fixture 规范）

**问题**：
- 未明确测试用的 project/shot 如何创建
- 未明确 LLM 响应如何 mock

**建议方案**：
```python
# tests/conftest.py

@pytest.fixture
def test_project(db):
    """创建测试项目，返回 project_id。"""
    project_id = db.execute("""
        INSERT INTO writing_projects (code, title, ...) VALUES (?, ?, ...)
    """, ("TEST", "Test Project", ...))
    return project_id

@pytest.fixture
def test_meta_contract(db, test_project):
    """创建测试元契约，返回 meta_contract_id。"""
    ...

@pytest.fixture
def test_shot(db, test_project, test_session):
    """创建测试 shot，返回 shot_id。"""
    shot_id = f"ch1_s1@run1"
    db.execute("""
        INSERT INTO writing_shots (shot_id, session_id, ...) VALUES (?, ?, ...)
    """, (shot_id, test_session, ...))
    return shot_id

@pytest.fixture
def mock_llm(monkeypatch):
    """Mock LLM 调用，返回固定响应。"""
    responses = {
        'drafting': '这是一段测试正文...',
        'jury_scoring': '{"score": 85, ...}',
    }
    def mock_call(prompt, model, call_type):
        return {"text": responses.get(call_type, "Mock response"), "tokens": 100}
    monkeypatch.setattr("ink.llm.LLMGateway.call", mock_call)
```

**决策状态**：已决策。

**最终决策**：
- 使用 builder/factory fixture 创建 project、session、run、shot、draft、revision，避免每个测试手写 INSERT。
- mock LLM 按 `(call_type, model, shot_id, attempt)` 返回固定结构化响应，支持失败、超时、JSON 错误和 smart-model-unavailable 场景。

---

#### F3. 性能测试基线

**问题**：
- 未提及性能测试
- 未定义耗时基线

**建议方案**：
在 M6 添加性能测试：
```python
# tests/e2e/test_performance.py

def test_shot_pipeline_performance(db, test_shot, mock_llm):
    """单次 shot 流水线耗时 < 5 分钟。"""
    start = time.time()
    process_shot(test_shot.shot_id, test_shot.run_id)
    elapsed = time.time() - start
    assert elapsed < 300, f"Shot pipeline took {elapsed}s, expected < 300s"

def test_jury_scoring_performance(db, test_draft, mock_llm):
    """单次 jury 评分耗时 < 30 秒。"""
    start = time.time()
    score_draft(test_draft.draft_id)
    elapsed = time.time() - start
    assert elapsed < 30, f"Jury scoring took {elapsed}s, expected < 30s"

def test_checkpoint_recovery_performance(db, test_session):
    """单次 checkpoint 恢复耗时 < 10 秒。"""
    start = time.time()
    recover_session(test_session.session_id)
    elapsed = time.time() - start
    assert elapsed < 10, f"Checkpoint recovery took {elapsed}s, expected < 10s"
```

**决策状态**：已决策。

**最终决策**：
- 默认 CI 只测 mock LLM 下的性能和复杂度，不用真实 LLM 墙钟时间做阻断。
- M6 生产验收单独记录真实 LLM 成本、耗时、失败率；这些数据用于调参，不作为本地单测门禁。

---

#### F4. 安全测试需求

**问题**：
- 未提及安全测试

**建议方案**：
在 M6 添加安全测试：
```python
# tests/e2e/test_security.py

def test_sql_injection_in_prompt(db, test_shot):
    """Prompt 中的恶意 SQL 不影响系统。"""
    malicious_prompt = "'; DROP TABLE writing_shots; --"
    create_revision(db, test_shot.shot_id, malicious_prompt)
    # 验证 writing_shots 表未被删除
    count = db.fetchone("SELECT count(*) FROM writing_shots")[0]
    assert count > 0, "SQL injection succeeded!"

def test_cross_project_access_control(db, test_project_a, test_project_b):
    """用户 A 不能访问用户 B 的项目。"""
    # 假设 test_project_a 属于 user_a，test_project_b 属于 user_b
    with pytest.raises(AccessDeniedError):
        load_project_config(test_project_b, user_id="user_a")

def test_sensitive_data_not_leaked_to_llm(db, test_shot):
    """LLM 响应中不包含敏感信息。"""
    # 验证 prompt 中不包含密码、token 等敏感信息
    prompt = compile_prompt(test_shot.shot_id)
    assert "password" not in prompt.lower()
    assert "api_key" not in prompt.lower()
```

**决策状态**：已决策。

**最终决策**：
- M0/M1 先覆盖 SQL 注入、动态 SQL/f-string SQL lint、正文表访问隔离、供应商 SDK 直连拦截。
- M6 增加 import path/source hash、prompt 敏感信息泄漏、export 结构标签清理测试。
- 多用户访问控制暂不进入当前版本；当前战略定位为单作者本地生产工具。

---

## 战略决策（已拍板）

| 问题 | 决策 | 影响 |
|------|------|------|
| 实现路线 | 采用“生产内核优先”：M0/M1 全做实，再用 1 章质量证明校准，之后扩展到 M2-M6 | 不裁剪生产范围，但先验证质量链路是否有效 |
| 产品形态 | 单作者本地生产工具 | 暂不引入多用户权限、租户、团队协作锁 |
| 数据库路线 | SQLite 实现，repository/DDL/事务纪律按未来 PostgreSQL 迁移预留 | 当前减少部署复杂度，未来可迁移到 RLS/advisory lock |
| 质量门禁策略 | M4-M6 验收期从严；稳定后低风险项可参数化，hard gate 不可降级 | 先证明质量上限，再基于数据调参 |
| 开工策略 | 先完成 Pre-M0 开工门禁，再进入 M0 正常开发 | 架构/DDL/状态机/测试边界问题不得带条件进入实现 |

---

## 开发任务队列

### 已完成的文档收口

- [x] 将“带条件开工”改为 **Pre-M0 开工门禁**：Pre-M0 未完成，不进入 M0。
- [x] 明确基础 jury 轮与分歧升级轮：`jury_round=1` 为 3 裁判全评 12 维；`jury_round>1` 使用 `escalated_jury_count`。
- [x] 修正 `writing_jury_raw_scores` 唯一约束：使用 `(draft_id, jury_round, judge_slot)` 与 `(draft_id, jury_round, judge_model)`。
- [x] 在 `writing_jury_aggregates` 增加 `jury_round_used`、`judge_count`，记录实际采用的裁判轮次和人数。
- [x] 统一 orchestrator 入口口径：shot 级只收 `(shot_id, run_id)`；chapter/book/import/export 只收自身业务 ID；所有入口禁止传上游 dataclass。
- [x] 修正 resume 示例 SQL：通过 `writing_runs.session_id` JOIN `writing_shots`，不在 `writing_shots` 上假设 `session_id`。
- [x] 修正 runtime event 时间字段：统一写入 `created_at`，不使用旧事件时间字段。
- [x] 明确字段消费 lint 边界：动态 dataclass 访问全局禁止；全字段消费强检查只作用于契约边界函数和 `@requires_full_field_consumption`。
- [x] 手工验证文档 DDL 可执行：从 `implementation-contract-v1.md` 抽取 SQL，在内存 SQLite 执行通过。

### Pre-M0 开工门禁任务

这些任务不是业务开发；它们是进入 M0 前必须完成的工程门禁。

- [x] 建立新源码骨架：`ink/src/ink/`、`ink/tests/`、`ink/sql/`、基础 `pyproject.toml`。
- [x] 从 `implementation-contract-v1.md` 抽取正式 `schema.sql` 到版本控制：`ink/sql/schema.sql`。
- [x] 添加 `test_schema_executes_all_ddl`：在内存 SQLite 开启 `PRAGMA foreign_keys=ON`，执行完整 schema，并断言表/索引/触发器/视图存在。
- [x] 添加 schema 元测试：禁止旧 jury role 唯一约束、禁止 runtime event 写入旧事件时间字段、禁止从 shot 表按 session 直查。
- [x] 添加 jury round schema 测试：基础轮允许 3 裁判；升级轮允许 `escalated_jury_count` 裁判；同轮同 slot/model 重复写入失败。
- [x] 添加 jury 自评阻断测试：`judge_model = writer_model` 时 DB trigger 必须拒绝写入，JOIN 审计查询结果为空。
- [x] 添加 orchestrator 入口签名 lint 的最小测试：shot 级 orchestrator 只能接收 `(shot_id, run_id)`；禁止 dataclass 作为入口参数。
- [x] 添加字段消费 lint 的最小测试：动态 dataclass 访问全局失败；全字段消费只在契约边界函数和显式标注函数失败。
- [x] 添加 resume SQL 契约测试：通过 `writing_runs.session_id` 定位 session 内 shot，不允许从 `writing_shots.session_id` 查询。
- [x] 把 Pre-M0 通过条件写入本地统一命令：`cd ink && python -m pytest`。

### M0 正式开发任务

Pre-M0 全部通过后才开始以下任务。

- [x] 落地 40 张生产表、1 个 `v_current_text` 视图、2 个关键 trigger、全部索引和 FK。
- [x] 实现 DB 连接与迁移入口，默认开启 `PRAGMA foreign_keys=ON`，业务时间统一 `now_utc_iso()`。
- [x] 实现 schema/dataclass 代码生成器，生成契约 DTO、项目配置 DTO、质量报告 DTO。
- [x] 实现 `ProjectConfigValidator`：模型池唯一性、非空字符串、writer/jury 隔离、容量下限、质量阈值底线。
- [x] 实现 `TextRepository` 最小闭环：`read_current_text`、`write_revision`、`is_hard_sealed`，并阻断外部直接访问 `writing_shot_revisions`。
- [x] 实现状态机更新入口，阻断非 `state_machine` 直接更新 `writing_shots.status`。
- [x] 实现 `LLMGateway` 空壳与 mock provider，阻断业务代码直连供应商 SDK，并写入 AI 调用审计表。
- [x] 接入字段消费 lint、SQL 访问 lint、状态更新 lint、LLM 访问 lint。
- [x] 建立 `invariant-traceability.md` 到测试文件的追踪检查，禁止里程碑只写占位测试。

### M1 核心机制任务

- [x] 实现 14 态状态机合法转移、终态阻断、CAS stale 更新阻断。
- [x] 实现 `SoftGateCounter`：`writing_soft_gate_counters` 作为 N 计数唯一权威源，支持 N=1/2/3 阈值映射。
- [x] 实现 `LLMCallBudget`：同类失败连续熔断、单类型预算、总调用预算耗尽转 `failed`。
- [x] 实现 `ResumeManager`：session 绑定恢复、14 态 resume 映射、`redo_in_progress` 分支、结构化 `resume_point` 校验。
- [x] 实现 `CheckpointManager`：payload checksum、损坏 checkpoint 回退、`CHECKPOINT_CORRUPTED` 事件、retention 清理。
- [x] 实现 `ResumeManager.execute_resume_action()` 可配置分发，并接入 M2 pre-drafting resume handlers。
- [x] 将 M1 核心不变量接入 `invariant-traceability.md` 追踪测试。
- [x] 实现 `SoftGateCounter` 与实际 soft gate orchestrator 的事务集成。
- [x] 实现 `LLMCallBudget` 与 `LLMGateway.call()` 的调用前后预算集成。
- [ ] 扩展 `ResumeManager.execute_resume_action()`，接入 M3-M6 drafting/gate/jury/polish/review/export handlers。

### M2 contract + outline baseline 任务

- [x] 扩展契约 DTO 生成器：覆盖 MetaContract / ShotContract / OutlineSpec / TaskCard / PromptSpec / DraftSpec / JuryInput 生产链。
- [x] 实现 `load_shot_contract(conn, shot_id, run_id)`：orchestrator 入口只用 id，从 DB 重新加载 shot contract 完整投影。
- [x] 实现 `TaskCardCompiler.write_task_card()`：拒绝半句 task card，二次编译旧行写 `superseded_at` 并新增当前行。
- [x] 实现 CJK bigram overlap drift 检测：`drift_score < outline_drift_threshold` 派生拒绝，不新增重复状态列。
- [x] 实现 `OutlineRepository`：落库大纲候选，PK 选优时保证同一 shot contract 仅一个 `is_winner=1`。
- [x] 实现 `OutlineOrchestrator.evaluate_and_select()`：按项目阈值生成合格大纲、保留低 drift 候选证据、选 winner 并推进到 `outline_confirmed`。
- [x] 实现 `PromptSnapshotCompiler`：prompt snapshot 二次编译旧行打 `superseded_at`，新行成为当前版本。
- [x] 将 M2 的 `INV-PROMPT-001`、`INV-OUTLINE-001`、`INV-OUTLINE-002` 接入 invariant 追踪测试。
- [x] 将 M2 outline/task card/prompt 编译接入 `PreDraftingOrchestrator` 与 resume 重跑分支。

### M3 writer baseline 任务

- [x] 实现 `writers/model_pool.py`：从 `writing_projects.writer_model_pool` 读取写手模型池，并按候选数量轮换选择模型。
- [x] 实现 `WriteOrchestrator.produce_drafts()`：shot 级入口只用 `(shot_id, run_id)` 重新加载 contract/task card/prompt。
- [x] 实现同 persona + 同 prompt + 换模型产 X 篇候选，并在完成后推进 `drafting -> hard_gate1`。
- [x] 实现 creative shot 的 `draft_count + creative_shot_extra` 候选产稿。
- [x] 实现 deviant 独立产 1 篇：`is_deviant=1`，使用 `relaxed_soft=1` prompt snapshot。
- [x] 实现 LLM provider 失败时 local fallback：落 `degraded=1`、`failure_category`，供 M4 jury 排除。
- [x] 实现 N=2 局部重写产 >= `redo_candidate_count` 篇，使用 `retry_count>0` 并保持 `winner_selected + redo_in_progress=1`。
- [x] 将 M3 `rerun_drafting` / `rerun_soft_gate_redo_drafting` handlers 接入 `ResumeManager.execute_resume_action()`。
- [x] 在 M4 jury 中将 N=2 redo 候选与原候选池合并评分，并处理翻盘事务。
- [x] 将 normal/deviant prompt context snapshot 写入 `writing_context_snapshots`，记录缺失/裁剪原因。

### M4 review baseline 任务

- [x] 实现 `HardGateOrchestrator.run_both_gates()`：`hard_gate1 -> hard_gate2 -> jury_scoring`，并落 `writing_draft_eligibility`。
- [x] hard gate baseline 阻断 `degraded=1` 候选进入正式 jury 候选池。
- [x] 实现 `JuryOrchestrator.score_and_select_winner()`：基础轮 3 裁判、每裁判 12 维全评分，raw scores 与 aggregate 分表落库。
- [x] jury dispatch 按 draft 排除该 draft 的 `writer_model`；DB trigger 与 JOIN 审计保持为空。
- [x] jury baseline 排除 `degraded` 与 `is_deviant` 正式候选；deviant 暂作为 M4 后续 creative boundary reference 输入。
- [x] 通过 `writing_jury_aggregates.is_winner` 唯一索引保证每 shot 唯一 winner，并推进 `jury_scoring -> winner_selected`。
- [x] 实现 `final_score < shot_quality_floor` 不得 winner：低分 aggregate 可审计落库，但不推进 `winner_selected`。
- [x] 实现 dimension_floor / judge_disagreement 失败分支：aggregate 记录失败原因，不选 winner。
- [x] 实现 quality floor 失败后的补写触发与自动重试策略：关闭自动重试时转 `failed`，开启时补写 retry 候选并重评。
- [x] 实现 deviant_reference 注入 jury aggregate 审计输入，且不建立独立 creative_jury。
- [x] 实现 polish_revision baseline：winner 进入 polish、写正文 revision、生成 polish draft，并回到 `hard_gate1` 重新验证。
- [x] 实现 polish 后重新过 hard gates + quality floor 通过才允许 `soft_sealed`。
- [x] 实现 polish smart-model-required 不可降级阻断：smart 不可用时停在 `polish_revision`，不写 revision。

---

## 决策记录

| 问题 | 决策 | 决策人 | 决策日期 |
|------|------|--------|----------|
| D1 | DB 底线 + `ProjectConfigValidator` 完整模型池校验；默认两池无交集，重叠时按 draft 排除后仍需 3 个 jury model | Codex | 2026-07-04 |
| D2 | checkpoint `shot_id` 允许 NULL；非 NULL 时 FK + `LIKE '%@%'` | Codex | 2026-07-04 |
| D3 | dispatch 动态排除 + DB trigger 阻止自评 + JOIN 审计测试 | Codex | 2026-07-04 |
| D4 | 仅 `TextRepository` 硬封版事务设置 `is_current`；partial unique index 保证每 shot 最多一个 current | Codex | 2026-07-04 |
| D5 | UTC ISO 8601 `YYYY-MM-DDTHH:MM:SS.sssZ`，统一 `now_utc_iso()` 写入 | Codex | 2026-07-04 |
| E1 | `ProjectConfig = WritingProject + MetaContract + ChapterSpecs`；运营参数只在 `writing_projects` | Codex | 2026-07-04 |
| E2 | shot 级 orchestrator 入口只收 `(shot_id, run_id)`，session 从 DB 反查 | Codex | 2026-07-04 |
| E3 | `TextRepository` 只公开 `read_current_text` / `write_revision` / `is_hard_sealed` | Codex | 2026-07-04 |
| E4 | 统一 `errors.py`：State/Concurrency/Quality/Data/Config/LLM 六类错误 | Codex | 2026-07-04 |
| F1 | unit/integration/e2e 分层；真实 LLM 不进默认 CI | Codex | 2026-07-04 |
| F2 | builder/factory fixture + `(call_type, model, shot_id, attempt)` mock LLM | Codex | 2026-07-04 |
| F3 | CI 只做 mock 性能；真实 LLM 成本/耗时进 M6 验收记录 | Codex | 2026-07-04 |
| F4 | 先做 SQL/动态 SQL/正文隔离/SDK 直连安全；M6 加 import/export/prompt 泄漏测试 | Codex | 2026-07-04 |

---

## 下一步

1. 先执行“开发任务队列 / Pre-M0 开工门禁任务”，并保证本地/CI 一键通过。
2. Pre-M0 通过后开始 M0 正式开发：schema、代码生成器、repository、状态机、LLMGateway、lint 与 invariant 测试。
3. 任一 Pre-M0 任务失败时，不进入 M0；技术小问题直接修，战略口径变化必须回到本文和正式设计文档同步更新。
