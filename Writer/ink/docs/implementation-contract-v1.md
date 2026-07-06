# 实现契约 v1 — dataclass / DB / 模块接口

> **状态**：v1（2026-07-03，评审修订），对应 `design-v2.md`
> **定位**：从 0 构建的完整生产技术契约。不沿用旧系统 schema，重新设计 40 张生产表。
> **评审修订**：jury 方案 B（3 裁判全评 12 维）、契约核心字段拆 5 张结构化表、resume 语义补齐、字段消费 lint 改访问器 API + AST、物理隔离加 DB VIEW + sqlparse、AI 调用审计、人类决策、导入账本、checkpoint 与契约条款审计。

---

## 1. 代码生成的 dataclass 链

### 1.1 生成方式

契约传递链的 7 个 dataclass 用 **pydantic schema 定义 → 代码生成**，非手写。

- **schema 源**：`ink/src/ink/contract/schemas/*.py`（pydantic v2 BaseModel）
- **生成目标**：`ink/src/ink/contract/generated/*.py`（`@dataclass(frozen=True)`，勿手改）
- **生成命令**：`python -m ink.codegen.generate`（CI 强制运行，schema 变更必须重新生成）
- **访问器生成**：生成器为每个 dataclass 产出 `unpack()` 方法，返回所有字段的解构元组（供消费端 `must_land, anti_write, scene = shot_contract.unpack()` 使用）
- **字段消费 lint**：`python -m ink.codegen.field_usage_lint`（CI 强制运行，详见 §1.4）
- **SQL 访问 lint**：`python -m ink.codegen.sql_access_lint`（CI 强制运行，详见 §3.2）

### 1.2 pydantic schema 定义（核心字段）

#### MetaContract（元契约，全书级）

```python
# contract/schemas/meta_contract.py
from pydantic import BaseModel
from typing import Literal

class ProjectIdentity(BaseModel):
    code: str                    # 项目代号
    title: str
    genre: Literal["悬疑", "都市", "奇幻", "科幻", "历史", "其他"]
    target_chapters: int
    target_words_per_chapter: int

class NarrativeVoice(BaseModel):
    pov: Literal["第一人称", "第三人称限知", "第三人称全知", "多视角"]
    tense: Literal["过去时", "现在时"]
    register: Literal["口语", "书面", "混合"]

class HardBoundaries(BaseModel):
    forbidden_facts: tuple[str, ...]      # 禁用事实（不可违背）
    forbidden_words: tuple[str, ...]      # 禁用词
    pov_only: tuple[str, ...]             # 仅允许的 POV 角色
    capacity_floor: int                   # 容量下限（UTF-8 bytes）

class StyleLocks(BaseModel):
    sentence_length_max: int
    paragraph_length_max: int
    repetition_rate_max: float
    register_lock: str

class WorldKnowledge(BaseModel):
    canon_facts: tuple[str, ...]          # 已确立的设定事实
    character_bible: tuple[str, ...]      # 角色档案
    geography: tuple[str, ...]
    timeline: tuple[str, ...]

class MotifSystem(BaseModel):
    motifs: tuple[str, ...]               # 母题列表
    target_density_per_chapter: float     # 每章目标密度

class CreativeZones(BaseModel):
    zones: tuple[str, ...]               # 允许创意偏离的场景/shot 类型

# QualityBar 已迁移至 writing_projects 表作为独立字段（shot_quality_floor、dimension_floor、
# chapter_quality_floor、book_quality_floor、judge_disagreement_max、reader_pull_floor、
# blind_review_min_passes），支持 DB 层约束和索引。MetaContract 应用层直接从 writing_projects
# 读取这些字段，不再需要独立的 QualityBar 类。

class StyleQualityProfile(BaseModel):
    target_readers: tuple[str, ...]       # 目标读者
    style_benchmarks: tuple[str, ...]     # 文体标杆/参照，不复制文本
    positive_examples: tuple[str, ...]    # 正例片段或摘要
    negative_examples: tuple[str, ...]    # 反例片段或摘要
    banned_cliches: tuple[str, ...]       # 禁止俗套/水文模式
    language_density_target: str
    dialogue_density_target: str
    suspense_density_target: str
    reader_pull_target: str               # 读者为什么必须继续读
    blind_review_policy: str              # 盲评对象、次数、通过口径
    protected_roughness: tuple[str, ...]   # 必须保护的粗粝/留白/声线/节奏特征
    voice_anti_samples: tuple[str, ...]    # 反面声音样本摘要，防角色同质化

class QualityReportItem(BaseModel):
    evidence_class: Literal["ES", "SEMI_ES", "NES"]
    defect_class: Literal["destructive", "productive", "neutral"]
    scope: Literal["shot", "chapter", "book"]
    dimension: str
    message: str
    evidence_ref: str                     # 段落/句子/contract_clause/fact_anchor 引用
    fix_instruction: str                  # destructive 必填；productive 说明保护原因
    confidence: float

class QualityReport(BaseModel):
    quality_gate_passed: bool
    final_score: int
    would_continue_reading_score: int
    blind_review_passed: bool
    destructive_count: int
    productive_deviations: tuple[QualityReportItem, ...]
    neutral_issues: tuple[QualityReportItem, ...]
    blocking_items: tuple[QualityReportItem, ...]
    smart_model_required: bool            # 文学体验/返工指导/盲评排序不可降级时为 true
    model_tier_used: Literal["rule", "fast", "balanced", "smart", "human"]

class MetaContract(BaseModel):
    identity: ProjectIdentity
    narrative_voice: NarrativeVoice
    hard_boundaries: HardBoundaries
    style_locks: StyleLocks
    world_knowledge: WorldKnowledge
    motif_system: MotifSystem
    creative_zones: CreativeZones
    # quality_bar 已迁移至 writing_projects 表（见 §2.1），通过 MetaContract 的
    # 应用层逻辑从 writing_projects 读取，不再作为 JSON 字段存储
    style_quality_profile: StyleQualityProfile  # 项目级"什么叫好"的锚点
```

#### ProjectConfig（项目完整配置投影）

运营参数只在 `writing_projects` 表；`MetaContract` 不复制这些字段。应用层通过 `ProjectConfig` 组合读取：

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class WritingProject:
    project_id: int
    code: str
    title: str
    draft_count: int
    creative_shot_extra: int
    writer_model_pool: tuple[str, ...]
    jury_model_pool: tuple[str, ...]
    jury_model_pool_min: int
    min_eligible_outlines: int
    min_eligible_candidates: int
    redo_candidate_count: int
    escalated_jury_count: int
    shot_quality_floor: int
    dimension_floor: int
    chapter_quality_floor: int
    book_quality_floor: int
    judge_disagreement_max: int
    reader_pull_floor: int
    blind_review_min_passes: int
    max_calls_per_shot: int
    max_total_llm_calls: int
    consecutive_failure_circuit_break: int
    soft_gate_redo_n: int
    soft_gate_fail_n: int
    auto_retry_on_hard_failure: bool
    max_retries_per_gate: int
    retry_strategy: Literal["change_model", "adjust_intensity", "relax_soft"]

@dataclass(frozen=True)
class ProjectConfig:
    project: WritingProject
    meta_contract: MetaContract
    chapter_specs: tuple["ChapterSpec", ...]
```

`ProjectConfigValidator` 负责 DB CHECK 难以表达的配置校验：
- `writer_model_pool` / `jury_model_pool` 必须是非空唯一字符串数组。
- 默认要求两池无交集。
- 如果允许模型池重叠，排除当前 draft 的 `writer_model` 后仍必须有至少 3 个 jury model。
- `draft_count <= len(writer_model_pool)`；`jury_model_pool_min >= 3`。
- `StyleQualityProfile` 必须含 `target_readers`、`reader_pull_target`、`blind_review_policy`、`protected_roughness`、`voice_anti_samples`。

#### ShotContract（shot 契约，核心字段对应 5 张结构化表）

```python
class MustLand(BaseModel):
    events: tuple[str, ...]               # 必须落地的事件
    beats: tuple[str, ...]                # beat 顺序
    information_releases: tuple[str, ...] # 必须释放的信息

class AntiWrite(BaseModel):
    forbidden_facts: tuple[str, ...]      # 本 shot 禁用事实
    forbidden_words: tuple[str, ...]
    pov_only: tuple[str, ...]             # 本 shot POV 限制

class SceneContract(BaseModel):
    location: str
    time_of_day: str
    characters_present: tuple[str, ...]
    character_positions: dict[str, str]   # 角色 → 位置/状态

class PersonaAssignment(BaseModel):
    persona: Literal["意象师", "节奏师", "对话师", "结构师", "悬疑官"]
    intensity: dict[str, int]             # 5 维强度配比 {"画面":3,"节奏":3,"对话":2,"结构":3,"悬疑":9}
    is_creative_shot: bool
    is_suspense_shot: bool                # 悬疑/压迫 shot 标记

class SoftConstraints(BaseModel):
    relaxable_rules: tuple[str, ...]      # 可酌情偏离的软约束
    deviation_budget: float               # 允许偏离幅度

class ShotContract(BaseModel):
    shot_id: str                          # {logical}@{run} 隔离
    chapter_id: int
    meta_contract_id: int
    must_land: MustLand                   # 从 writing_shot_must_land 表加载
    anti_write: AntiWrite                 # 从 writing_shot_anti_write 表加载
    scene_contract: SceneContract         # 从 writing_shot_scene_contract 表加载
    persona_assignment: PersonaAssignment # 从 writing_shot_persona_assignment 表加载
    soft_constraints: SoftConstraints     # 从 writing_shot_soft_constraints 表加载
    status: Literal["draft", "confirmed", "locked"]
```

#### OutlineSpec / TaskCard / PromptSpec / DraftSpec

```python
class OutlineSpec(BaseModel):
    outline_id: int
    shot_contract_id: int
    evaluated_outline_text: str
    drift_score: float
    is_winner: bool                       # 大纲 PK 选优（drift_rejected 派生自 drift_score < writing_projects.outline_drift_threshold，不存列）

class TaskCard(BaseModel):
    task_card_id: int
    shot_contract_id: int
    compiled_instructions: str           # 编译后的 prompt 指令
    superseded_at: str | None            # B88 supersede 机制

class PromptSpec(BaseModel):
    prompt_id: int
    task_card_id: int
    persona: str
    full_prompt_text: str
    relaxed_soft: bool                   # 仅 deviant 生效
    superseded_at: str | None

class DraftSpec(BaseModel):
    draft_id: int
    shot_id: str
    prompt_id: int
    persona: str
    writer_model: str                    # 写手模型（换模型获多样性）
    text: str
    degraded: bool                       # 铁律 3
    failure_category: str | None
    retry_count: int
    is_deviant: bool                     # deviant 沙盒稿
    byte_count: int
    source_revision_id: int | None       # B92 stale 检测：若该 draft 被封版，指向 revisions.revision_id
```

### 1.3 JuryInput

```python
class JuryInput(BaseModel):
    draft: DraftSpec
    shot_contract: ShotContract          # 评分对标基准（5 维强度配比作加权权重）
    eligibility_first_gate: bool         # 第一道硬门槛结果
    eligibility_second_gate: bool        # 第二道硬门槛结果
    deviant_reference: DraftSpec | None  # deviant 稿作创意边界参考（通过第一道门槛的 deviant 才注入；失败稿不注入）
```

### 1.4 字段消费 lint（铁律 1 的强制机制，评审 #2 修订）

**脚本**：`ink/src/ink/codegen/field_usage_lint.py`

**机制**（两道防线）：

**防线 1 — 访问器 API 强制**：
- 生成器为每个 dataclass 产出 `unpack()` 方法
- 消费端**必须**用 `unpack()` 解构或具名属性访问（`ast.Attribute` 节点）
- **禁止**动态访问：lint 扫描 AST，遇 `getattr(x, ...)` / `vars(x)` / `x.__dict__` / `dataclasses.asdict(x)` / `**x` 一律报错

**防线 2 — 字段消费可达性扫描**：
1. 动态访问禁令扫描所有 import 了 generated dataclass 的模块。
2. “全字段消费”只扫描契约边界函数：`contract_compiler/*`、`prompt_compiler/*`、gate input builder、jury input builder、shot 级 orchestrator 入口，以及显式标注 `@requires_full_field_consumption` 的函数。
3. 对这些边界函数签名里的上游 dataclass 类型，提取其所有字段名。
4. 断言每个字段名被 `ast.Attribute` 节点引用（`x.field` 形式），**不再用"字段名出现在源码字符串中"的词法匹配**（治误报：字段名出现在注释/f-string/log 文本里不算消费；治漏报：动态访问会被防线 1 拦截）。
5. 未引用 = 报错，列出 `函数名 → 未消费字段名`。

普通 helper 不应直接接收 generated dataclass；如果只需要部分字段，调用方先转换为收窄 DTO 或传显式字段参数。这样 lint 检查的是契约边界的完整消费，不逼迫内部函数写 `_ = field` 式假消费。

**示例**：
```python
# 正确：用 unpack() 显式解构所有字段
def compile_prompt(prompt_spec: PromptSpec) -> str:
    task_card, persona, full_prompt_text, relaxed_soft, _ = prompt_spec.unpack()
    aw = task_card.shot_contract.anti_write
    _ = aw.forbidden_facts  # 显式引用，ast.Attribute 节点
    _ = aw.forbidden_words
    _ = aw.pov_only
    return ...

# 错误：forbidden_facts 未被消费
def compile_prompt(prompt_spec: PromptSpec) -> str:
    aw = prompt_spec.task_card.shot_contract.anti_write
    if aw.pov_only or aw.forbidden_words:   # 只用了 2 个字段
        ...
    # aw.forbidden_facts 无 ast.Attribute 引用 → lint 报错
    return ...

# 错误：动态访问，防线 1 拦截
def compile_prompt(prompt_spec: PromptSpec) -> str:
    for k, v in vars(prompt_spec).items():  # vars() 禁止
        ...
```

**CI 集成**：pre-commit + CI 强制运行，未过 = 构建失败。

### 1.5 参数化原则（运营参数 vs 架构不变量）

**原则**：凡是"改变后系统行为变化但正确性不变"的值，都应该是 `writing_projects` 表中的运营参数，运行时可调，不改代码。"改变后系统正确性也变了"的值（状态机转移矩阵、铁律、DB CHECK 绝对底线）保持硬编码。

**运营参数**（全部在 `writing_projects` 表，`init` 时设定，之后可 `UPDATE`）：

| 参数 | 默认值 | 说明 | 来源 |
|------|--------|------|------|
| `draft_count` | 3 | X 全局候选稿数 | 已有 |
| `creative_shot_extra` | 3 | 创意 shot 额外候选数 | 已有 |
| `chapter_rolling_check_interval` | 5 | 篇级检测间隔（每 N 章跑一次） | 已有 |
| `writer_model_pool` | — | 写手模型池 | 已有 |
| `jury_model_pool` | — | 裁判模型池 | 已有 |
| `shot_quality_floor` | 80 | winner 最低 final_score | 已有，QualityBar |
| `dimension_floor` | 65 | 12 维任一核心维度最低分 | 已有，QualityBar |
| `chapter_quality_floor` | 75 | 章级 7 维最低分 | 已有，QualityBar |
| `book_quality_floor` | 75 | 篇级 6 维最低分 | 已有，QualityBar |
| `judge_disagreement_max` | 25 | 同维裁判最高-最低最大分差 | 已有，QualityBar |
| `reader_pull_floor` | 75 | would_continue_reading 最低分 | 已有，QualityBar |
| `blind_review_min_passes` | 2 | 盲评最少通过数 | 已有，QualityBar |
| `max_calls_per_shot` | 8 | 单 shot 单类型 LLM 调用上限（第一层熔断） | **新增**，原硬编码 |
| `max_total_llm_calls` | 40 | 单 shot 全生命周期 LLM 调用总上限（第二层熔断） | **新增**，原硬编码 |
| `consecutive_failure_circuit_break` | 3 | 同类失败连续 N 次触发熔断 | **新增**，原硬编码 |
| `soft_gate_redo_n` | 2 | soft gate 连续失败 N 次触发局部重写 | **新增**，原硬编码 |
| `soft_gate_fail_n` | 3 | soft gate 连续失败 N 次，质量类转 failed | **新增**，原硬编码 |
| `outline_drift_threshold` | 0.20 | 大纲 CJK bigram overlap 低于此值拒绝 | **新增**，原硬编码于 B77 |
| `capacity_floor_titled_shot` | 1200 | titled shot 容量下限（UTF-8 bytes） | **新增**，原硬编码于 B93 |
| `capacity_floor_chapter_end` | 1500 | 章末 shot 容量下限（UTF-8 bytes） | **新增**，原硬编码于 B93 |
| `prompt_archive_size_bytes` | 65536 | prompt 超此大小归档到独立文件 | **新增**，原硬编码 64KB |
| `checkpoint_max_retention` | 3 | checkpoint 保留最近几个稳定点 | **新增**，原硬编码 |
| `scene_fingerprint_min_diversity` | 3 | L3 场景指纹多样性最低要求 | **新增**，原硬编码 |
| `suspense_shot_min_intensity` | 5 | 悬疑 shot 悬疑维度最低强度 | **新增**，原硬编码 |
| `auto_retry_on_hard_failure` | TRUE | hard gate / quality floor 失败后是否自动重试（A'+A'' 机制） | **新增** |
| `max_retries_per_gate` | 2 | 每层 gate 自动重试最大次数 | **新增** |
| `retry_strategy` | 'change_model' | 重试策略：change_model / adjust_intensity / relax_soft | **新增** |

**架构不变量**（硬编码，不可参数化）：

| 不变量 | 值 | 为什么不能参数化 |
|--------|---|----------------|
| shot_status 合法转移矩阵 | 14 态穷举 | 改变 = 改变状态机语义 |
| `is_winner=1 → quality_gate_passed=1` | DB CHECK | 改变 = 允许质量不达标 winner |
| `hard_quality_override=0` | DB CHECK | 改变 = 允许人工覆盖硬失败（见设计讨论） |
| 信息差 6 态转移合法性 | DB CHECK | 改变 = 改变信息差语义 |
| `v_current_text` 每 shot 恰一行 | DB VIEW | 改变 = 破坏正文唯一性 |
| text_repository 三重隔离 | 代码 + CI lint | 改变 = 破坏铁律 5 |
| 字段消费 AST lint | CI lint | 改变 = 破坏铁律 1 |
| 基础裁判数 = 3 | 设计常量 | 改变 = 改变基础评分算法；分歧升级裁判数由 `escalated_jury_count` 参数化 |
| 12 维评分 | 设计常量 | 改变 = 改变评分体系 |
| 5 persona | 设计常量 | 改变 = 改变产稿机制 |

**DB CHECK 绝对底线 vs 运营阈值**：

`jury_aggregates` 等表的 CHECK 约束（如 `final_score >= 80`）是**绝对底线**——任何项目的运营阈值不得低于此。运营阈值已拆为 `writing_projects` 表的独立字段（`shot_quality_floor`、`dimension_floor`、`chapter_quality_floor`、`book_quality_floor`、`judge_disagreement_max`、`reader_pull_floor`、`blind_review_min_passes`），并在 `writing_projects` 表级 CHECK 约束中保证运营阈值不低于 DB 绝对底线。应用层直接读取 `writing_projects` 表的运营阈值执行。这样既允许项目提高标准，又防止项目误设过低阈值导致质量失控。

---

## 2. DB schema（40 张生产表 DDL）

**时间字段约定**：所有 `created_at`、`updated_at`、`evaluated_at`、`started_at`、`finished_at`、`sealed_at` 等 `TEXT` 时间字段统一使用 UTC ISO 8601：`YYYY-MM-DDTHH:MM:SS.sssZ`。应用层只能通过 `now_utc_iso()` 写入业务时间；DDL 不依赖 SQLite 本地时间函数。

### 2.1 第 1 层：项目元数据（3 张）

```sql
-- 1. writing_projects
-- 运营参数全部在此表，运行时可调不改代码（见 §1.5 参数化原则）
CREATE TABLE writing_projects (
    project_id INTEGER PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    title TEXT NOT NULL,
    meta_contract_id INTEGER,                         -- 当前元契约指针；不做 FK，避免 projects/meta_contracts 循环级联

    -- ── 产稿参数 ──
    draft_count INTEGER NOT NULL DEFAULT 3,          -- X 全局候选稿数
    creative_shot_extra INTEGER NOT NULL DEFAULT 3,  -- 创意 shot 额外候选数
    writer_model_pool TEXT NOT NULL,                 -- JSON array
    jury_model_pool TEXT NOT NULL,                   -- JSON array
    jury_model_pool_min INTEGER NOT NULL DEFAULT 3,  -- 裁判模型池最少数量（DB CHECK 用）
    min_eligible_outlines INTEGER NOT NULL DEFAULT 2,  -- 大纲生成最少合格数
    min_eligible_candidates INTEGER NOT NULL DEFAULT 2,  -- jury 候选不足此数触发补写
    redo_candidate_count INTEGER NOT NULL DEFAULT 2,    -- N=2 局部重写时产几篇新候选
    escalated_jury_count INTEGER NOT NULL DEFAULT 5,    -- 裁判分歧超阈值时升级到几个裁判

    -- ── 熔断预算参数（原硬编码，现运营可调） ──
    max_calls_per_shot INTEGER NOT NULL DEFAULT 8,          -- 单 shot 单类型 LLM 调用上限
    max_total_llm_calls INTEGER NOT NULL DEFAULT 40,        -- 单 shot 全生命周期 LLM 调用总上限
    consecutive_failure_circuit_break INTEGER NOT NULL DEFAULT 3,  -- 同类失败连续 N 次熔断

    -- ── soft gate 升级阈值参数（原硬编码，现运营可调） ──
    soft_gate_redo_n INTEGER NOT NULL DEFAULT 2,            -- soft gate 连续失败 N 次触发局部重写
    soft_gate_fail_n INTEGER NOT NULL DEFAULT 3,            -- soft gate 连续失败 N 次，质量类转 failed

    -- ── 自动重试参数（A'+A'' 机制） ──
    auto_retry_on_hard_failure INTEGER NOT NULL DEFAULT 1 CHECK (auto_retry_on_hard_failure IN (0,1)),
    max_retries_per_gate INTEGER NOT NULL DEFAULT 2,        -- 每层 gate 自动重试最大次数
    retry_strategy TEXT NOT NULL DEFAULT 'change_model'
        CHECK (retry_strategy IN ('change_model','adjust_intensity','relax_soft')),

    -- ── 大纲与容量参数 ──
    outline_drift_threshold REAL NOT NULL DEFAULT 0.20,     -- 大纲 CJK bigram overlap 拒绝阈值
    capacity_floor_titled_shot INTEGER NOT NULL DEFAULT 1200,  -- titled shot 容量下限 UTF-8 bytes
    capacity_floor_chapter_end INTEGER NOT NULL DEFAULT 1500,  -- 章末 shot 容量下限 UTF-8 bytes

    -- ── 多样性与场景参数 ──
    scene_fingerprint_min_diversity INTEGER NOT NULL DEFAULT 3,  -- L3 场景指纹多样性最低要求
    suspense_shot_min_intensity INTEGER NOT NULL DEFAULT 5,      -- 悬疑 shot 悬疑维度最低强度

    -- ── 归档与恢复参数 ──
    prompt_archive_size_bytes INTEGER NOT NULL DEFAULT 65536,  -- prompt 超此大小归档到独立文件
    checkpoint_max_retention INTEGER NOT NULL DEFAULT 3,       -- checkpoint 保留最近几个稳定点

    -- ── 质量阈值参数（原 quality_bar JSON，拆为独立字段以支持 DB 层约束） ──
    shot_quality_floor INTEGER NOT NULL DEFAULT 80,           -- winner 最低 final_score，DB 绝对底线 80
    dimension_floor INTEGER NOT NULL DEFAULT 65,              -- 12 维任一核心维度最低分，DB 绝对底线 65
    chapter_quality_floor INTEGER NOT NULL DEFAULT 75,        -- 章级 7 维最低分，DB 绝对底线 75
    book_quality_floor INTEGER NOT NULL DEFAULT 75,           -- 篇级 6 维最低分，DB 绝对底线 75
    judge_disagreement_max INTEGER NOT NULL DEFAULT 25,       -- 同维 3 裁判最高-最低最大分差，DB 绝对底线 25
    reader_pull_floor INTEGER NOT NULL DEFAULT 75,            -- would_continue_reading 最低分
    blind_review_min_passes INTEGER NOT NULL DEFAULT 2,       -- 盲评最少通过数

    -- ── 篇级检测参数 ──
    chapter_rolling_check_interval INTEGER NOT NULL DEFAULT 5,

    created_at TEXT NOT NULL,

    CHECK (shot_quality_floor >= 80),                          -- 运营阈值不得低于 DB 绝对底线
    CHECK (dimension_floor >= 65),
    CHECK (chapter_quality_floor >= 75),
    CHECK (book_quality_floor >= 75),
    CHECK (judge_disagreement_max <= 25),                     -- 分差阈值不得高于绝对底线（越小越严格）
    CHECK (blind_review_min_passes BETWEEN 1 AND 3),

    -- CHECK 约束：DB 只做 JSON/长度底线；元素类型、去重、两池交集由 ProjectConfigValidator 校验
    CHECK (json_valid(writer_model_pool) AND json_type(writer_model_pool) = 'array'),
    CHECK (json_valid(jury_model_pool) AND json_type(jury_model_pool) = 'array'),
    CHECK (json_array_length(writer_model_pool) >= draft_count),
    CHECK (json_array_length(jury_model_pool) >= jury_model_pool_min),
    CHECK (jury_model_pool_min >= 3)
);

-- 2. writing_meta_contracts
CREATE TABLE writing_meta_contracts (
    meta_contract_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    identity TEXT NOT NULL,                          -- JSON
    narrative_voice TEXT NOT NULL,                   -- JSON
    hard_boundaries TEXT NOT NULL,                   -- JSON
    style_locks TEXT NOT NULL,                       -- JSON
    world_knowledge TEXT NOT NULL,                   -- JSON
    motif_system TEXT NOT NULL,                      -- JSON
    creative_zones TEXT NOT NULL,                    -- JSON
    -- quality_bar 已迁移至 writing_projects 表作为独立字段（支持 DB 层约束和索引）
    style_quality_profile TEXT NOT NULL,             -- JSON：目标读者、文体标杆、正/反例、禁用俗套、密度目标
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','confirmed','locked')),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);

-- 3. writing_chapter_specs
CREATE TABLE writing_chapter_specs (
    chapter_spec_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    rhythm_curve_target TEXT NOT NULL,               -- JSON 节奏曲线目标
    hook_target TEXT,                                -- 章末钩子目标
    motif_density_target REAL,
    injected_issues TEXT,                            -- 篇级检测/soft gate 注入的问题（评审 #18/#36）
    UNIQUE (project_id, chapter_id),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
```

### 2.2 第 2 层：契约链（9 张） — shot 契约核心字段拆 5 张结构化表（评审 #1 critical 修复）

```sql
-- 4. writing_outline_specs
CREATE TABLE writing_outline_specs (
    outline_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER,
    evaluated_outline_text TEXT NOT NULL,
    drift_score REAL NOT NULL,
    -- drift_rejected 派生自 drift_score < writing_projects.outline_drift_threshold，不再存列（评审 #23："一个信号只存一处"）
    is_winner INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);
-- 评审 #30：is_winner 唯一约束，大纲 PK 只能选一个 winner
CREATE UNIQUE INDEX idx_outline_winner ON writing_outline_specs(shot_contract_id) WHERE is_winner = 1;

-- 5. writing_shot_contracts（契约主表，不存核心字段 blob）
CREATE TABLE writing_shot_contracts (
    shot_contract_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    run_id INTEGER NOT NULL,
    logical_shot_id TEXT NOT NULL,
    -- 核心字段拆到 5 张子表（下方 6-10），本表只存状态与指针
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','confirmed','locked')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,                        -- 评审 #28：状态机变更时间可追踪
    UNIQUE (project_id, chapter_id, logical_shot_id, run_id),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE
);

-- 6. writing_shot_must_land（必须落地，结构化）
CREATE TABLE writing_shot_must_land (
    must_land_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL UNIQUE,        -- 1:1
    events TEXT NOT NULL,                            -- JSON array（事件列表，结构化存储非 blob 单列）
    beats TEXT NOT NULL,                             -- JSON array（beat 顺序）
    information_releases TEXT NOT NULL,              -- JSON array
    CHECK (json_array_length(events) > 0),
    CHECK (json_array_length(beats) > 0),
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 7. writing_shot_anti_write（禁区，结构化）
CREATE TABLE writing_shot_anti_write (
    anti_write_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL UNIQUE,        -- 1:1
    forbidden_facts TEXT NOT NULL,                   -- JSON array
    forbidden_words TEXT NOT NULL,                   -- JSON array
    pov_only TEXT NOT NULL,                          -- JSON array
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 8. writing_shot_scene_contract（场景契约，结构化）
CREATE TABLE writing_shot_scene_contract (
    scene_contract_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL UNIQUE,        -- 1:1
    location TEXT NOT NULL,
    time_of_day TEXT NOT NULL,
    characters_present TEXT NOT NULL,                -- JSON array
    character_positions TEXT NOT NULL,               -- JSON object {角色: 位置}
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 9. writing_shot_persona_assignment（persona 指定，结构化）
CREATE TABLE writing_shot_persona_assignment (
    persona_assignment_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL UNIQUE,        -- 1:1
    persona TEXT NOT NULL CHECK (persona IN ('意象师','节奏师','对话师','结构师','悬疑官')),
    intensity TEXT NOT NULL,                         -- JSON {画面,节奏,对话,结构,悬疑} 各 0-10
    is_creative_shot INTEGER NOT NULL DEFAULT 0 CHECK (is_creative_shot IN (0,1)),
    is_suspense_shot INTEGER NOT NULL DEFAULT 0 CHECK (is_suspense_shot IN (0,1)),
    -- 评审 medium 修订：5 维全补全非 NULL + 0-10 区间 CHECK（原只查画面/悬疑非 NULL）
    CHECK (json_extract(intensity, '$.画面') IS NOT NULL AND json_extract(intensity, '$.画面') BETWEEN 0 AND 10),
    CHECK (json_extract(intensity, '$.节奏') IS NOT NULL AND json_extract(intensity, '$.节奏') BETWEEN 0 AND 10),
    CHECK (json_extract(intensity, '$.对话') IS NOT NULL AND json_extract(intensity, '$.对话') BETWEEN 0 AND 10),
    CHECK (json_extract(intensity, '$.结构') IS NOT NULL AND json_extract(intensity, '$.结构') BETWEEN 0 AND 10),
    CHECK (json_extract(intensity, '$.悬疑') IS NOT NULL AND json_extract(intensity, '$.悬疑') BETWEEN 0 AND 10),
    -- is_suspense_shot=1 要求悬疑强度 >= writing_projects.suspense_shot_min_intensity（默认 5，运营可调）
    -- 注意：此 CHECK 为绝对底线 5，实际阈值由应用层从 writing_projects 读取后执行
    CHECK (is_suspense_shot = 0 OR json_extract(intensity, '$.悬疑') >= 5),
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 10. writing_shot_soft_constraints（软约束，结构化）
CREATE TABLE writing_shot_soft_constraints (
    soft_constraints_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL UNIQUE,        -- 1:1
    relaxable_rules TEXT NOT NULL,                   -- JSON array
    deviation_budget REAL NOT NULL,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 11. writing_shot_task_cards
CREATE TABLE writing_shot_task_cards (
    task_card_id INTEGER PRIMARY KEY,
    shot_contract_id INTEGER NOT NULL,
    compiled_instructions TEXT NOT NULL,
    superseded_at TEXT,                              -- B88 supersede
    created_at TEXT NOT NULL,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);

-- 12. writing_prompt_snapshots
CREATE TABLE writing_prompt_snapshots (
    prompt_id INTEGER PRIMARY KEY,
    task_card_id INTEGER NOT NULL,
    persona TEXT NOT NULL,
    full_prompt_text TEXT NOT NULL,
    prompt_size_bytes INTEGER NOT NULL,              -- 评审 #31：超 writing_projects.prompt_archive_size_bytes 时迁到独立文件
    relaxed_soft INTEGER NOT NULL DEFAULT 0,         -- 仅 deviant
    superseded_at TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (task_card_id) REFERENCES writing_shot_task_cards(task_card_id) ON DELETE CASCADE
);
-- prompt 归档策略：prompt_size_bytes > writing_projects.prompt_archive_size_bytes 时 full_prompt_text 迁到 prompts/{prompt_id}.txt，列存路径
-- supersede 历史保留：旧 prompt 不删，superseded_at 标记，供审计回溯
```

### 2.3 第 3 层：执行与产出（6 张）

```sql
-- 13. writing_shots
CREATE TABLE writing_shots (
    shot_id TEXT PRIMARY KEY,                        -- {logical}@{run} 隔离
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    shot_contract_id INTEGER,
    run_id INTEGER NOT NULL,
    logical_shot_id TEXT NOT NULL,                   -- 评审 #6：N 计数绑 logical_shot_id（跨 run 累积）
    status TEXT NOT NULL CHECK (status IN (
        'pending','outline_draft','outline_confirmed',
        'task_card_compiled','prompt_compiled',
        'drafting','hard_gate1','hard_gate2',
        'jury_scoring','winner_selected','polish_revision',
        'soft_sealed','hard_sealed','failed'
    )),                                             -- 14 态，resume 映射见 §3.6
    retry_count INTEGER NOT NULL DEFAULT 0,
    soft_fail_counts_snapshot TEXT NOT NULL DEFAULT '{}', -- JSON 审计快照；业务不得读取，权威源是 writing_soft_gate_counters
    redo_in_progress INTEGER NOT NULL DEFAULT 0,     -- 评审 #6：N=2 局部重写子状态标记
    resume_point TEXT,                               -- 评审 #17：结构化 JSON {phase, chapter_id, dimension_index}
    llm_call_count INTEGER NOT NULL DEFAULT 0,       -- 评审 P0-5：shot 内 LLM 总调用计数（上限 = writing_projects.max_total_llm_calls）
    llm_call_breakdown TEXT NOT NULL DEFAULT '{}',   -- 评审 P0-5：JSON {call_type: count}，单类型上限 = writing_projects.max_calls_per_shot
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,                        -- 评审 #28：状态机变更时间
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id),
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE
);
CREATE INDEX idx_shots_logical ON writing_shots(logical_shot_id);
CREATE INDEX idx_shots_run ON writing_shots(run_id);

-- 14. writing_soft_gate_counters
-- 唯一权威源：每 (project_id, logical_shot_id, gate_name) 一行，N 计数原子累加。
-- writing_shots.soft_fail_counts_snapshot 仅为审计快照，业务读 N 必须查本表。
CREATE TABLE writing_soft_gate_counters (
    counter_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    logical_shot_id TEXT NOT NULL,                   -- 跨 run 累积（绑 logical 非 attempt）
    gate_name TEXT NOT NULL,
    n INTEGER NOT NULL DEFAULT 0 CHECK (n >= 0),
    last_incremented_at TEXT NOT NULL,
    last_level INTEGER NOT NULL DEFAULT 0 CHECK (last_level IN (0,1,2,3)),  -- 0=未触发
    UNIQUE (project_id, logical_shot_id, gate_name),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX idx_soft_gate_logical ON writing_soft_gate_counters(project_id, logical_shot_id);

-- 15. writing_runs
CREATE TABLE writing_runs (
    run_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    session_id INTEGER NOT NULL,
    run_attempt INTEGER NOT NULL,                    -- 同 session 的第 N 次尝试
    started_at TEXT NOT NULL,
    finished_at TEXT,
    status TEXT NOT NULL CHECK (status IN ('running','completed','crashed','aborted')),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES writing_sessions(session_id) ON DELETE CASCADE
);

-- 16. writing_sessions
CREATE TABLE writing_sessions (
    session_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    started_at TEXT NOT NULL,
    crashed INTEGER NOT NULL DEFAULT 0,
    resume_point TEXT,                               -- 崩溃恢复点（结构化 JSON，见 §3.6）
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);

-- 17. writing_drafts
CREATE TABLE writing_drafts (
    draft_id INTEGER PRIMARY KEY,
    shot_id TEXT NOT NULL,
    prompt_id INTEGER NOT NULL,
    persona TEXT NOT NULL,
    writer_model TEXT NOT NULL,                      -- 换模型获多样性
    text TEXT NOT NULL,
    degraded INTEGER NOT NULL DEFAULT 0,             -- 铁律 3
    failure_category TEXT,
    retry_count INTEGER NOT NULL DEFAULT 0,
    is_deviant INTEGER NOT NULL DEFAULT 0,           -- deviant 沙盒稿
    byte_count INTEGER NOT NULL,
    source_revision_id INTEGER,                      -- 评审 #12/#21：B92 stale 检测，指向 revisions
    created_at TEXT NOT NULL,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (prompt_id) REFERENCES writing_prompt_snapshots(prompt_id) ON DELETE CASCADE,
    FOREIGN KEY (source_revision_id) REFERENCES writing_shot_revisions(revision_id)
);
CREATE INDEX idx_drafts_shot ON writing_drafts(shot_id);

-- 18. writing_shot_revisions（正文，物理隔离）
-- 只允许 core/text_repository 模块通过 Python import + DB VIEW 访问
CREATE TABLE writing_shot_revisions (
    revision_id INTEGER PRIMARY KEY,
    shot_id TEXT NOT NULL,
    run_id INTEGER NOT NULL,
    revision_sequence INTEGER NOT NULL,
    text TEXT NOT NULL,
    is_current INTEGER NOT NULL DEFAULT 0,           -- B19 封版规则
    sealed_at TEXT,                                  -- 硬封版时间
    sealed_by TEXT,                                  -- 'shot_soft' | 'chapter_hard'
    source_revision_id INTEGER,                      -- 评审 #12：跨 run stale 检测（B92），指向上游 revision
    created_at TEXT NOT NULL,
    UNIQUE (shot_id, revision_sequence),
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (source_revision_id) REFERENCES writing_shot_revisions(revision_id)
);
CREATE UNIQUE INDEX uq_revisions_one_current ON writing_shot_revisions(shot_id) WHERE is_current = 1;
CREATE INDEX idx_revisions_current ON writing_shot_revisions(shot_id, is_current) WHERE is_current = 1;
CREATE INDEX idx_revisions_seq ON writing_shot_revisions(shot_id, revision_sequence);

-- DB VIEW：封版逻辑封装，业务模块查 view 而非原表（评审 #3 修复）
-- 评审 P0-3 修订：原 WHERE is_current=1 OR revision_sequence=(MAX) 是 OR 并集语义，
-- 同 shot 既有 is_current=1 封版行又有更高 revision_sequence 未封版行（redo/崩溃重跑场景）
-- 时会返回两行，违反 read_current_text 单条不变量。改为 ROW_NUMBER() 优先级单行返回：
-- is_current=1 优先于任何未封版行；同为未封版时 revision_sequence 高者优先。
CREATE VIEW v_current_text AS
SELECT revision_id, shot_id, run_id, text, revision_sequence, is_current, source_revision_id
FROM (
    SELECT revision_id, shot_id, run_id, text, revision_sequence, is_current, source_revision_id,
           ROW_NUMBER() OVER (
               PARTITION BY shot_id
               ORDER BY is_current DESC, revision_sequence DESC
           ) AS rn
    FROM writing_shot_revisions
)
WHERE rn = 1;
-- 不变量：每个 shot_id 在 v_current_text 中恰好一行。
-- 集成测试（M0 必补）：同 shot 存在 is_current=1 行 + 更高 revision_sequence 未封版行时，
-- SELECT * FROM v_current_text WHERE shot_id=? 只返回一行（is_current=1 那行）。
```

### 2.4 第 4 层：评审（5 张） — jury 拆 raw + aggregate（评审 #1/#7 修复）

```sql
-- 19. writing_draft_eligibility（2 道硬门槛）
-- 评审 medium 修订：8 个 eligible 列补 CHECK(0,1) + 子项一致性 CHECK（eligible=1 要求所有子项=1）
CREATE TABLE writing_draft_eligibility (
    eligibility_id INTEGER PRIMARY KEY,
    draft_id INTEGER NOT NULL,
    gate1_eligible INTEGER NOT NULL CHECK (gate1_eligible IN (0,1)),
    gate1_contract_compliance INTEGER NOT NULL CHECK (gate1_contract_compliance IN (0,1)),
    gate1_forbidden_check INTEGER NOT NULL CHECK (gate1_forbidden_check IN (0,1)),
    gate1_capacity INTEGER NOT NULL CHECK (gate1_capacity IN (0,1)),
    gate1_basic_readability INTEGER NOT NULL CHECK (gate1_basic_readability IN (0,1)),
    gate2_eligible INTEGER NOT NULL CHECK (gate2_eligible IN (0,1)),
    gate2_fact_anchor INTEGER NOT NULL CHECK (gate2_fact_anchor IN (0,1)),
    gate2_scene_contract INTEGER NOT NULL CHECK (gate2_scene_contract IN (0,1)),
    gate2_pov_compliance INTEGER NOT NULL CHECK (gate2_pov_compliance IN (0,1)),
    gate2_structure_skeleton INTEGER NOT NULL CHECK (gate2_structure_skeleton IN (0,1)),
    evaluated_at TEXT NOT NULL,
    -- gate1_eligible=1 当且仅当 4 子项全 1（eligible=0 但子项全 1 非法；eligible=1 但某子项=0 非法）
    CHECK (gate1_eligible = (gate1_contract_compliance AND gate1_forbidden_check AND gate1_capacity AND gate1_basic_readability)),
    CHECK (gate2_eligible = (gate2_fact_anchor AND gate2_scene_contract AND gate2_pov_compliance AND gate2_structure_skeleton)),
    FOREIGN KEY (draft_id) REFERENCES writing_drafts(draft_id) ON DELETE CASCADE
);
CREATE INDEX idx_eligibility_draft ON writing_draft_eligibility(draft_id);

-- 20. writing_jury_raw_scores（裁判原始分）
-- 基础轮 jury_round=1：3 裁判全评 12 维，无稀疏 NULL。
-- 分歧升级轮 jury_round>1：可使用 writing_projects.escalated_jury_count（默认 5）个裁判重评。
-- judge_role 只是 prompt 主视角标签，不是裁判身份标识；同一 role 可在升级轮重复。
-- 真正由 DB 保证的不变量："同一 draft 同一 jury_round 同一 judge_model/slot 只能一行"。
-- "judge_model 不等于该 draft 的 writer_model" 是跨表约束：
-- 1) literary_jury.dispatch 按 draft 动态排除；
-- 2) SQLite trigger 在落库时兜底阻断；
-- 3) post-write JOIN 审计作为测试门禁。
CREATE TABLE writing_jury_raw_scores (
    raw_score_id INTEGER PRIMARY KEY,
    draft_id INTEGER NOT NULL,
    shot_contract_id INTEGER NOT NULL,
    jury_round INTEGER NOT NULL DEFAULT 1 CHECK (jury_round >= 1),  -- 1=基础 3 裁判；>1=分歧升级重评
    judge_slot INTEGER NOT NULL CHECK (judge_slot >= 1),            -- 该轮第几个裁判，基础轮为 1..3，升级轮为 1..escalated_jury_count
    judge_model TEXT NOT NULL,                       -- 裁判模型（身份标识）
    judge_role TEXT NOT NULL CHECK (judge_role IN ('text','literary','cross_shot')),
    -- 12 维分数（0-100），3 裁判全填（方案 B），NOT NULL + CHECK 区间（评审 medium）
    scene_visual INTEGER NOT NULL CHECK (scene_visual BETWEEN 0 AND 100),                   -- 画面感官
    rhythm_pacing INTEGER NOT NULL CHECK (rhythm_pacing BETWEEN 0 AND 100),                 -- 节奏张弛
    dialogue_subtext INTEGER NOT NULL CHECK (dialogue_subtext BETWEEN 0 AND 100),           -- 对话潜台词
    suspense_tension INTEGER NOT NULL CHECK (suspense_tension BETWEEN 0 AND 100),           -- 悬疑紧张
    language_texture INTEGER NOT NULL CHECK (language_texture BETWEEN 0 AND 100),           -- 语言质感
    emotional_progression INTEGER NOT NULL CHECK (emotional_progression BETWEEN 0 AND 100), -- 情感推进
    character_believability INTEGER NOT NULL CHECK (character_believability BETWEEN 0 AND 100), -- 人物可信
    structure_landing INTEGER NOT NULL CHECK (structure_landing BETWEEN 0 AND 100),         -- 结构落地
    reading_fluency INTEGER NOT NULL CHECK (reading_fluency BETWEEN 0 AND 100),             -- 可读流畅
    motif_theme_fit INTEGER NOT NULL CHECK (motif_theme_fit BETWEEN 0 AND 100),             -- 母题主题贴合
    chapter_continuity INTEGER NOT NULL CHECK (chapter_continuity BETWEEN 0 AND 100),       -- 章续衔接
    creative_boundary INTEGER NOT NULL CHECK (creative_boundary BETWEEN 0 AND 100),         -- 创意边界（裁判3 参考 deviant_reference）
    evaluated_at TEXT NOT NULL,
    -- 不变量：同一 draft 同一 jury_round 内，同一 slot/model 只能出现一次（防重复评分，评审 P0-4）
    UNIQUE (draft_id, jury_round, judge_slot),
    UNIQUE (draft_id, jury_round, judge_model),
    FOREIGN KEY (draft_id) REFERENCES writing_drafts(draft_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);
-- 应用层断言（literary_jury.dispatch 落库后校验，DB 层 CHECK 无法表达"每轮恰好 N 行"）：
-- 基础轮：jury_round=1 必须 count(*)=3 且 count(DISTINCT judge_model)=3，judge_slot=1..3。
-- 升级轮：jury_round>1 必须 count(*)=writing_projects.escalated_jury_count，且模型去重。
CREATE INDEX idx_jury_raw_draft ON writing_jury_raw_scores(draft_id, jury_round, judge_model);

CREATE TRIGGER trg_jury_raw_no_self_judge_insert
BEFORE INSERT ON writing_jury_raw_scores
FOR EACH ROW
WHEN EXISTS (
    SELECT 1 FROM writing_drafts d
    WHERE d.draft_id = NEW.draft_id AND d.writer_model = NEW.judge_model
)
BEGIN
    SELECT RAISE(ABORT, 'judge_model must differ from writer_model');
END;

CREATE TRIGGER trg_jury_raw_no_self_judge_update
BEFORE UPDATE OF draft_id, judge_model ON writing_jury_raw_scores
FOR EACH ROW
WHEN EXISTS (
    SELECT 1 FROM writing_drafts d
    WHERE d.draft_id = NEW.draft_id AND d.writer_model = NEW.judge_model
)
BEGIN
    SELECT RAISE(ABORT, 'judge_model must differ from writer_model');
END;

-- 21. writing_jury_aggregates（评分聚合，1 行/draft）
CREATE TABLE writing_jury_aggregates (
    aggregate_id INTEGER PRIMARY KEY,
    shot_id TEXT NOT NULL,
    draft_id INTEGER NOT NULL UNIQUE,
    shot_contract_id INTEGER NOT NULL,
    jury_round_used INTEGER NOT NULL DEFAULT 1 CHECK (jury_round_used >= 1), -- 聚合采用的 raw score 轮次；分歧升级后使用最新升级轮
    judge_count INTEGER NOT NULL DEFAULT 3 CHECK (judge_count >= 3),         -- 该轮参与聚合的裁判数，基础轮 3，升级轮 escalated_jury_count
    -- 12 维中位数得分（3 样本去 1 高 1 低剩 1 个 = median，P0-1 诚实声明：trimmed mean 退化为 median）
    scene_visual_median REAL NOT NULL CHECK (scene_visual_median BETWEEN 0 AND 100),
    rhythm_pacing_median REAL NOT NULL CHECK (rhythm_pacing_median BETWEEN 0 AND 100),
    dialogue_subtext_median REAL NOT NULL CHECK (dialogue_subtext_median BETWEEN 0 AND 100),
    suspense_tension_median REAL NOT NULL CHECK (suspense_tension_median BETWEEN 0 AND 100),
    language_texture_median REAL NOT NULL CHECK (language_texture_median BETWEEN 0 AND 100),
    emotional_progression_median REAL NOT NULL CHECK (emotional_progression_median BETWEEN 0 AND 100),
    character_believability_median REAL NOT NULL CHECK (character_believability_median BETWEEN 0 AND 100),
    structure_landing_median REAL NOT NULL CHECK (structure_landing_median BETWEEN 0 AND 100),
    reading_fluency_median REAL NOT NULL CHECK (reading_fluency_median BETWEEN 0 AND 100),
    motif_theme_fit_median REAL NOT NULL CHECK (motif_theme_fit_median BETWEEN 0 AND 100),
    chapter_continuity_median REAL NOT NULL CHECK (chapter_continuity_median BETWEEN 0 AND 100),
    creative_boundary_median REAL NOT NULL CHECK (creative_boundary_median BETWEEN 0 AND 100),
    weight_used TEXT NOT NULL,                       -- JSON：12 维加权权重 + _intensity_5d + _Z（weight_map 输出，见 §3.5）
    final_score REAL NOT NULL,                       -- 加权平均分（Σ median[d] × weight[d]）
    quality_gate_passed INTEGER NOT NULL DEFAULT 0 CHECK (quality_gate_passed IN (0,1)),
    quality_gate_reasons TEXT NOT NULL DEFAULT '[]', -- JSON：未通过维度/原因/证据
    judge_disagreement_max REAL NOT NULL DEFAULT 0 CHECK (judge_disagreement_max BETWEEN 0 AND 100),
    is_winner INTEGER NOT NULL DEFAULT 0,
    evaluated_at TEXT NOT NULL,
    -- 绝对底线 CHECK：项目运营阈值（writing_projects 表对应字段）不得低于此，由应用层取 max(项目阈值, 绝对底线) 执行。
    CHECK (quality_gate_passed = 0 OR final_score >= 80),          -- 绝对底线，运营阈值见 writing_projects.shot_quality_floor
    CHECK (quality_gate_passed = 0 OR judge_disagreement_max <= 25),  -- 绝对底线，运营阈值见 writing_projects.judge_disagreement_max
    CHECK (quality_gate_passed = 0 OR (
        scene_visual_median >= 65 AND rhythm_pacing_median >= 65 AND dialogue_subtext_median >= 65 AND
        suspense_tension_median >= 65 AND language_texture_median >= 65 AND emotional_progression_median >= 65 AND
        character_believability_median >= 65 AND structure_landing_median >= 65 AND reading_fluency_median >= 65 AND
        motif_theme_fit_median >= 65 AND chapter_continuity_median >= 65 AND creative_boundary_median >= 65
    )),  -- 绝对底线 65，运营阈值见 writing_projects.dimension_floor
    CHECK (is_winner = 0 OR quality_gate_passed = 1),
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (draft_id) REFERENCES writing_drafts(draft_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX idx_jury_aggregate_winner ON writing_jury_aggregates(shot_id) WHERE is_winner = 1;

-- 22. writing_chapter_reviews（章级 7 维硬质量门禁）
-- 质量硬门禁修订：7 维全部是 accepted 前硬门禁；问题可注入后文，但不能替代本章达标。
CREATE TABLE writing_chapter_reviews (
    review_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    chapter_id INTEGER NOT NULL,
    run_id INTEGER NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending','accepted','rejected','revised')),
    -- 章级 7 维（accepted 前全部必须达标），0-100
    chapter_continuity_hard INTEGER CHECK (chapter_continuity_hard IS NULL OR chapter_continuity_hard BETWEEN 0 AND 100),
    pov_consistency INTEGER CHECK (pov_consistency IS NULL OR pov_consistency BETWEEN 0 AND 100),
    character_consistency INTEGER CHECK (character_consistency IS NULL OR character_consistency BETWEEN 0 AND 100),
    chapter_hook_soft INTEGER CHECK (chapter_hook_soft IS NULL OR chapter_hook_soft BETWEEN 0 AND 100),
    rhythm_curve INTEGER CHECK (rhythm_curve IS NULL OR rhythm_curve BETWEEN 0 AND 100),
    motif_density INTEGER CHECK (motif_density IS NULL OR motif_density BETWEEN 0 AND 100),
    info_gap_lifecycle INTEGER CHECK (info_gap_lifecycle IS NULL OR info_gap_lifecycle BETWEEN 0 AND 100),
    quality_gate_passed INTEGER NOT NULL DEFAULT 0 CHECK (quality_gate_passed IN (0,1)),
    blocking_issues TEXT NOT NULL DEFAULT '[]',      -- JSON：任一硬质量失败项
    review_notes TEXT,
    reviewed_at TEXT NOT NULL,
    -- accepted 要求 7 维非 NULL、全部 >= 绝对底线 75（运营阈值见 writing_projects.chapter_quality_floor）、质量门禁通过。
    CHECK (status != 'accepted' OR (
        quality_gate_passed = 1 AND
        chapter_continuity_hard IS NOT NULL AND pov_consistency IS NOT NULL AND character_consistency IS NOT NULL AND
        chapter_hook_soft IS NOT NULL AND rhythm_curve IS NOT NULL AND motif_density IS NOT NULL AND info_gap_lifecycle IS NOT NULL AND
        chapter_continuity_hard >= 75 AND pov_consistency >= 75 AND character_consistency >= 75 AND
        chapter_hook_soft >= 75 AND rhythm_curve >= 75 AND motif_density >= 75 AND info_gap_lifecycle >= 75
    )),  -- 绝对底线 75，运营阈值见 writing_projects.chapter_quality_floor
    UNIQUE (project_id, chapter_id, run_id),   -- accepted canonical 唯一索引
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX idx_chapter_accepted ON writing_chapter_reviews(project_id, chapter_id) WHERE status = 'accepted';

-- 23. writing_failure_attributions（评审 #16：扩展审计链，支撑质量阻断与非质量降级追溯）
CREATE TABLE writing_failure_attributions (
    attribution_id INTEGER PRIMARY KEY,
    draft_id INTEGER,
    shot_id TEXT NOT NULL,
    failure_category TEXT NOT NULL,
    failure_level TEXT NOT NULL CHECK (failure_level IN ('draft','hard_gate1','hard_gate2','jury','quality_gate','polish','soft_gate','chapter_review','book_check')),
    contract_clause_id INTEGER,                      -- 指向 writing_contract_clauses，支撑 D-23 条款级审计
    gate_name TEXT,                                  -- 触发失败的 gate 名
    soft_gate_n INTEGER,                             -- soft gate 第 N 级（1/2/3）
    injected_to_shot_id TEXT,                        -- 问题注入到哪个后续 shot
    failure_detail TEXT,
    degraded INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY (draft_id) REFERENCES writing_drafts(draft_id) ON DELETE CASCADE,
    FOREIGN KEY (contract_clause_id) REFERENCES writing_contract_clauses(clause_id),
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_attribution_shot ON writing_failure_attributions(shot_id);
```

### 2.5 第 5 层：悬疑、一致性与篇级检测（3 张）

```sql
-- 24. writing_information_gaps（评审 #9：加 abandoned 终态 + 转移合法性）
-- 评审 medium 修订：补转移合法性 CASE CHECK（DB 层拦截非法跳转，如 pending 直接 resolved）
CREATE TABLE writing_information_gaps (
    gap_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    gap_name TEXT NOT NULL,
    planted_chapter INTEGER NOT NULL,
    planted_shot TEXT,
    -- 转移合法性（prev_status → status）：
    --   pending → active
    --   active → reinforced | revealed | resolved | abandoned
    --   reinforced → reinforced | revealed | resolved | abandoned
    --   revealed → resolved | abandoned
    --   resolved → （终态，无出边）
    --   abandoned → （终态，无出边）
    -- 应用层写 status 时同事务写 prev_status；DB CHECK 断言 (prev_status, status) 合法。
    prev_status TEXT,   -- 上一状态（NULL 表示首次插入 pending）
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','reinforced','revealed','resolved','abandoned')),
    resolved_chapter INTEGER,
    resolved_shot TEXT,
    abandoned_chapter INTEGER,                       -- 放弃章节
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    CHECK ((
        prev_status IS NULL AND status = 'pending'
    ) OR (
        prev_status = 'pending' AND status = 'active'
    ) OR (
        prev_status IN ('active','reinforced') AND status IN ('reinforced','revealed','resolved','abandoned')
    ) OR (
        prev_status = 'revealed' AND status IN ('resolved','abandoned')
    ) OR (
        prev_status = status AND status IN ('reinforced')  -- reinforced 自环（多次加固）
    )),
    UNIQUE (project_id, gap_name),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX idx_info_gap_status ON writing_information_gaps(project_id, status);

-- 25. writing_motif_instances
CREATE TABLE writing_motif_instances (
    motif_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    motif_name TEXT NOT NULL,
    chapter_id INTEGER NOT NULL,
    shot_id TEXT,
    instance_text TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_motif_project_chapter ON writing_motif_instances(project_id, chapter_id);

-- 26. writing_shot_scene_fingerprints（L3 多样性 gate，与 motif 同层管理）
CREATE TABLE writing_shot_scene_fingerprints (
    fingerprint_id INTEGER PRIMARY KEY,
    shot_id TEXT NOT NULL,
    location_hash TEXT NOT NULL,
    time_hash TEXT NOT NULL,
    character_set_hash TEXT NOT NULL,
    similarity_score REAL,                           -- 与近邻 shot 的场景相似度
    created_at TEXT NOT NULL,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_fingerprint_shot ON writing_shot_scene_fingerprints(shot_id);
```

### 2.6 篇级滚动检测落库（评审 #18，新增表）

```sql
-- 27. writing_book_check_results（篇级检测结果，支撑增量检测）
CREATE TABLE writing_book_check_results (
    check_run_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    check_sequence INTEGER NOT NULL,                 -- 第 k 次检测
    chapter_range_start INTEGER NOT NULL,            -- 本次检测起始章
    chapter_range_end INTEGER NOT NULL,              -- 本次检测截止章（= 当前章）
    -- 6 维全书级检测分数
    longline_suspense_closure REAL,                  -- 长线悬念闭环
    character_arc_completeness REAL,                 -- 角色弧光完整
    motif_echo_density REAL,                         -- 母题回响
    theme_sublimation REAL,                          -- 主题升华
    global_rhythm_curve REAL,                        -- 全书节奏曲线
    foreshadow_recovery REAL,                        -- 伏笔回收
    is_incremental INTEGER NOT NULL DEFAULT 0,       -- 是否增量检测（1=只检测新增章节）
    issues TEXT NOT NULL,                            -- JSON：问题列表（注入到 chapter_specs.injected_issues）
    blocking_issue_count INTEGER NOT NULL DEFAULT 0 CHECK (blocking_issue_count >= 0),
    quality_gate_passed INTEGER NOT NULL DEFAULT 0 CHECK (quality_gate_passed IN (0,1)),
    created_at TEXT NOT NULL,
    CHECK (quality_gate_passed = 0 OR blocking_issue_count = 0),
    CHECK (quality_gate_passed = 0 OR (
        longline_suspense_closure IS NOT NULL AND character_arc_completeness IS NOT NULL AND motif_echo_density IS NOT NULL AND
        theme_sublimation IS NOT NULL AND global_rhythm_curve IS NOT NULL AND foreshadow_recovery IS NOT NULL AND
        longline_suspense_closure >= 75 AND character_arc_completeness >= 75 AND motif_echo_density >= 75 AND
        theme_sublimation >= 75 AND global_rhythm_curve >= 75 AND foreshadow_recovery >= 75
    )),  -- 绝对底线 75，运营阈值见 writing_projects.book_quality_floor
    UNIQUE (project_id, check_sequence),
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);
CREATE INDEX idx_book_check_project ON writing_book_check_results(project_id, chapter_range_end);
```

### 2.7 生产审计、恢复、导入与人工决策（13 张）

```sql
-- 28. writing_ai_call_attempts（所有 AI 调用的幂等审计）
CREATE TABLE writing_ai_call_attempts (
    attempt_id INTEGER PRIMARY KEY,
    idempotency_key TEXT NOT NULL UNIQUE,
    project_id INTEGER NOT NULL,
    shot_id TEXT,
    run_id INTEGER,
    call_type TEXT NOT NULL CHECK (call_type IN ('outline','task_card','prompt','draft','polish','gate1_semantic','gate2','jury','chapter_review','book_check','import')),
    model_provider TEXT NOT NULL,
    model_name TEXT NOT NULL,
    prompt_id INTEGER,
    prompt_hash TEXT NOT NULL,
    response_hash TEXT,
    response_path TEXT,
    token_input INTEGER,
    token_output INTEGER,
    latency_ms INTEGER,
    finish_reason TEXT,
    success INTEGER NOT NULL CHECK (success IN (0,1)),
    error_category TEXT,
    retry_of INTEGER,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (prompt_id) REFERENCES writing_prompt_snapshots(prompt_id),
    FOREIGN KEY (retry_of) REFERENCES writing_ai_call_attempts(attempt_id)
);
CREATE INDEX idx_ai_attempts_shot ON writing_ai_call_attempts(shot_id, call_type, created_at);

-- 29. writing_runtime_events（运行时事件时间线）
CREATE TABLE writing_runtime_events (
    event_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    session_id INTEGER,
    run_id INTEGER,
    shot_id TEXT,
    event_type TEXT NOT NULL,
    event_payload TEXT NOT NULL,                      -- JSON
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES writing_sessions(session_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_runtime_events_timeline ON writing_runtime_events(project_id, created_at);

-- 30. writing_llm_failure_streaks（连续失败计数权威源）
CREATE TABLE writing_llm_failure_streaks (
    streak_id INTEGER PRIMARY KEY,
    shot_id TEXT NOT NULL,
    call_type TEXT NOT NULL,
    failure_type TEXT NOT NULL,
    consecutive_count INTEGER NOT NULL DEFAULT 0 CHECK (consecutive_count >= 0),
    last_error_at TEXT NOT NULL,
    UNIQUE (shot_id, call_type, failure_type),
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);

-- 31. writing_session_checkpoints（崩溃恢复 checkpoint）
-- 崩溃恢复幂等性设计（见 §3.8）：
-- 1. checkpoint 写入必须原子（事务内完成 payload + checksum 一起写入）
-- 2. 恢复时先校验 checksum，不匹配则视为损坏，回退到上一个有效 checkpoint
-- 3. checkpoint_max_retention 控制保留数量，避免无限增长
CREATE TABLE writing_session_checkpoints (
    checkpoint_id INTEGER PRIMARY KEY,
    session_id INTEGER NOT NULL,
    run_id INTEGER,
    shot_id TEXT,
    phase TEXT NOT NULL,
    checkpoint_payload TEXT NOT NULL,                -- JSON：恢复所需的状态快照
    payload_checksum TEXT NOT NULL,                  -- SHA-256(checkpoint_payload)，用于检测部分写入/损坏
    created_at TEXT NOT NULL,
    CHECK (shot_id IS NULL OR shot_id LIKE '%@%'),   -- NULL 表示 session/phase 级 checkpoint
    FOREIGN KEY (session_id) REFERENCES writing_sessions(session_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_checkpoints_session ON writing_session_checkpoints(session_id, created_at);

-- 32. writing_human_decisions（人工决策审计）
CREATE TABLE writing_human_decisions (
    decision_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    session_id INTEGER,
    run_id INTEGER,
    shot_id TEXT,
    chapter_id INTEGER,
    decision_type TEXT NOT NULL CHECK (decision_type IN ('setup_confirm','contract_confirm','accept','revise','reject','abort','import_finalize')),
    actor TEXT NOT NULL,
    reason TEXT NOT NULL,
    preconditions_json TEXT NOT NULL,                -- JSON：accept/revise/reject 前置条件校验结果
    quality_report_json TEXT NOT NULL DEFAULT '{}',  -- JSON：QualityReport，含 ES/SEMI_ES/NES、destructive/productive/neutral、盲评与继续阅读
    hard_quality_override INTEGER NOT NULL DEFAULT 0 CHECK (hard_quality_override = 0), -- 硬质量失败不可人工覆盖
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (session_id) REFERENCES writing_sessions(session_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE
);
CREATE INDEX idx_human_decisions_project ON writing_human_decisions(project_id, chapter_id, created_at);

-- 33. writing_contract_clauses（条款级契约审计）
CREATE TABLE writing_contract_clauses (
    clause_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    shot_contract_id INTEGER,
    clause_scope TEXT NOT NULL CHECK (clause_scope IN ('meta','chapter','shot')),
    clause_key TEXT NOT NULL,
    clause_text TEXT NOT NULL,
    severity TEXT NOT NULL CHECK (severity IN ('hard','soft','diagnostic')),
    source_hash TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_contract_id) REFERENCES writing_shot_contracts(shot_contract_id) ON DELETE CASCADE
);
CREATE INDEX idx_contract_clauses_scope ON writing_contract_clauses(project_id, clause_scope, clause_key);

-- 34. writing_contract_changelog（契约变更历史）
CREATE TABLE writing_contract_changelog (
    change_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    clause_id INTEGER,
    old_hash TEXT,
    new_hash TEXT NOT NULL,
    actor TEXT NOT NULL,
    reason TEXT NOT NULL,
    human_decision_id INTEGER,
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (clause_id) REFERENCES writing_contract_clauses(clause_id),
    FOREIGN KEY (human_decision_id) REFERENCES writing_human_decisions(decision_id)
);

-- 35. writing_fact_anchors（事实锚点）
CREATE TABLE writing_fact_anchors (
    anchor_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    shot_id TEXT,
    revision_id INTEGER,
    fact_text TEXT NOT NULL,
    source_span TEXT,
    confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    status TEXT NOT NULL CHECK (status IN ('proposed','confirmed','violated','deprecated')),
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (revision_id) REFERENCES writing_shot_revisions(revision_id)
);
CREATE INDEX idx_fact_anchors_project ON writing_fact_anchors(project_id, status);

-- 36. writing_context_snapshots（prompt/context 输入快照）
CREATE TABLE writing_context_snapshots (
    context_snapshot_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    shot_id TEXT NOT NULL,
    run_id INTEGER NOT NULL,
    prompt_id INTEGER,
    context_hash TEXT NOT NULL,
    upstream_revision_ids TEXT NOT NULL,             -- JSON array
    context_payload TEXT NOT NULL,                   -- JSON，供 replay 和 stale 检测
    created_at TEXT NOT NULL,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE,
    FOREIGN KEY (shot_id) REFERENCES writing_shots(shot_id) ON DELETE CASCADE,
    FOREIGN KEY (run_id) REFERENCES writing_runs(run_id) ON DELETE CASCADE,
    FOREIGN KEY (prompt_id) REFERENCES writing_prompt_snapshots(prompt_id)
);
CREATE INDEX idx_context_snapshots_shot ON writing_context_snapshots(shot_id, run_id);

-- 37. writing_import_runs（已有稿导入/重构批次）
CREATE TABLE writing_import_runs (
    import_run_id INTEGER PRIMARY KEY,
    project_id INTEGER NOT NULL,
    mode TEXT NOT NULL CHECK (mode IN ('dry_run','finalize')),
    source_root TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('running','needs_human','completed','failed')),
    created_at TEXT NOT NULL,
    finalized_at TEXT,
    FOREIGN KEY (project_id) REFERENCES writing_projects(project_id) ON DELETE CASCADE
);

-- 38. writing_import_manifests（导入映射清单）
CREATE TABLE writing_import_manifests (
    manifest_id INTEGER PRIMARY KEY,
    import_run_id INTEGER NOT NULL,
    source_path TEXT NOT NULL,
    source_hash TEXT NOT NULL,
    target_chapter_id INTEGER,
    target_logical_shot_id TEXT,
    confidence REAL NOT NULL CHECK (confidence >= 0 AND confidence <= 1),
    action TEXT NOT NULL CHECK (action IN ('create','update','skip','question')),
    created_at TEXT NOT NULL,
    FOREIGN KEY (import_run_id) REFERENCES writing_import_runs(import_run_id) ON DELETE CASCADE
);
CREATE INDEX idx_import_manifest_run ON writing_import_manifests(import_run_id, target_chapter_id);

-- 39. writing_import_questions（低置信导入问题）
CREATE TABLE writing_import_questions (
    question_id INTEGER PRIMARY KEY,
    import_run_id INTEGER NOT NULL,
    manifest_id INTEGER,
    question_text TEXT NOT NULL,
    options_json TEXT NOT NULL,
    resolution TEXT,
    resolved_by TEXT,
    resolved_at TEXT,
    FOREIGN KEY (import_run_id) REFERENCES writing_import_runs(import_run_id) ON DELETE CASCADE,
    FOREIGN KEY (manifest_id) REFERENCES writing_import_manifests(manifest_id) ON DELETE CASCADE
);

-- 40. writing_import_decisions（导入 finalize 决策）
CREATE TABLE writing_import_decisions (
    import_decision_id INTEGER PRIMARY KEY,
    import_run_id INTEGER NOT NULL,
    human_decision_id INTEGER NOT NULL,
    applied_manifest_hash TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (import_run_id) REFERENCES writing_import_runs(import_run_id) ON DELETE CASCADE,
    FOREIGN KEY (human_decision_id) REFERENCES writing_human_decisions(decision_id)
);
```

### 2.8 索引清单（评审 #29：补全）

关键 FK 列 + 高频查询列建显式索引；低频审计指针不机械建索引，避免写放大。SQLite 自动唯一索引也计入 DDL 烟测，但本节只列显式索引与关键唯一索引：
- `writing_shot_revisions(shot_id) WHERE is_current = 1` 唯一索引（每 shot 最多一个 current）
- `writing_shot_revisions(shot_id, is_current) WHERE is_current = 1`（封版读取）
- `writing_shot_revisions(shot_id, revision_sequence)`（未封版读 MAX）
- `writing_chapter_reviews` 的 accepted canonical 唯一索引
- `writing_outline_specs` 的 is_winner 唯一索引（评审 #30）
- `writing_jury_raw_scores(draft_id)` + `(draft_id, judge_model)` 唯一索引（P0-4）
- `writing_jury_aggregates` 的 is_winner 唯一索引
- `writing_drafts(shot_id)`（查某 shot 的候选稿）
- `writing_shots(logical_shot_id)` + `(run_id)`（N 计数跨 run 查询 + resume 定位）
- `writing_failure_attributions(shot_id)`（审计追溯）
- `writing_information_gaps(project_id, status)`（篇级检测读 pending 悬念）
- `writing_motif_instances(project_id, chapter_id)`（密度统计）
- `writing_book_check_results(project_id, chapter_range_end)`（增量检测定位上次截止）
- `writing_ai_call_attempts(shot_id, call_type, created_at)`（AI 调用审计）
- `writing_runtime_events(project_id, created_at)`（事件时间线）
- `writing_llm_failure_streaks(shot_id, call_type, failure_type)`（连续失败熔断）
- `writing_session_checkpoints(session_id, created_at)`（崩溃恢复）
- `writing_human_decisions(project_id, chapter_id, created_at)`（人工决策审计）
- `writing_contract_clauses(project_id, clause_scope, clause_key)`（条款级审计）
- `writing_fact_anchors(project_id, status)`（事实锚点扫描）
- `writing_context_snapshots(shot_id, run_id)`（replay/stale 检测）
- `writing_import_manifests(import_run_id, target_chapter_id)`（导入 dry-run/finalize）

### 2.9 ON DELETE CASCADE 策略矩阵（评审 medium）

**级联删除（ON DELETE CASCADE）**：从属子表，父删子随。
| 子表 | FK → 父表 | 理由 |
|------|-----------|------|
| writing_meta_contracts | project_id → projects | 项目删元契约随删 |
| writing_chapter_specs | project_id → projects | 同上 |
| writing_outline_specs | shot_contract_id → shot_contracts | 契约删大纲评估随删 |
| writing_shot_*（5 张结构化子表）| shot_contract_id → shot_contracts | 契约删核心字段随删 |
| writing_shot_task_cards | （契约链）| 同上 |
| writing_prompt_snapshots | task_card_id → task_cards | task card 删快照随删 |
| writing_sessions / writing_runs | project_id/session_id | 项目删 session/run 随删，session 删 run 随删 |
| writing_soft_gate_counters | project_id → projects | 项目删 soft gate 计数随删 |
| writing_shot_revisions | shot_id → shots | shot 删封版记录随删 |
| writing_drafts | shot_id → shots, prompt_id → prompt_snapshots | 执行记录随删；prompt 删候选稿随删 |
| writing_draft_eligibility | draft_id → drafts | 稿删门槛结果随删 |
| writing_jury_raw_scores | draft_id → drafts | 稿删原始分随删 |
| writing_jury_aggregates | draft_id → drafts, shot_contract_id → shot_contracts | 稿删聚合随删 |
| writing_chapter_reviews | project_id, run_id | 项目/run 删审稿随删 |
| writing_failure_attributions | draft_id, shot_id | 审计链随删 |
| writing_information_gaps | project_id | 项目删信息差随删 |
| writing_motif_instances | project_id | 同上 |
| writing_shot_scene_fingerprints | shot_id | 同上 |
| writing_book_check_results | project_id | 同上 |
| writing_ai_call_attempts | project_id/run_id/shot_id | 项目/run/shot 删调用审计随删 |
| writing_runtime_events | project_id/session_id/run_id/shot_id | 运行事件随执行实体删除 |
| writing_llm_failure_streaks | shot_id | shot 删连续失败计数随删 |
| writing_session_checkpoints | session_id/run_id/shot_id | session 删 checkpoint 随删 |
| writing_human_decisions | project_id/session_id/run_id/shot_id | 项目级人工决策随删 |
| writing_contract_clauses | project_id/shot_contract_id | 契约条款随项目/契约删 |
| writing_fact_anchors | project_id/shot_id | 项目或 shot 删事实锚点随删；revision 指针不级联 |
| writing_context_snapshots | project_id/shot_id/run_id | 上下文快照随执行删 |
| writing_import_runs / manifests / questions / decisions | project_id/import_run_id | 导入账本随项目删 |

**不级联（无 ON DELETE）**：跨 run 审计指针，保留历史。
| 子表 | FK → 父表 | 理由 |
|------|-----------|------|
| writing_shots | shot_contract_id → shot_contracts | 契约删不连带删执行记录（执行是独立审计实体，contract 删时 shots 留档或先手工清理） |
| writing_drafts | source_revision_id → shot_revisions | revision 删不连带删 draft（draft 是候选稿审计，指向历史 revision 保留） |
| writing_shot_revisions | source_revision_id → shot_revisions（自引用）| 跨 run redo 指针，不级联（级联会连锁删除整条 redo 链） |
| writing_ai_call_attempts | prompt_id/retry_of | prompt 和 retry 链是审计引用，不随被引用 attempt/prompt 误删 |
| writing_context_snapshots | prompt_id | prompt 是 replay 引用，不随 prompt 误删上下文快照 |
| writing_fact_anchors | revision_id → shot_revisions | revision 删不连带删事实锚点，锚点是审计实体 |
| writing_contract_changelog | clause_id / human_decision_id | 契约变更日志保留历史，不随条款或人工决策误删 |
| writing_import_decisions | human_decision_id → human_decisions | import finalize 记录保留引用，不随人工决策误删 |

**策略**：从属数据级联，审计指针不级联。项目级删除（删 project）级联清掉所有项目内数据；shot 级删除只级联直接从属（drafts/revisions/eligibility/jury），不级联到 contract（contract 独立生命周期）。

---

## 3. 模块接口契约

### 3.0 错误类型层级

所有业务异常统一定义在 `src/ink/errors.py`，模块不得各自发明根异常。

```python
class InkError(Exception): ...

class StateError(InkError): ...
class IllegalTransitionError(StateError): ...
class TerminalStateError(StateError): ...

class ConcurrencyError(InkError): ...
class ConcurrentModificationError(ConcurrencyError): ...

class QualityError(InkError): ...
class QualityGateFailedError(QualityError): ...
class QualityFloorNotMetError(QualityError): ...
class ProductiveDeviationLostError(QualityError): ...

class DataError(InkError): ...
class ShotNotFoundError(DataError): ...
class SessionMismatchError(DataError): ...

class ConfigError(InkError): ...
class ModelPoolValidationError(ConfigError): ...

class LLMError(InkError): ...
class LLMUnavailableError(LLMError): ...
```

### 3.1 orchestrator 物理隔离（铁律 2）

shot 级 `pipeline/*_orchestrator.py` 的入口签名**只收 `(shot_id, run_id)`**，禁止传上游 dataclass：

```python
# 正确
def produce_drafts(shot_id: str, run_id: int) -> list[DraftSpec]:
    # 入口从 DB 重新加载 ShotContract/TaskCard/PromptSpec
    shot_contract = shot_contract_repo.load(shot_id, run_id)
    task_card = task_card_repo.load_latest(shot_id)
    prompt_spec = prompt_spec_repo.load_latest(task_card.task_card_id)
    ...

# 错误（禁止）
def produce_drafts(shot_contract: ShotContract, prompt_spec: PromptSpec) -> list[DraftSpec]:
    # 跨步骤复用 dataclass，铁律 2 禁止
    ...
```

**写操作上下文校验**（评审 #24，可执行定义）：任何写操作函数（落 draft、写 jury 分、封版 revision）必须：
1. 签名收 `(shot_id, run_id, ...)`，不收上游 dataclass 的"已处理"状态
2. 函数体内 `SELECT status FROM writing_shots WHERE shot_id=?` reload 当前状态
3. 校验状态机允许该写（如 `drafting` 才允许落 draft，`jury_scoring` 才允许写 score）
4. lint 断言写操作函数体含 `SELECT status` 调用

非 shot 级 orchestrator 可以收自己的业务 ID（如 `project_id, chapter_id, run_id`），但同样禁止传上游 dataclass，入口必须从 DB reload 所需投影。

**shot 级 orchestrator 清单**：
- `outline_orchestrator.evaluate_and_select(shot_id, run_id) -> OutlineSpec`
- `write_orchestrator.produce_drafts(shot_id, run_id) -> list[DraftSpec]`（含 deviant 1 篇）
- `hard_gate_orchestrator.run_both_gates(shot_id, run_id) -> list[DraftSpec]`（2 道门槛）
- `jury_orchestrator.score_and_select_winner(shot_id, run_id) -> DraftSpec`
- `gate_orchestrator.run_soft_gates(shot_id, run_id) -> GateResult`（含 3 级状态机）

**非 shot 级 orchestrator 清单**：
- `chapter_review_orchestrator.review_chapter(project_id, chapter_id, run_id) -> ChapterReview`
- `book_rolling_check_orchestrator.run_rolling_check(project_id, up_to_chapter) -> BookCheckResult`

### 3.2 text_repository 物理隔离（铁律 5，评审 #3 修订）

```python
# core/text_repository.py — 唯一可访问 writing_shot_revisions 的模块
class TextRepository:
    def read_current_text(self, shot_id: str, run_id: int) -> str:
        """封版规则（P0-3 修正）：走 DB VIEW v_current_text 的 ROW_NUMBER() 单行判定——
        已封版（存在 is_current=1 行）取该行，未封版取 MAX(revision_sequence) 行。
        VIEW 保证业务模块只读到唯一一行"当前正文"，不存在 OR 多行 bug。
        业务模块不可直接查 writing_shot_revisions 原表。"""
        ...

    def write_revision(self, shot_id: str, run_id: int, text: str,
                       source_revision_id: int | None = None,
                       seal: Literal['none','shot_soft','chapter_hard'] = 'none') -> int:
        """写正文，seal='none' 只追加 revision；seal='shot_soft' 不设 is_current（软封版，后续可被新 revision 覆盖）；
        seal='chapter_hard' 设 is_current=1（硬封版，事务内先把同 shot 旧行 is_current 置 0，再设置目标 revision）。
        返回 revision_id。v_current_text 的 ROW_NUMBER 保证读时只取一行。"""
        ...

    def is_hard_sealed(self, shot_id: str, run_id: int) -> bool:
        ...
```

**接口最小化**：只暴露上述 3 方法。**禁止** `get_text_by_revision_id` / `get_text_by_sequence` 类直查接口（旧系统正是用这类后门跳过封版判断）。

**物理隔离实现（三重约束）**：
- **Python import 边界**：`writing_shot_revisions` 表的 SQL 访问函数只暴露在 `core/text_repository.py`；`ink/src/ink/contract/generated/` 不生成 `ShotRevision` dataclass 的公开加载器
- **DB VIEW**：`v_current_text` 封装封版逻辑，业务模块查 view 而非原表
- **CI sqlparse lint**：`ink/src/ink/codegen/sql_access_lint.py` 用 sqlparse 解析所有 `execute()`/`cursor.executescript()` 调用的 SQL 字面量 token，断言只有 `core/text_repository.py` 的 SQL 含 `writing_shot_revisions` 表名（白名单 migration/schema/test 模块）。动态构造表名（`'writing_'+t`）、f-string 拼接 SQL 一律禁。

**诚实声明**：SQLite 无 RLS，所谓"物理隔离"是 Python import + DB VIEW + sqlparse CI 三重软约束，不是 DB 层硬隔离。若未来需真物理隔离，需迁移到 PostgreSQL + RLS。

### 3.3 retry_budget（铁律 4 的 soft gate 3 级，评审 #6 修订）

```python
# core/retry_budget.py
class SoftGateCounter:
    """同一 logical_shot_id 同一 soft gate 的连续失败计数。
    无状态：每次从 writing_soft_gate_counters 读，崩溃后计数不丢。"""
    def increment(self, project_id: int, logical_shot_id: str, gate_name: str) -> int:
        """判定后立即原子累加 writing_soft_gate_counters，返回新 N。
        writing_shots.soft_fail_counts_snapshot 只同步审计快照，不作为读路径。"""
        ...

    def get_level(self, project_id: int, logical_shot_id: str, gate_name: str) -> Literal[1, 2, 3]:
        """从 DB 读 N，映射到 1/2/3 级。无 n 参数（旧设计收 n 是错的）。
        升级阈值 soft_gate_redo_n（默认 2）/ soft_gate_fail_n（默认 3）从 writing_projects 读取。"""
        # N=1: 阻断不 redo
        # N=soft_gate_redo_n: 触发局部重写（产 >=2 篇新候选）
        # N=soft_gate_fail_n: 非质量 SOFT 可降级；QUALITY_BLOCKING 转 revise_required/failed，不放行
        ...

class LLMCallBudget:
    """shot 级 LLM 调用两层熔断（B59，评审 P0-5 拆分）。
    第 1 层：同类失败连续 consecutive_failure_circuit_break 次熔断 / 单类型调用 ≤ max_calls_per_shot。
    第 2 层：shot 总调用 ≤ max_total_llm_calls，防类型分散绕过第 1 层。
    阈值从 writing_projects 读取，运行时可调不改代码。
    总量计数落 writing_shots.llm_call_count + llm_call_breakdown。
    连续失败计数落 writing_llm_failure_streaks。
    每次调用落 writing_ai_call_attempts，运行状态落 writing_runtime_events。"""

    # 以下默认值仅为示例，实际从 writing_projects 读取
    # max_calls_per_shot = 8     # 第 1 层：单 call_type 上限（B59 原义）
    # max_total_llm_calls = 40   # 第 2 层：shot 总调用硬上限（P0-5 新增）
    # consecutive_failure_circuit_break = 3  # 同类失败连续 N 次熔断

    CallType = Literal['draft', 'polish', 'gate2', 'jury', 'chapter_review', 'book_check']

    def __init__(self, project_id: int):
        """从 writing_projects 加载阈值。"""
        ...

    def record_call(self, shot_id: str, call_type: CallType,
                    success: bool, failure_type: str | None = None) -> None:
        """每次 LLM 调用后立即落库：
        - llm_call_count += 1（原子 UPDATE SET count=count+1）
        - llm_call_breakdown[call_type] += 1
        - 若 success=False，更新 writing_llm_failure_streaks 的 (shot_id, call_type, failure_type) 连续失败计数；
          success=True 归零该 call_type 的 streak。
        先算 next_count 再判阈值（B59 原义）。"""
        ...

    def check_circuit(self, shot_id: str) -> tuple[bool, str | None]:
        """返回 (allow, reason)。
        - llm_call_count >= max_total_llm_calls → (False, 'total_exceeded')，调 transition(status,'failed')
        - 某 (call_type, failure_type) 连续失败 >= consecutive_failure_circuit_break → (False, 'consecutive_fail')，熔断该类型
        - 某 call_type 调用数 >= max_calls_per_shot → (False, 'per_type_exceeded')
        - 否则 (True, None)。"""
        ...
```

**P0-5 集成测试（M1 必补）**：
- 同类失败连续 `consecutive_failure_circuit_break`（默认 3）次熔断（第 4 次调 record_call 前 check_circuit 返回 False）
- 失败类型切换归零连续计数
- 总调用达 `max_total_llm_calls`（默认 40）次转 failed 终态（transition 合法，任一非终态 → failed）
- 计数崩溃恢复：record_call 落库后进程崩，重启 check_circuit 读到正确 count
- 阈值参数化测试：UPDATE writing_projects 修改阈值后，check_circuit 读取新值生效，不改代码

### 3.3b 自动重试机制（A'+A'' 机制，减少编辑工作量）

```python
# pipeline/auto_retry.py（或集成在 gate_orchestrator / jury_orchestrator 内）
class AutoRetryHandler:
    """hard gate / quality floor 失败后的自动重试处理。
    参数从 writing_projects 读取：
    - auto_retry_on_hard_failure: 是否启用
    - max_retries_per_gate: 每层 gate 最多重试次数
    - retry_strategy: 重试策略
    """

    RetryStrategy = Literal['change_model', 'adjust_intensity', 'relax_soft']

    def handle_failure(self, shot_id: str, run_id: int,
                       failed_gate: str, failure_detail: dict) -> RetryResult:
        """
        1. 检查 auto_retry_on_hard_failure 是否启用
        2. 检查 max_retries_per_gate 是否还有余量
        3. 检查 max_total_llm_calls 是否还有预算
        4. 按 retry_strategy 调整参数：
           - change_model: 从 writer_model_pool 选不同模型重新产稿
           - adjust_intensity: 微调 persona 5 维强度配比（±1）
           - relax_soft: 放宽 soft_constraints（仅限 deviant 或重试后期）
        5. 记录重试到 writing_runtime_events 和 writing_failure_attributions
        6. 返回 RetryResult(should_retry=True, new_params=...) 或 (should_retry=False, reason='budget_exhausted')
        """
        ...
```

**编辑工作量**：accept 路径上编辑零动作。系统自动重试直到预算耗尽。只有 `failed` 状态才上报编辑，动作是项目级资源决策（换模型池 / 调阈值 / 放弃该 shot），不是审美判断。

**参数化测试（M4 必补）**：
- `auto_retry_on_hard_failure=TRUE` 时，quality floor 失败后自动重试，重试成功则 winner 正常产生
- `auto_retry_on_hard_failure=FALSE` 时，quality floor 失败后直接转 failed
- `max_retries_per_gate` 达到后停止重试，转 failed
- `retry_strategy='change_model'` 时，每次重试使用不同写手模型
- 重试预算耗尽后转 failed，编辑介入

### 3.3a LLMGateway（所有 AI 调用唯一入口）

```python
# core/llm_gateway.py
class LLMGateway:
    def call(self, shot_id: str | None, run_id: int | None, call_type: str,
             prompt_id: int | None, prompt_text: str, model_name: str,
             idempotency_key: str) -> ModelResult:
        """唯一 AI 调用入口：
        1. 调用前 check_circuit；
        2. 写 writing_ai_call_attempts pending/started 记录；
        3. 执行模型调用；
        4. 无论成功失败都更新 attempt、failure streak、runtime_events；
        5. 根据 budget/gate 结果决定是否 transition 到 failed。
        """
        ...
```

任何服务模块不得直接调用供应商 SDK。`sql_access_lint` 同级新增 `llm_access_lint`，扫描除 `core/llm_gateway.py` 与测试外的供应商 SDK 调用并阻断。

### 3.4 quad_dispatcher（同 persona + 同 prompt + 换模型）

```python
# writers/quad_dispatcher.py
def produce_drafts(shot_id: str, run_id: int) -> list[DraftSpec]:
    """
    同 persona + 同 prompt + 换写手模型，产 X 篇候选 + 1 篇 deviant。
    - X 从 writing_projects.draft_count 读（创意 shot + creative_shot_extra）
    - 写手模型池从 writing_projects.writer_model_pool 读（DB CHECK 保证 X <= 池大小）
    - deviant 用 relaxed_soft=True 的 PromptSpec
    - N=2 局部重写时产 >=2 篇新候选（评审 #11），与原 winner 候选池合并评分
    """
    ...
```

### 3.5 literary_jury（基础 3 裁判全评 12 维；分歧升级轮支持 5 裁判，评审 #4 修订 / P0-1 / P0-4）

```python
# jury/literary_jury.py
def weight_map(intensity_5d: dict[str, int]) -> dict[str, float]:
    """
    5 维强度配比 → 12 维加权权重（评审 P0-1 形式化，winner 选择的数学基础）。
    输入：{"画面":0-10,"节奏":0-10,"对话":0-10,"结构":0-10,"悬疑":0-10}（来自 scene_contract.persona_assignment.intensity）
    输出：12 维权重，和为 1.0，文学基础维有非零下限（>=0.05）防"零权重维度被忽略"。

    映射规则：
    - 直接对应维（取强度归一化值）：画面→scene_visual, 节奏→rhythm_pacing, 对话→dialogue_subtext, 悬疑→suspense_tension
    - 结构维：结构→structure_landing(1.0) + chapter_continuity(0.5)  # 结构落地+章续衔接同源
    - 悬疑维（附加）：悬疑→info_gap_lifecycle(章级,0.5)  # 悬疑紧张+信息差章级生命周期同源
    - 文学基础维（固定基准 0.5，非零下限）：language_texture/emotional_progression/character_believability 各 0.5
    - 跨 shot 维（固定基准 0.5）：reading_fluency/motif_theme_fit 各 0.5
    - 创意边界维（固定基准 0.3）：creative_boundary 0.3

    归一化：weight[d] = (raw[d] + BASE[d]) / Z, Z = Σ(raw[d']+BASE[d'])
    保证文学基础维 BASE>=0.5 → 即便某强度为 0，该维权重 >= 0.5/Z > 0.05。
    """
    ...

def score_and_select_winner(shot_id: str, run_id: int) -> DraftSpec:
    """
    方案 B：基础轮（jury_round=1）3 裁判都评全部 12 维，每维去 1 高 1 低取中位数
    （3 样本 trimmed mean 退化为 median，评审 P0-1 已诚实声明），再按契约 5 维强度加权。
    若 judge_disagreement_max 超阈值，则开启升级轮（jury_round>1），使用 escalated_jury_count 个裁判重评，
    jury_aggregates 使用升级轮结果。
    - 裁判模型池从 writing_projects.jury_model_pool 读（基础轮排除 writer_model 后 >=3 个异模型；升级轮排除 writer_model 后 >= escalated_jury_count 个异模型）
    - **按 draft 动态排除写手模型（评审 P0-4）**：为每个 draft 选 3 裁判时，
      从 jury_model_pool 中排除产出该 draft 的 writing_drafts.writer_model，
      保证"裁判模型 ≠ 产出该 draft 的写手模型"（粒度按 draft，非按 shot）。
      配置层优先要求两池无交集；若供应商有限导致两池有重叠，则必须保证排除该 draft 的 writer_model 后仍至少 3 个 jury model。
    - 基础轮 3 裁判各有"主视角"（prompt 强调主视角维度详细 reasoning，非主视角快速评分）：
      * 裁判1（text 主视角）: 画面/节奏/对话/悬疑
      * 裁判2（literary 主视角）: 语言/情感/人物/结构
      * 裁判3（cross_shot 主视角）: 可读/母题/章续/创意边界
    - 每个裁判都填全部 12 维（NOT NULL + CHECK 0-100），基础轮每维有 3 个分数，升级轮每维有 escalated_jury_count 个分数
    - 落库后应用层断言：每 draft 每 jury_round 行数等于该轮裁判数且 judge_model 去重（DB CHECK 无法表达"恰好 N 行"，post-write 校验）
    - 低分维度硬筛选（某维 3 裁判均分 < dimension_floor 的 draft 淘汰，不允许降权后胜出）
    - 基础轮每维去 1 高 1 低 → 中位数（3 样本退化为 median，aggregates 列名 *_median 反映真实算法）；升级轮用同样的 trim 策略按裁判数取中位/截尾均值
    - 12 维按 weight_map(intensity_5d) 加权 → final_score
    - quality floor 硬门禁：final_score >= shot_quality_floor、所有核心维度 >= dimension_floor、judge_disagreement_max <= 阈值或升级轮通过、合格候选 >=2
    - 只有通过 quality floor 的最高分 draft 可 is_winner=1；否则补写，耗尽预算则 shot failed
    - raw 分落 jury_raw_scores（UNIQUE(draft_id,jury_round,judge_model) 防重复；writer_model != judge_model 由 dispatch 动态排除 + trigger + JOIN 审计），median+质量门禁+加权结果落 jury_aggregates
    - 创意 shot 的 creative_boundary 维度：裁判3 参考 JuryInput.deviant_reference 评分
    """
    ...
```

**P0-1 单元测试（M4 必补）**：`assert weight_map(悬疑 shot)["suspense_tension"] > weight_map(过渡 shot)["suspense_tension"]`

### 3.5a polish_revision（winner 后强制精修）

```python
# pipeline/polish_orchestrator.py
def polish_winner(shot_id: str, run_id: int) -> int:
    """
    winner 不能直接 soft_sealed。必须进入 polish_revision：
    - 只允许局部润色，不允许新增事实、不允许改变 must_land、不允许改变 POV/scene_contract。
    - 输入必须包含 QualityReport.productive_deviations 与 neutral_issues。
    - productive_deviations 是保护清单：不得删除有效粗粝、角色声线、留白、非常规节奏。
    - neutral_issues 只允许标注给 review，不得在无人类裁决时自动磨平。
    - polish 调用经 LLMGateway(call_type='polish')，落 ai_call_attempts/runtime_events。
    - polish 使用 smart 模型；smart 不可用时阻断，不降级到 fast/balanced。
    - 生成新 revision 或 draft 后，重新跑 hard_gate1、hard_gate2、quality floor。
    - 通过后才 transition('polish_revision','soft_sealed')；失败则保持 polish_revision 并要求 revise/reject 或 failed。
    """
    ...
```

**质量硬门禁测试（M4/M5 必补）**：
- `final_score < shot_quality_floor` 不得 `is_winner=1`
- 任一核心维度低于 `dimension_floor` 不得 `quality_gate_passed=1`
- `judge_disagreement_max > threshold` 不得 `quality_gate_passed=1`
- `is_winner=1` 但 `quality_gate_passed=0` 被 DB CHECK 拦截
- winner 未经过 `polish_revision` 不得 `soft_sealed`
- `QualityReport` 必须包含 `evidence_class` 与 `defect_class`；缺失时报 schema error
- `would_continue_reading_score < reader_pull_floor` 或 `blind_review_passed=False` 不得 `quality_gate_passed=1`
- `productive_deviations` 在 polish 后必须仍可定位；被删除或被磨平时报 `ProductiveDeviationLostError`
- `smart_model_required=True` 的文学体验评审、盲评排序、返工指导、polish 不得降级执行

### 3.5b shot_status 14 态合法转移矩阵（评审 P0-2 + 质量硬门禁）

`writing_shots.status` 14 态，合法转移由下表穷举（未列出的 prev→next 一律非法，`transition()` 抛 `IllegalTransitionError`）。对照 information_gap 的 transition 模式（见 §2.6 information_gaps 的 CASE CHECK）。

| prev \ next | pending | outline_draft | outline_confirmed | task_card_compiled | prompt_compiled | drafting | hard_gate1 | hard_gate2 | jury_scoring | winner_selected | polish_revision | soft_sealed | hard_sealed | failed |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pending | — | ✓ | | | | | | | | | | | | ✓ |
| outline_draft | | — | ✓ | | | | | | | | | | | ✓ |
| outline_confirmed | | | — | ✓ | | | | | | | | | | ✓ |
| task_card_compiled | | | | — | ✓ | | | | | | | | | ✓ |
| prompt_compiled | | | | | — | ✓ | | | | | | | | ✓ |
| drafting | | | | | | — | ✓ | | | | | | | ✓ |
| hard_gate1 | | | | | | | — | ✓ | | | | | | ✓ |
| hard_gate2 | | | | | | | | — | ✓ | | | | | ✓ |
| jury_scoring | | | | | | | | | — | ✓ | | | | ✓ |
| winner_selected | | | | | | | | | | — | ✓ | | | ✓ |
| polish_revision | | | | | | | ✓ | | | | — | ✓ | | ✓ |
| soft_sealed | | | | | | | | | | | | — | ✓ | |
| hard_sealed | | | | | | | | | | | | | —（终态） | |
| failed | | | | | | | | | | | | | | —（终态） |

**终态不可恢复**：`hard_sealed`、`failed` 为终态，无出边（`failed` 不允许 `→pending` 重试，需新建 run_id 重跑，旧 failed shot 留档审计）。`winner_selected → polish_revision → soft_sealed → hard_sealed` 是唯一前进路径。`soft_sealed` 不允许回退到 `winner_selected`；若软封板后发现问题，必须通过 `revise/reject` 新建 run。

**失败汇聚**：任一非终态遇硬故障（LLM 预算耗尽 P0-5 / 不可重试错误 / 人工 abort）→ `failed`。`transition(prev,'failed')` 对所有非终态 prev 合法。

**transition 函数契约（乐观锁 CAS）**：
```python
# core/state_machine.py
LEGAL_TRANSITIONS: set[tuple[str,str]] = { ... }  # 上表 ✓ 项

def transition(shot_id: str, run_id: int, prev: str, next_: str) -> None:
    """原子推进 shot_status。乐观锁 CAS：UPDATE ... WHERE status=? 断言 affected_rows=1。
    - (prev, next_) 不在 LEGAL_TRANSITIONS → raise IllegalTransitionError
    - WHERE status=prev 命中 0 行（已被并发改）→ raise ConcurrentModificationError（不自动重试，交上层）
    - 成功后更新 updated_at（评审 #28 状态机变更时间）
    失败/终态检查：if prev in {'hard_sealed','failed'}: raise TerminalStateError。"""
    sql = "UPDATE writing_shots SET status=:next, updated_at=:now WHERE shot_id=:id AND run_id=:rid AND status=:prev"
    # affected_rows != 1 → 抛对应异常
```

**N=2 winner 翻盘流程（评审 P0-2，评审 #6 N=2 细化）**：soft gate 累积 N=2 触发局部重写，原 winner 候选池与新候选合并重评，原 winner 可能被翻盘。该流程只允许在 `winner_selected` 状态运行，进入 `polish_revision` 或 `soft_sealed` 后不得回退。流程（单事务内）：
1. soft gate 判定某维度 N=2 → `redo_in_progress=1`（status 仍为 `winner_selected`）
2. 产 ≥2 篇新候选 draft（新 draft_id），与原 winner 候选池合并
3. 重跑 jury_scoring（新 draft 的 raw_scores + aggregates）
4. **翻盘**：若新某 draft 的 final_score > 原 winner → 事务内翻转：
   - `UPDATE writing_jury_aggregates SET is_winner=0 WHERE draft_id=原winner`
   - `UPDATE writing_jury_aggregates SET is_winner=1 WHERE draft_id=新winner`（唯一索引保证仅 1 行）
   - `writing_soft_gate_counters` 对应维度 N 清零（翻盘后该维度重新计数）
5. `redo_in_progress=0`，继续 soft gate 链
6. 若新候选未翻盘（原 winner 仍最高）→ 原 winner 保持，N 不清零（继续累积；质量类 N=3 触发 QUALITY_BLOCKING，不降级放行）

**不变量**：(1) `is_winner` 唯一索引保证同 shot_id 恰 1 winner；(2) 翻盘是事务内原子翻转，无中间态可见；(3) `redo_in_progress=1` 期间 status 不前进到 `polish_revision` / `soft_sealed` / `hard_sealed`（gate_orchestrator 检查）。

### 3.6 resume 崩溃恢复（评审 #5/#6/#17，新增）

```python
# core/resume.py
class ResumeManager:
    """崩溃恢复：根据 shot_status 映射到 resume 动作（评审 #5）。"""

    # shot_status 14 态 → resume 行为映射矩阵
    RESUME_MAP = {
        # done 类：skip
        'soft_sealed': 'skip',
        'hard_sealed': 'skip',
        'failed': 'skip',
        # generating 类：幂等重跑（shot_id+run_id 去重已落库行）
        'drafting': 'rerun_drafting',        # 已落库 draft 按 (shot_id, run_id) 幂等去重
        'hard_gate1': 'rerun_hard_gate1',    # 已落库 eligibility 幂等去重
        'hard_gate2': 'rerun_hard_gate2',
        'jury_scoring': 'rerun_jury',        # 已落库 raw_scores 按 (draft_id, judge_model) 幂等去重（P0-4）
        'winner_selected': 'rerun_winner_select',
        'polish_revision': 'rerun_polish_and_quality_gate',
        # pre-drafting 类：重跑，靠 superseded_at 幂等
        'outline_draft': 'rerun_outline',
        'outline_confirmed': 'rerun_outline',
        'task_card_compiled': 'rerun_task_card',
        'prompt_compiled': 'rerun_prompt',
        'pending': 'start_from_scratch',
    }

    def resume_shot(self, session_id: int, shot_id: str, run_id: int) -> str:
        """读 writing_shots.status，返回 resume 动作。
        session_id 必传，禁止自动选择最新 session（B44）。
        特殊处理 redo_in_progress（评审 #6）：
        - redo_in_progress=1 且无新候选 draft → 重跑局部重写
        - redo_in_progress=1 且有新候选但无新评分 → 重跑评分
        """
        ...

    def parse_resume_point(self, resume_point: str) -> dict:
        """resume_point 结构化 JSON：{phase, chapter_id, dimension_index}。
        phase ∈ {'outline','drafting','jury','polish','soft_gate','chapter_review','book_check'}
        chapter_id：崩溃时所在章
        dimension_index：若崩溃在多维度步骤（如 jury 12 维），指向具体维度"""
        ...
```

**N 计数崩溃恢复**（评审 #6）：
- `writing_soft_gate_counters` 每次 soft gate 判定后立即原子累加（非封版时才落）
- `SoftGateCounter` 无状态读 DB，崩溃不丢
- N 绑 `logical_shot_id + gate_name`（跨 run 累积）：同一 logical shot 重跑计数延续

### 3.6a DecisionSession 与主编台交互（v1.1 产品化扩展）

`DecisionSession` 是自然语言交互的持久化状态机，用于防止 AI 理解、作者确认和程序写库之间漂移。它是主编台交互层的核心，不替代 `writing_human_decisions`；只有 `confirmed` 的 DecisionSession 才能产生正式 human decision 和 contract changelog。

**角色边界**：

- `WorkflowConductor`：薄调度层，只读取状态并选择下一步角色，不直接写契约、正文或 canonical。
- `DecisionSessionHost`：保存 human_text、AI parsed patch、readback_text、状态和恢复点。
- `ContractSteward`：管理契约版本、source hash、confirmed/locked/superseded 状态。
- `Gatekeeper`：校验 AI patch 的 schema、来源覆盖、上下层冲突、stale 和状态机合法性。
- `CanonicalKeeper`：只接受已确认契约与 accepted 正文，不读取聊天内容。
- `AuditLedger`：追加记录 AI 调用、human decision、contract changelog、runtime event、失败原因。

**状态机**：

```python
DECISION_SESSION_TRANSITIONS = {
    "collecting": {"ai_parsed", "cancelled"},
    "ai_parsed": {"awaiting_confirm", "needs_human", "retryable_failed", "cancelled"},
    "awaiting_confirm": {"confirmed", "collecting", "cancelled", "stale"},
    "needs_human": {"collecting", "cancelled"},
    "retryable_failed": {"ai_parsed", "needs_human", "cancelled"},
    "stale": {"collecting", "cancelled"},
    "confirmed": set(),
    "cancelled": set(),
}
```

**最小投影字段**（v1.1 schema revision 再落正式 DDL，不混入当前 40 表基线）：

```python
@dataclass(frozen=True)
class DecisionSession:
    decision_session_id: int
    project_id: int
    scope_type: Literal["book", "volume", "part", "chapter", "shot", "review", "import"]
    scope_id: str | None
    target_type: str
    target_id: str | None
    status: str
    human_text: str
    parsed_patch_json: str
    readback_text: str
    source_hashes_json: str
    before_hash: str | None
    after_hash: str | None
    created_at: str
    updated_at: str
```

**写入规则**：

1. AI 只能返回结构化 patch，不得直接写 SQL 或生产表。
2. 同一 target 同时只能有一个 active DecisionSession。
3. `awaiting_confirm` 恢复时必须回读 `readback_text`，不得依赖聊天上下文。
4. source hash 变化后，DecisionSession 转 `stale`，不得直接确认。
5. 作者裸 "确认" 只有在当前唯一 `awaiting_confirm` 会话存在时有效。
6. `confirmed` 必须在单事务内写入 `writing_human_decisions`、`writing_contract_changelog`、新契约版本/source hash，并把 DecisionSession 置为终态。
7. 任一写入失败必须整体回滚，不允许出现 human decision 已写但契约未更新的半状态。

**ScopedDecisionSession**：

局部修订必须带作用域，不能偷改上层契约：

```python
@dataclass(frozen=True)
class ScopedDecisionPatch:
    scope_type: Literal["book", "volume", "part", "chapter", "shot"]
    scope_id: str | None
    base_contract_version: str
    change_type: Literal["refine", "override", "split", "defer", "reject"]
    affected_scopes_json: str
    stale_downstream_json: str
    patch_json: str
```

下游 stale 规则：局部契约变更后，依赖旧契约的 prompt snapshots、drafts、reviews 必须标记 stale 或新建 run；已 accepted 正文只允许通过 revise run 修改。

### 3.7 并发模型与隔离边界（评审 P0-2，新增）

**当前假设（单 session 串行）**：
- 一个 `writing_sessions` 同时只跑一个 shot 流水线（gate_orchestrator 串行推进 pending→...→hard_sealed），无同一 session 内多 shot 并发。
- 多 `writing_sessions`（多 run）隔离靠 `shot_id = {logical}@{run}` 天然隔离——不同 run 的同 logical shot 是不同行，互不干扰。
- resume 串行：崩溃恢复由单进程 `ResumeManager` 串行扫描 crashed session，无并发 resume。

**乐观锁 CAS（防并发改同一行）**：
- 所有 `writing_shots.status` 推进走 `transition()`（§3.5a），`UPDATE ... WHERE status=:prev` 断言 `affected_rows=1`，并发改抛 `ConcurrentModificationError`。
- `writing_jury_aggregates.is_winner` 翻转走事务内 `UPDATE ... WHERE is_winner=1` + `UPDATE ... WHERE draft_id=:new`，唯一索引兜底。
- `redo_in_progress` 翻转同样 CAS：`UPDATE writing_shots SET redo_in_progress=1 WHERE shot_id=? AND redo_in_progress=0`。

**未来多 worker（advisory lock 预留）**：
- 当前 SQLite 单写者，无需 advisory lock。未来若多进程 worker 并发消费多 shot（不同 logical shot 并行），需 `pg_advisory_xact_lock(hashtext(shot_id))`（迁移 PostgreSQL 后）保证同 shot 串行、不同 shot 并行。
- 预留接口：`gate_orchestrator.acquire_shot_lock(shot_id)` 当前 no-op（单 session 假设），未来填 advisory lock 实现，业务代码不变。

**隔离边界诚实声明**：
- session 间隔离是 DB 行级隔离（不同 run_id 不同行），非进程级隔离。
- 同 session 内多 shot 并发**不支持**（gate_orchestrator 串行设计），若强行并发跑会破坏 N 计数/redo 状态机一致性。
- 跨 session 的同 logical shot 并发（两个 run 同时跑同一章）允许，但 N 计数绑 logical_shot_id 会有竞态——`SoftGateCounter` 的 `UPDATE ... SET count=count+1` 是原子累加，但"读 N 决策"与"写 N"非原子，极端情况两 run 同时读到 N=1 同时写 N=2 都触发 N=2 动作。缓解：N=2 动作幂等（局部重写产新 draft，重复触发只是多产几篇候选，jury 仍选最优）；质量类 N=3 不降级放行，重复触发只会重复产生 blocking failure attribution。

### 3.8 checkpoint 崩溃恢复幂等性设计（评审 P1，新增）

**设计目标**：保证崩溃恢复的可靠性和一致性，避免因 checkpoint 损坏导致恢复失败或数据不一致。

**核心机制**：

```python
# core/checkpoint_manager.py
class CheckpointManager:
    """Checkpoint 写入与恢复，保证幂等性和完整性。"""

    def save_checkpoint(self, session_id: int, phase: str, payload: dict,
                       run_id: int = None, shot_id: str = None) -> int:
        """原子写入 checkpoint（payload + checksum 同事务）。

        1. 序列化 payload 为 JSON
        2. 计算 SHA-256(payload_json)
        3. 在同一事务内 INSERT payload + checksum
        4. 清理旧 checkpoint（保留 checkpoint_max_retention 个）
        """
        payload_json = json.dumps(payload, sort_keys=True, ensure_ascii=False)
        checksum = hashlib.sha256(payload_json.encode('utf-8')).hexdigest()

        with db.transaction():
            checkpoint_id = db.execute("""
                INSERT INTO writing_session_checkpoints
                (session_id, run_id, shot_id, phase, checkpoint_payload, payload_checksum, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (session_id, run_id, shot_id, phase, payload_json, checksum, now()))

            # 清理旧 checkpoint，保留最近 N 个
            retention = db.fetchone("""
                SELECT checkpoint_max_retention FROM writing_projects
                WHERE project_id = (SELECT project_id FROM writing_sessions WHERE session_id = ?)
            """, (session_id,))[0]

            db.execute("""
                DELETE FROM writing_session_checkpoints
                WHERE session_id = ? AND checkpoint_id NOT IN (
                    SELECT checkpoint_id FROM writing_session_checkpoints
                    WHERE session_id = ? ORDER BY created_at DESC LIMIT ?
                )
            """, (session_id, session_id, retention))

        return checkpoint_id

    def load_latest_valid_checkpoint(self, session_id: int) -> tuple[int, dict] | None:
        """加载最新的有效 checkpoint（校验 checksum）。

        1. 按 created_at DESC 遍历 checkpoint
        2. 对每个 checkpoint 计算 payload_checksum，与存储值比对
        3. 匹配则返回 (checkpoint_id, payload)
        4. 不匹配则记录 runtime_event（CHECKPOINT_CORRUPTED），继续检查下一个
        5. 全部损坏则返回 None，触发从头恢复
        """
        checkpoints = db.fetchall("""
            SELECT checkpoint_id, checkpoint_payload, payload_checksum, phase
            FROM writing_session_checkpoints
            WHERE session_id = ?
            ORDER BY created_at DESC
        """, (session_id,))

        for cp in checkpoints:
            computed = hashlib.sha256(cp.checkpoint_payload.encode('utf-8')).hexdigest()
            if computed == cp.payload_checksum:
                payload = json.loads(cp.checkpoint_payload)
                return (cp.checkpoint_id, payload)
            else:
                # 记录损坏事件
                db.execute("""
                    INSERT INTO writing_runtime_events
                    (project_id, session_id, event_type, event_payload, created_at)
                    VALUES (?, ?, 'CHECKPOINT_CORRUPTED', ?, ?)
                """, (
                    db.fetchone("SELECT project_id FROM writing_sessions WHERE session_id=?", (session_id,))[0],
                    session_id,
                    json.dumps({"checkpoint_id": cp.checkpoint_id, "expected": cp.payload_checksum, "actual": computed}),
                    now_utc_iso()
                ))

        return None  # 全部损坏，从头恢复
```

**幂等性保证**：

1. **写入幂等**：checkpoint 写入靠 `(session_id, phase, created_at)` 唯一标识，重复写入只是新增一行，不影响已有数据。
2. **恢复幂等**：`ResumeManager` 的 `RESUME_MAP` 保证同一状态多次恢复结果一致（§3.6）。
3. **损坏检测**：payload_checksum 检测部分写入、磁盘错误、内存损坏等情况。

**恢复流程**：

```python
def resume_session(session_id: int):
    """崩溃恢复完整流程。"""
    cp_mgr = CheckpointManager()
    resume_mgr = ResumeManager()

    # 1. 尝试加载最新有效 checkpoint
    result = cp_mgr.load_latest_valid_checkpoint(session_id)

    if result:
        checkpoint_id, payload = result
        # 2. 从 checkpoint 恢复
        phase = payload['phase']
        shot_id = payload.get('shot_id')
        run_id = payload.get('run_id')
        logger.info(f"Resuming from checkpoint {checkpoint_id}, phase={phase}")
    else:
        # 3. 无有效 checkpoint，从头扫描 shot_status
        logger.warning("No valid checkpoint found, scanning shot_status")
        phase = None
        shot_id = None
        run_id = None

    # 4. 扫描所有 shot，按 RESUME_MAP 恢复
    shots = db.fetchall("""
        SELECT s.shot_id, s.status, s.run_id
        FROM writing_shots s
        JOIN writing_runs r ON r.run_id = s.run_id
        WHERE r.session_id = ?
    """, (session_id,))

    for shot in shots:
        action = resume_mgr.RESUME_MAP.get(shot.status, 'skip')
        if action != 'skip':
            resume_mgr.execute_resume_action(shot.shot_id, shot.run_id, action)
```

**审计与监控**：

- `CHECKPOINT_CORRUPTED` 事件记录到 `writing_runtime_events`，便于事后分析
- `checkpoint_max_retention` 控制存储大小，默认保留最近 3 个 checkpoint
- 建议生产环境监控 checkpoint 损坏率，超过阈值告警

---

## 4. pyright strict + 字段消费 lint + SQL lint 配置

### 4.1 pyproject.toml

```toml
[tool.pyright]
strict = true
pythonVersion = "3.11"
include = ["src/ink"]
exclude = ["src/ink/contract/generated"]  # 生成代码，由 schema 保证

[tool.ink.codegen]
schema_dir = "src/ink/contract/schemas"
output_dir = "src/ink/contract/generated"
field_usage_lint = true
sql_access_lint = true
```

### 4.2 CI 强制检查

```bash
# .github/workflows/ci.yml（或本地 pre-commit）
- python -m ink.codegen.generate           # 生成 dataclass + unpack() 访问器
- python -m ink.codegen.field_usage_lint   # AST 字段消费检查（ast.Attribute 节点）
- python -m ink.codegen.sql_access_lint    # sqlparse SQL 访问检查（text_repository 物理隔离）
- python -m ink.codegen.state_update_lint  # 只有 state_machine 可更新 writing_shots.status
- python -m ink.codegen.llm_access_lint    # 只有 LLMGateway 可调用供应商 SDK
- pyright --strict                         # 类型检查
- pytest                                   # 测试
```

**全部通过 = 构建通过**。任一失败 = 阻塞合并。

### 4.3 sql_access_lint 边界（评审 medium 细化）

`sql_access_lint.py` 用 sqlparse 解析所有 SQL 执行点，断言：

**白名单**（允许访问 `writing_shot_revisions`）：
- `core/text_repository.py`（铁律 5 唯一入口）
- `migration/`、`schema/`、`tests/`（DDL/migration/test 模块）

**禁止的执行后门**（非白名单模块一律不许出现）：
- `sqlite3.Cursor.execute` / `executescript` / `executemany` 含 `writing_shot_revisions` 表名
- ORM 框架调用（SQLAlchemy `.query(writing_shot_revisions)` / peewee `Model.select()`）——ink 不引入 ORM，全用原生 sqlite3
- 动态构造表名：`'writing_' + table` / `f'writing_{t}'` / `table.replace(...)`——表名必须是字面量 token，否则 lint 报 `DynamicTableNameError`
- f-string 拼接 SQL：`f"SELECT ... WHERE shot_id='{shot_id}'"`——必须用参数化 `?` 占位符，否则报 `StringConcatenatedSqlError`（防 SQL 注入 + 防 lint 绕过）

**元测试（M0 lint 自检）**：`tests/test_sql_access_lint_meta.py` 放入故意违规的样本代码，断言 lint 能检出：
```python
def test_lint_catches_dynamic_table_name():
    # 样本：动态表名，lint 必须报 DynamicTableNameError
    code = "cursor.execute(f'SELECT * FROM writing_{t}')"
    assert lint_violations(code) == ['DynamicTableNameError']

def test_lint_catches_orm_query():
    # 样本：ORM 查 revisions，lint 必须报
    code = "session.query(WritingShotRevision).all()"
    assert lint_violations(code) == ['OrmAccessError']

def test_lint_allows_text_repository():
    # 样本：text_repository.py 内的参数化查询，lint 必须放过
    code = "cursor.execute('SELECT text FROM writing_shot_revisions WHERE shot_id=?', (sid,))"
    assert lint_violations(code, module='core/text_repository.py') == []
```

### 4.4 field_usage_lint 元测试（评审 medium 细化）

`field_usage_lint.py` 的 self-test（M0 必补）：
```python
def test_lint_catches_getattr_dynamic_access():
    # getattr 动态访问，防线 1 必须报
    code = "val = getattr(shot_contract, 'must_land')"
    assert lint_violations(code) == ['DynamicAccessError']

def test_lint_catches_unconsumed_field():
    # 字段在签名但未在函数体 ast.Attribute 引用，必须报
    code = "def f(contract: ShotContract):\n    pass  # contract.must_land 未引用"
    assert lint_violations(code) == ['UnconsumedFieldError:must_land']

def test_lint_allows_unpack_destructure():
    # unpack() 解构所有字段，必须放过
    code = "must_land, anti, scene, persona, soft = contract.unpack()"
    assert lint_violations(code) == []

def test_lint_catches_field_name_in_comment_only():
    # 字段名只在注释出现，不算消费，必须报
    code = "def f(contract: ShotContract):\n    # uses contract.must_land\n    return 1"
    assert lint_violations(code) == ['UnconsumedFieldError:must_land']  # 注释不算 ast.Attribute
```

---

## 5. 下游

- `design-v2.md`：架构设计与铁律
- `pitfall-checklist.md`：踩坑结晶在新架构的落点（含 B29/B44/B92 resume 语义、jury 方案 B 数学修正）
- `migration-plan.md`：从 0 构建的 M0-M6 步骤；M6 联调 ≥6 章；557 旧测试三桶迁移方法论
- `author-workflow-contract.md`：作者可执行工作流与人工确认边界
- `interactive-contract-workflow.md`：主编台、DecisionSession、ScopedDecisionSession 与自然语言交互防漂移机制
- `invariant-traceability.md`：旧 bugfix / 架构决策 / 新测试 / 里程碑阻断矩阵
