# InkFlow v3.16 Phase 1 实现契约 v1.4

> 作用：冻结 P0 阻塞项，并记录当前实现已落地的 DDL / 状态机 / CLI / 模型调用协议。
> 状态：实现对齐版（P0 闭环 + D-25 + ARCH-4/5/10/11/12/13 + CREATIVE-1/2/3 + 分层裁判 + 生产内核硬化第一批）
> 日期：2026-06-17；最近对齐：2026-06-26
> 当前范围：DB3 DDL（38 张业务表 + `_schema_meta` 元表，Schema v17）、状态机/枚举、CLI 命令面、模型调用 JSON 协议、`idempotency_key` 格式、并发控制、Prompt Caching 降级策略、polish 精修链路、留白创意评审策略、模型审计 phase、分层裁判 hard/type/literary 维度
> 当前 P0：以《分流》为单书样本，导入第 1 章 locked human baseline；第 2/3 章链路已验证，当前只能受控试跑。正式生产阻塞项是 canonical accepted truth source、run/shot identity 重构和 accepted-only export。

---

## 0. P0 裁剪目标（2026-06-17 冻结）

P0 的工程目标是验证墨韵能把复杂文学契约执行成连续正文，不是一次实现完整系统。

```text
D:\_Progs\.Story\《分流》
  → .inkflow/inkflow.db
  → 导入第 1 章正文为 locked human_baseline
  → 确认第 1 章 shot 边界
  → 提取风格指纹 / 事实锚点 / 人物声音基线
  → init 多轮交互形成 contract-draft.yaml 并确认元契约
  → setup --chapter 编译单章生产前校准包
  → run --chapter 逐 shot 生成目标章节，通过 L3/L4 后自动导出
  → writer race + jury + gate + revision + checkpoint
  → 章完成报告
  → Chesil read-only 导入 InkFlow DB 到自己的 story.db
```

P0 固定边界：

| 项 | 决策 |
|---|------|
| 项目范围 | 单书闭环，只服务《分流》 |
| run 粒度 | 用户按 chapter 运行，内部按 shot 执行 |
| baseline | 第 1 章作为 `human_baseline` 导入并锁定，墨韵不得自动改写 |
| 生成目标 | 按章生成，严格执行该章 chapter_N_events，只允许补充细节 |
| 人类介入 | init / contract / chapter setup 阶段确认；run 阶段不中断；review 阶段记录判断 |
| Gate 硬停 | L4 必须在 shot finalize 前通过；L3 必须在 session complete / auto export 前通过 |
| 导出边界 | 自动导出只取当前 run 的 done_green/done_yellow 且有 current_revision_id 的正文 |
| 红灯 | best-failed placeholder 不断流 |
| 成本 | 不作为开发和运行约束；记录 usage，但不设成本确认门 |
| 模型 | 每书 `.inkflow/.models` 配置功能与模型候选/兜底关系 |
| Chesil | 只读读取 InkFlow DB 并复制导入；不得回写 InkFlow DB |

P0 不实现：Universe、多项目同步、全书一次生成、完整 voice-calibrate、完整 contract dashboard、Chesil 反向提取契约、成本估算确认门。

### 0.1 下一阶段必须固化的 canonical 规则

当前实现已收紧当前 run 的封板/导出边界，但尚未完成 DB canonical 状态机。下一阶段 v18/schema 迁移必须满足：

1. `review --accept` 产生章节级 accepted/sealed canonical 状态。
2. `review --revise/--reject` 必须使对应章节不可被默认 previous context、事实锚点和导出 selector 当作正式正文。
3. `sessions abort/crash` 后的非正式 revision 只能用于排障，不进入后续章节上下文。
4. stable logical shot 与 run attempt identity 必须分离，同一章节重写不能复用旧 shot 导致跳过旧正文。

## 1. CLI 命令面（冻结为 `ink <verb>`）

| 命令 | 语义 |
|------|------|
| `ink init <project> [--chapter-file path]` | 全书初始化、导入样章、生成章以上层级契约草稿 |
| `ink setup <project> --chapter <key>` | 单章生产前校准，生成 `.inkflow/chapter-setups/<chapter>.yaml` |
| `ink confirm-contract <project>` | 兼容/内部命令：确认 `contract-draft.yaml` 并写入 confirmed 元契约 |
| `ink import-baseline <project> --chapter <key> --file <path>` | 导入人工样章为 locked baseline |
| `ink review-shots <project> --chapter <key>` | 审核/确认 baseline shot 边界 |
| `ink run <project> --chapter <key> [flags]` | 全自动生产；L3/L4 通过后自动导出 |
| `ink review <project> --chapter <key> --accept/--revise/--reject` | 记录生产后人工验收 |
| `ink repair <project> --red / --yellow` | AI 修红/修黄 |
| `ink resume <session_id>` | 崩溃恢复 |
| `ink sessions list` | 查看所有未完成 Session |
| `ink sessions abort <id>` | 放弃 Session，已生成文本保留 |
| `ink status <project>` | 写作进度查看 |
| `ink contracts <project>` | 契约仪表盘 |
| `ink voice-calibrate <project>` | 声音校准 |
| `ink clone <source> --as <target>` | 跨项目 clone |

### 1.1 `ink run` flags

```
ink run <project> \
  [--shot <shot_id>] \
  [--chapter v01.c01] \
  [--volume 1] \
  [--from v01.c01] \
  [--to v01.c32] \
  [--writer-count 2|3|4] \
  [--resume] \
  [--suggest] \
  [--config key=value ...]
```

P0 固定用法：

```bash
ink import-baseline "分流" --chapter v01.c01 --file "D:\_Progs\.Story\《分流》\正文\V01_第01章_膝盖与螺丝刀·茶与水.md"
ink review-shots "分流" --chapter v01.c01
ink init "分流"
ink confirm-contract "分流"
ink setup "分流" --chapter v01.c03
ink run "分流" --chapter v01.c03 --resume
ink review "分流" --chapter v01.c03 --accept
```

---

## 2. 状态机与枚举

### 2.1 契约生命周期（`contract_status`）

```
draft → human_review → confirmed → locked → repairing → evolving
```

| 状态 | 含义 |
|------|------|
| `draft` | Init 契约草稿编辑中 |
| `human_review` | 等待人类审核 |
| `confirmed` | 人类已确认，尚未 run |
| `locked` | `ink run` 快照已创建 |
| `repairing` | 修复中 |
| `evolving` | 升级中 |

### 2.2 Shot 主状态（`shot_status`）

```
pending → generating → gate1_check → jury_scoring → final_gate → done_green
                                               │              │
                                               │              ├→ done_yellow
                                               │              │
                                               └→ placeholder ──→ redo ──→ done_red_permanent
                                                                   │
                                                                   └→ generating (smart-redo 成功)
```

> 正常路径：generating → gate1_check → jury_scoring → final_gate → done_green（≥85）/ done_yellow（65-84）。`gate1_check` 无可用候选 → 直接进入 `placeholder`。Smart-Redo 成功 → `redo` 回到 `generating`。三级耗尽 → `done_red_permanent`。

| 状态 | 含义 |
|------|------|
| `pending` | 等待生成 |
| `generating` | writer race 进行中 |
| `gate1_check` | L0 + Contract Gate 1 |
| `jury_scoring` | 分层裁判评分（硬规则 → 类型职责 → 文学 9 维） |
| `final_gate` | 最终门控 |
| `done_green` | 绿灯 |
| `done_yellow` | 黄灯 |
| `placeholder` | 红灯占位 |
| `redo` | smart-redo 修复中 |
| `done_red_permanent` | 3 级耗尽 |

### 2.3 Placeholder 类型

```
best_failed_candidate | redo_placeholder | permanent_red
```

### 2.4 灯色/质量标签（正交附加字段）

- `light_status`: `green` | `yellow` | `red`
- `brilliance_level`: `NULL` | `A` | `A+` | `S`
- `badsmell_level`: `NULL` | `B` | `Br` | `Bz`

### 2.5 灯色阈值

| 灯色 | 默认阈值 |
|------|---------|
| `green` | ≥ 85 |
| `yellow` | ≥ 65 且 < 85 |
| `red` | < 65 |

### 2.6 Smart-Redo 级别

| 级别 | 触发条件 | 动作 |
|------|---------|------|
| L0 | Gate 1 不通过 | 重试同 prompt |
| L1 | Gate 1 通过但 Gate 2 不通过，综合分 < 50 | 简化上下文，重跑 |
| L2 | L1 后仍不通过 | 完整 redo，模型从 `redo_model` 读取（默认 `claude-sonnet-4-6`） |

### 2.7 Repair 四层框架（L1-L4）

| 层级 | 名称 | 含义 |
|------|------|------|
| L1 | 零改动 | 不改变契约，仅重试 |
| L2 | 风格级 | 修改软约束，diff 留痕 |
| L3 | 结构级 | 修改 structure_rules/motif_system |
| L4 | 方向级 | 涉及 hard_boundaries，升级到人类决策 |

升级规则：L1 连续 3 次 → L2；L2 连续 3 次 → L3；L3 连续 2 次 → L4。

---

## 3. DB3 DDL（38 张业务表 + `_schema_meta` 元表，Schema v17）

> v17 变更（2026-06-26，分层裁判）：`writing_jury_scores.dimension` 新增 `hard_rule_compliance` 与文学 9 维。Jury 流程变为硬规则 → 类型职责 → 文学 9 维 trimmed mean。类型维度仅在对应 shot_profile 启用。
> v16 变更（2026-06-25，B41）：`model_attempts.phase` 新增 `outline_evaluate`、`constitution_generate`、`architect_chapter_rhythm(_retry)`、`architect_volume_rhythm(_retry)`，避免架构/大纲模型调用审计被 CHECK 约束静默丢弃。
> v15 变更（2026-06-25，CREATIVE-2）：`shot_revisions.operation` 新增 `write_polish`；`model_attempts.phase` 新增 `polish`。winner 后处理精修必须通过 `parent_revision_id` 指向原 winner revision。
> 运行时变更（2026-06-25，CREATIVE-3，无 DDL）：每 5 个 shot 的留白 shot 使用 `creative_review=True`，按 `creative_score` 选稿，提高 `unexpected_value` 权重，同时保留逐维评分审计。
> v14 变更（2026-06-25，CREATIVE-1）：`writing_jury_scores.dimension` 新增 `unexpected_value`，用于奖励“意料之外、情理之中”的有效偏离。
> v13 变更（2026-06-24，ARCH-11）：新增 `writing_anti_contract_reviews` 表，记录反契约沙盒的软约束偏离与人类裁决。
> v12 变更（2026-06-24，ARCH-10）：新增 `writing_style_preferences` 表，`writing_drafts` 增加 `model_ref` / `temperature` / `style_direction`。
> v11 变更（2026-06-24，D-25）：`writing_shots` 新增 `failure_signature_json`，配合重试预算和熔断器。
> v10 变更（2026-06-24，ARCH-5）：新增 `writing_volume_rhythms` 表（L0.5 卷部节奏）。
> v9 变更（2026-06-24，ARCH-4）：新增 `writing_book_constitutions` 表（L0 全书宪法）+ `writing_meta_contract.constitution_version_id` 指针列。
> v8 变更（2026-06-21，ARCH-12）：新增 4 张表支持三棵树架构（`tree_nodes` / `contract_versions` / `story_content` / `execution_records`），详见 `design-3tree-architecture.md`。

### 3.1 约定

- 主键：ULID 格式（`session_id`、`project_id`、`run_id` 等内部 ID）
- **`shot_id`：复合层级格式**（详见 §3.1.1）
- 时间戳：业务表含 `created_at`、`updated_at`；审计/日志/不可变表仅含 `created_at`
- JSON 字段：SQLite JSON1
- 异常事件统一为 `writing_exception_events`

#### 3.1.1 `shot_id` 复合层级格式

继承自 DeepStory 8层金字塔设计（详见 `docs/design-8layer-hierarchy.md`）。

```
格式: {volume}.{chapter}.s{section}
示例: v01.c02.s03
```

| 组件 | 格式 | 示例 |
|------|------|------|
| volume | `v` + 2位数字 | v01 |
| chapter | `c` + 2位数字 | c02 |
| section | `s` + 2位数字 | s03 |

- `layer_key` = `{volume}.{chapter}` (如 `v01.c02`)
- `shot_id` = `{layer_key}.s{shot_index:02d}` (如 `v01.c02.s03`)
- 排序：字典序即可（零填充保证）

### 3.2 核心表 DDL

#### `projects`

```sql
CREATE TABLE projects (
  project_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  universe_id TEXT,                         -- NULL = 独立项目
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','archived')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

> InkFlow 和 Chesil 各自维护独立的数据库。`projects` 表是 InkFlow 内部的项目索引，相关业务表的 `project_id` 均引用或软引用此表。

#### `writing_sessions`

```sql
CREATE TABLE writing_sessions (
  session_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  run_id TEXT NOT NULL UNIQUE,
  act_id TEXT,                              -- 软引用 writing_project_structure.layer_key
  status TEXT NOT NULL CHECK (status IN ('active','paused','completed','aborted','crashed')),
  current_shot_id TEXT,
  completed_shots INTEGER NOT NULL DEFAULT 0,
  total_shots INTEGER,
  escape_used BOOLEAN NOT NULL DEFAULT 0,
  checkpoint_json JSON,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_sessions_project ON writing_sessions(project_id);
CREATE INDEX idx_sessions_status ON writing_sessions(status);
```

#### `writing_session_checkpoints`

```sql
CREATE TABLE writing_session_checkpoints (
  checkpoint_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES writing_sessions(session_id),
  shot_id TEXT NOT NULL,
  checkpoint_json JSON NOT NULL,
  checkpoint_storage_path TEXT NOT NULL DEFAULT '.checkpoints/',
  context_hash TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_checkpoints_session ON writing_session_checkpoints(session_id);
```

> 恢复优先从文件系统加载，DB 作为 fallback。

#### `writing_meta_contract`

```sql
CREATE TABLE writing_meta_contract (
  meta_contract_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL UNIQUE,
  contract_version TEXT NOT NULL DEFAULT '3.6',
  min_runtime_version TEXT NOT NULL DEFAULT '3.6',
  status TEXT NOT NULL CHECK (status IN ('draft','human_review','confirmed','locked','repairing','evolving')),
  upgraded_from TEXT,
  upgraded_at TEXT,
  fields_added_json JSON,
  layers_json JSON NOT NULL,
  human_confirm_layer INTEGER NOT NULL,
  constitution_version_id TEXT REFERENCES writing_book_constitutions(constitution_id),  -- v9: ARCH-4
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `writing_book_constitutions`（v9 新增，ARCH-4 L0 全书宪法）

```sql
CREATE TABLE writing_book_constitutions (
  constitution_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES projects(project_id),
  version INTEGER NOT NULL DEFAULT 1,
  arc_shape TEXT,
  tension_peak_chapter TEXT,
  tension_valley_chapters_json JSON,
  volume_map_json JSON,
  chapter_roles_json JSON,
  motif_lifecycle_json JSON,
  global_deviation_mean REAL,
  global_deviation_range_json JSON,
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','human_review','confirmed','locked')),
  confirmed_at TEXT,
  locked_at TEXT,
  source_outline_hash TEXT,
  llm_model_ref TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(project_id, version)
);
```

#### `writing_meta_contract_revisions`

```sql
CREATE TABLE writing_meta_contract_revisions (
  revision_id TEXT PRIMARY KEY,
  meta_contract_id TEXT NOT NULL REFERENCES writing_meta_contract(meta_contract_id),
  changed_by TEXT NOT NULL CHECK (changed_by IN ('human','ai','upgrade')),
  reason TEXT NOT NULL CHECK (length(reason) >= 50),
  before_json JSON NOT NULL,
  after_json JSON NOT NULL,
  diff_json JSON NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `writing_project_structure`

```sql
CREATE TABLE writing_project_structure (
  structure_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  layer_type TEXT NOT NULL CHECK (layer_type IN ('universe','project','act','volume','chapter','scene')),
  layer_key TEXT NOT NULL,
  parent_layer_key TEXT,
  layer_index INTEGER NOT NULL,
  human_confirm_layer INTEGER NOT NULL,
  metadata_json JSON,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(project_id, layer_key)
);
```

#### `writing_shot_contracts`

```sql
CREATE TABLE writing_shot_contracts (
  contract_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  run_id TEXT NOT NULL,
  shot_id TEXT NOT NULL,
  layer_key TEXT NOT NULL,
  parent_contract_id TEXT REFERENCES writing_shot_contracts(contract_id),
  contract_status TEXT NOT NULL CHECK (contract_status IN ('draft','human_review','confirmed','locked','repairing','evolving')),
  snapshot_hash TEXT NOT NULL,
  must_land_json JSON NOT NULL,
  anti_write_json JSON NOT NULL,
  exit_to_json JSON,
  motif_tasks_json JSON,
  pov_routing_json JSON,
  contract_json JSON NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(run_id, shot_id)
);
```

#### `writing_run_snapshots`

```sql
CREATE TABLE writing_run_snapshots (
  snapshot_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL UNIQUE,
  project_id TEXT NOT NULL,
  meta_contract_id TEXT NOT NULL,
  config_hash TEXT NOT NULL,
  contract_snapshot_hash TEXT NOT NULL,
  snapshot_json JSON NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `writing_shots`

```sql
CREATE TABLE writing_shots (
  shot_id TEXT PRIMARY KEY,           -- 复合格式: v01.c02.s03 (详见 §3.1.1)
  project_id TEXT NOT NULL,
  run_id TEXT NOT NULL,
  layer_key TEXT NOT NULL,            -- v01.c02
  shot_index INTEGER NOT NULL,        -- 3
  shot_status TEXT NOT NULL CHECK (shot_status IN (
    'pending','generating','gate1_check','jury_scoring','final_gate',
    'done_green','done_yellow','placeholder','redo','done_red_permanent'
  )),
  placeholder_type TEXT CHECK (placeholder_type IN ('best_failed_candidate','redo_placeholder','permanent_red')),
  redo_attempt INTEGER NOT NULL DEFAULT 0 CHECK (redo_attempt BETWEEN 0 AND 3),
  light_status TEXT CHECK (light_status IN ('green','yellow','red')),
  brilliance_level TEXT CHECK (brilliance_level IN ('A','A+','S')),
  badsmell_level TEXT CHECK (badsmell_level IN ('B','Br','Bz')),
  source_hard_boundary_index INTEGER,
  context_injection_status TEXT CHECK (context_injection_status IN ('full','warning','summary_only')),
  current_revision_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(run_id, shot_index)
);
```

#### `shot_revisions`

```sql
CREATE TABLE shot_revisions (
  revision_id TEXT PRIMARY KEY,
  shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
  run_id TEXT NOT NULL,
  parent_revision_id TEXT REFERENCES shot_revisions(revision_id),
  contract_id TEXT NOT NULL REFERENCES writing_shot_contracts(contract_id),
  revision_sequence INTEGER NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('write_generate','write_placeholder','write_repair','write_redo','write_polish')),
  text TEXT NOT NULL,
  text_hash_normalized TEXT NOT NULL,
  writer_persona TEXT,
  jury_scores_json JSON,
  gate_result_json JSON,
  is_current BOOLEAN NOT NULL DEFAULT 0,
  attempt_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(shot_id, operation, attempt_id)
);
```

P0 兼容约定：导入人工样章时，`operation='write_generate'` 暂存导入文本，`writer_persona='human_baseline'`，`is_current=1`，并在 `gate_result_json` 写入 `{"locked": true, "source": "human_baseline"}`。后续实现可以把 `operation` 枚举扩展为 `human_baseline`，但 P0 不因枚举扩展阻塞。

#### `writing_drafts`

```sql
CREATE TABLE writing_drafts (
  draft_id TEXT PRIMARY KEY,
  shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
  run_id TEXT NOT NULL,
  writer_persona TEXT NOT NULL,
  writer_index INTEGER NOT NULL,
  text TEXT NOT NULL,
  self_note TEXT,
  gate1_result_json JSON,
  gate2_result_json JSON,
  is_usable BOOLEAN NOT NULL DEFAULT 0,
  attempt_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `writing_shot_prompts`

```sql
CREATE TABLE writing_shot_prompts (
  prompt_id TEXT PRIMARY KEY,
  shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
  run_id TEXT NOT NULL,
  writer_persona TEXT,
  prompt_hash TEXT NOT NULL,
  static_prefix TEXT NOT NULL,
  static_prefix_length INTEGER NOT NULL DEFAULT 0,
  dynamic_assembly_json JSON NOT NULL,
  assembled_prompt TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(run_id, shot_id, writer_persona)
);
```

> `static_prefix` 在 init/setup 阶段预编译；`dynamic_assembly_json` 运行时装配；`static_prefix_length` 用于 Prompt Caching 长度探测。

#### `writing_context_snaps`

```sql
CREATE TABLE writing_context_snaps (
  snap_id TEXT PRIMARY KEY,
  shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
  run_id TEXT NOT NULL,
  context_hash TEXT NOT NULL,
  previous_shots_json JSON NOT NULL,
  fact_anchor_refs_json JSON NOT NULL,
  motif_tracker_state_json JSON NOT NULL,
  anti_samples_json JSON NOT NULL,
  injected_with_warning BOOLEAN NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `writing_fact_anchors`

```sql
CREATE TABLE writing_fact_anchors (
  anchor_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  run_id TEXT,
  shot_id TEXT REFERENCES writing_shots(shot_id),
  anchor_type TEXT NOT NULL CHECK (anchor_type IN (
    'character_state','character_trait','object_location','object_property',
    'event_occurred','relationship','world_rule','timeline','knowledge'
  )),
  anchor_key TEXT NOT NULL,
  anchor_value TEXT NOT NULL,
  confidence REAL NOT NULL CHECK (confidence BETWEEN 0 AND 1),
  pov_scope TEXT DEFAULT NULL,
  override_source TEXT CHECK (override_source IN ('universe','project_override','project_fork')),
  contract_clause_ref TEXT,
  source_revision_id TEXT REFERENCES shot_revisions(revision_id),
  extracted_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(project_id, anchor_key, run_id)
);
```

#### `writing_motif_definitions`

```sql
CREATE TABLE writing_motif_definitions (
  motif_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  name TEXT NOT NULL,
  category TEXT,
  description TEXT,
  planned_density_json JSON NOT NULL,
  variants_json JSON NOT NULL,
  min_shot_gap INTEGER NOT NULL DEFAULT 3,
  mutual_exclusion_json JSON,
  evolution_json JSON,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `writing_motif_instances`

```sql
CREATE TABLE writing_motif_instances (
  instance_id TEXT PRIMARY KEY,
  motif_id TEXT NOT NULL REFERENCES writing_motif_definitions(motif_id),
  project_id TEXT NOT NULL,
  run_id TEXT NOT NULL,
  shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
  variant_used TEXT NOT NULL,
  evolution_phase TEXT NOT NULL CHECK (evolution_phase IN ('establishment','variation','subversion','resolution')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `writing_motif_tracker`

```sql
CREATE TABLE writing_motif_tracker (
  tracker_id TEXT PRIMARY KEY,
  motif_id TEXT NOT NULL REFERENCES writing_motif_definitions(motif_id),
  project_id TEXT NOT NULL,
  run_id TEXT NOT NULL,
  current_count INTEGER NOT NULL DEFAULT 0,
  density_status TEXT NOT NULL CHECK (density_status IN ('green','yellow','blue','red','gray')),
  last_used_shot_id TEXT,
  task_generated_for_shot_id TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(run_id, motif_id)
);
```

#### `writing_writer_profiles`

```sql
CREATE TABLE writing_writer_profiles (
  profile_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  persona_name TEXT NOT NULL CHECK (persona_name IN ('意象师','节奏师','对话师','结构师')),
  model_id TEXT NOT NULL,
  temperature REAL NOT NULL DEFAULT 0.8,
  voice_samples_json JSON,
  anti_samples_json JSON,
  system_prompt_template TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(project_id, persona_name)
);
```

#### `writing_jury_config`

```sql
CREATE TABLE writing_jury_config (
  config_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  base_dimensions_json JSON NOT NULL,
  dynamic_dimensions_json JSON,
  thresholds_json JSON NOT NULL,
  weights_json JSON NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `writing_jury_scores`

```sql
CREATE TABLE writing_jury_scores (
  score_id TEXT PRIMARY KEY,
  draft_id TEXT NOT NULL REFERENCES writing_drafts(draft_id),
  shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
  run_id TEXT NOT NULL REFERENCES writing_sessions(run_id),
  jury_persona TEXT NOT NULL,
  phase TEXT NOT NULL CHECK (phase IN ('independent','comparative','final')),
  dimension TEXT NOT NULL CHECK (dimension IN (
    'literary_quality','narrative_pacing','voice_consistency','contract_compliance',
    'motif_compatibility','anti_pattern_avoidance','hook_transition','character_coherence','reader_engagement',
    'forbidden_expression','reading_fluency','suspense_effectiveness','unexpected_value',
    'hard_rule_compliance','language_texture','scene_specificity','emotional_progression',
    'character_believability','dialogue_subtext','pacing_control','motif_theme_fit','chapter_continuity'
  )),
  score INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
  comment TEXT,
  attempt_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(shot_id, draft_id, jury_persona, phase, dimension, attempt_id)
);
```

#### `writing_repair_audit`

```sql
CREATE TABLE writing_repair_audit (
  repair_audit_id TEXT PRIMARY KEY,
  shot_id TEXT REFERENCES writing_shots(shot_id),
  run_id TEXT NOT NULL,
  contract_id TEXT NOT NULL,
  layer TEXT NOT NULL CHECK (layer IN ('L1','L2','L3','L4')),
  diagnosis TEXT NOT NULL,
  diff_json JSON NOT NULL,
  repair_result_json JSON,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `writing_exception_events`

```sql
CREATE TABLE writing_exception_events (
  event_id TEXT PRIMARY KEY,
  run_id TEXT NOT NULL,
  shot_id TEXT NOT NULL REFERENCES writing_shots(shot_id),
  event_type TEXT NOT NULL CHECK (event_type IN ('unresolvable','escape','drift_alert')),
  reason_json JSON NOT NULL,
  boundary_id TEXT,
  new_direction TEXT,
  resolution_json JSON,
  architect_review_status TEXT CHECK (architect_review_status IN ('pending','approved','rejected','deferred')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `writing_deviation_notes`

```sql
CREATE TABLE writing_deviation_notes (
  note_id TEXT PRIMARY KEY,
  shot_id TEXT REFERENCES writing_shots(shot_id),
  run_id TEXT NOT NULL,
  note_type TEXT NOT NULL CHECK (note_type IN ('intent_drift','contract_violation','human_flag')),
  severity TEXT NOT NULL CHECK (severity IN ('info','warning','critical')),
  content TEXT NOT NULL,
  resolved_at TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

#### `writing_project_config`

```sql
CREATE TABLE writing_project_config (
  config_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL UNIQUE,
  default_preset TEXT NOT NULL DEFAULT 'balanced',
  redo_model TEXT NOT NULL DEFAULT 'claude-sonnet-4-6',
  layers_json JSON NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

P0 约定：`writing_project_config.layers_json` 必须记录 `.inkflow/.models` 的文件 hash、加载时间和解析后的功能模型映射。运行期模型选择以 `.models` 为准，`redo_model` 仅作为兼容字段。

#### `writing_reference_pool`

```sql
CREATE TABLE writing_reference_pool (
  sample_id TEXT PRIMARY KEY,
  project_id TEXT NOT NULL,
  sample_type TEXT NOT NULL CHECK (sample_type IN ('positive','negative')),
  text TEXT NOT NULL,
  annotation TEXT NOT NULL,
  source_shot_id TEXT REFERENCES writing_shots(shot_id),
  review_status TEXT NOT NULL DEFAULT 'pending' CHECK (review_status IN ('pending','approved','rejected')),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### 3.3 Phase 1 最小表集（25 张表，v7 已有）

```
projects
writing_sessions / writing_session_checkpoints / writing_meta_contract
writing_meta_contract_revisions / writing_project_structure
writing_shot_contracts / writing_run_snapshots / writing_shots
shot_revisions / writing_drafts / writing_shot_prompts
writing_context_snaps / writing_fact_anchors
writing_motif_definitions / writing_motif_instances / writing_motif_tracker
writing_writer_profiles / writing_jury_config / writing_jury_scores
writing_repair_audit / writing_exception_events / writing_deviation_notes
writing_project_config / writing_reference_pool
writing_information_gaps / writing_chapter_rhythms  -- v6/v7 新增
```

### 3.4 Schema v8 新增表（ARCH-12，三棵树架构）

> 4 张新表，总表数 27 → 31。完整设计见 `design-3tree-architecture.md`。

#### tree_nodes（骨架，三棵树共用）

```sql
CREATE TABLE tree_nodes (
    node_id         TEXT PRIMARY KEY,
    tree_type       TEXT NOT NULL
                        CHECK (tree_type IN ('contract', 'story', 'execution')),
    project_id      TEXT NOT NULL REFERENCES projects(project_id),
    parent_id       TEXT REFERENCES tree_nodes(node_id),
    layer_key       TEXT NOT NULL,
    node_level      TEXT NOT NULL
                        CHECK (node_level IN ('L0','L1','L2','L3','L4','L5','L6','L7')),
    node_name       TEXT,
    sort_order      INTEGER DEFAULT 0,
    design_status   TEXT DEFAULT 'pending'
                        CHECK (design_status IN
                            ('pending','drafting','review','confirmed','locked')),
    quality_color   TEXT
                        CHECK (quality_color IN ('green','yellow','red','gray',NULL)),
    node_intent     TEXT,
    run_id          TEXT,
    source_version_id TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(tree_type, project_id, layer_key, run_id)
);
CREATE INDEX idx_tree_nodes_parent ON tree_nodes(parent_id);
CREATE INDEX idx_tree_nodes_lookup ON tree_nodes(tree_type, project_id, layer_key);
CREATE INDEX idx_tree_nodes_run    ON tree_nodes(run_id) WHERE run_id IS NOT NULL;
```

#### contract_versions（契约树正文，版本化）

```sql
CREATE TABLE contract_versions (
    version_id        TEXT PRIMARY KEY,
    node_id           TEXT NOT NULL REFERENCES tree_nodes(node_id),
    version           INTEGER NOT NULL,
    parent_version_id TEXT REFERENCES contract_versions(version_id),
    is_collapsed      INTEGER NOT NULL DEFAULT 0,
    contract_body_json JSON NOT NULL,
    change_reason     TEXT,
    created_by        TEXT NOT NULL DEFAULT 'human'
                          CHECK (created_by IN ('human', 'ai', 'upgrade')),
    created_at        TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(node_id, version)
);
CREATE INDEX idx_contract_versions_node ON contract_versions(node_id);
```

#### story_content（故事树正文）

```sql
CREATE TABLE story_content (
    content_id        TEXT PRIMARY KEY,
    node_id           TEXT NOT NULL REFERENCES tree_nodes(node_id),
    content_body_json JSON NOT NULL,
    updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_story_content_node ON story_content(node_id);
```

#### execution_records（执行树正文）

执行树不存正文本身。正文唯一真相源始终是 `shot_revisions.text`。`execution_records.revision_id` 是指向 `shot_revisions` 的指针，使执行树成为"正文的访问路径"。

```sql
CREATE TABLE execution_records (
    record_id          TEXT PRIMARY KEY,
    node_id            TEXT NOT NULL REFERENCES tree_nodes(node_id),
    run_id             TEXT NOT NULL,
    prompt_snapshot_id TEXT,
    draft_ids_json     JSON,                -- 4 份草稿 ID 列表
    selected_draft_id  TEXT,                -- jury 选中的草稿
    revision_id        TEXT REFERENCES shot_revisions(revision_id),
    quality_result_json JSON,
    created_at         TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_execution_records_node ON execution_records(node_id);
CREATE INDEX idx_execution_records_run  ON execution_records(run_id);
```

**正文真相源规则**：
- **未封版**：正文 = `shot_revisions` 中 `revision_sequence` 最大的行（最后一次生成的）
- **已封版**：正文 = `shot_revisions` 中 `is_current=1` 的行（封版锁定的版本）
- `is_current` 是封版标记，一旦设置就不再随新生成而更新
- 执行树通过 `revision_id` 提供访问路径，但不复制正文

---

## 4. 模型调用 JSON 协议

### 4.0 `.models` 文件

每个 InkFlow 项目必须有项目级模型配置：

```text
{project_root}/.inkflow/.models
```

格式使用 YAML。字段含义：

```yaml
architect:
  primary: claude-opus-4-6
  candidates:
    - claude-sonnet-4-6
  fallback: gpt-5

writer:
  primary: claude-sonnet-4-6
  candidates:
    - gpt-5
  fallback: local-default

jury:
  primary: claude-sonnet-4-6
  candidates:
    - gpt-5
  fallback: claude-haiku-4-6

fact_anchor:
  primary: claude-sonnet-4-6
  candidates:
    - gpt-5-mini
  fallback: local-default

repair:
  primary: claude-opus-4-6
  candidates:
    - claude-sonnet-4-6
  fallback: gpt-5
```

选择规则：

```text
1. 按功能读取 primary。
2. primary 不可用时按 candidates 顺序尝试。
3. candidates 全部不可用时使用 fallback。
4. 成本不参与选择，不触发人工确认。
5. 每次模型选择结果写入 attempt 记录和 usage。
```

### 4.1 Writer Race 请求

```json
{
  "attempt_id": "<ulid>",
  "idempotency_key": "{run_id}:{snapshot_hash}:{shot_id}:writer:{writer_index}:0",
  "model_id": "claude-sonnet-4-6",
  "messages": [
    {"role": "system", "content": "[STATIC_PREFIX]"},
    {"role": "user", "content": "[DYNAMIC_ASSEMBLY]"}
  ],
  "max_tokens": 6000,
  "temperature": 0.8
}
```

### 4.2 Writer Race 响应

```json
{
  "attempt_id": "<ulid>",
  "text": "...",
  "self_note": "...",
  "finish_reason": "stop|length|content_filter",
  "usage": {"prompt_tokens": 2400, "completion_tokens": 3200}
}
```

### 4.3 Jury 评分（v17 分层裁判）

当前实现按候选稿、评委模型和评分维度逐项记录分数，但评分流程分三层：

1. **硬规则裁判**：`hard_rule_compliance`。规则预检失败时直接淘汰；远端 jury 可追加 LLM hard-rule check，但只能清零硬事实、must_land、POV、禁写、提前揭示、前文冲突、空文/重复、提示词残留等致命问题。段落长度、方言点缀、感官密度、身体时刻开场和 `characters_alive` 被误读为唯一角色名单，均不得作为硬规则清零依据。
2. **类型裁判**：只在 shot_profile 启用对应职责时打分。悬疑 shot 打 `suspense_effectiveness`；留白/创意入口打 `unexpected_value`；章末/转折打 `hook_transition`。
3. **文学裁判**：固定 9 维：`language_texture` / `reading_fluency` / `scene_specificity` / `emotional_progression` / `character_believability` / `dialogue_subtext` / `pacing_control` / `motif_theme_fit` / `chapter_continuity`。

文学分计算：先对每个文学维度求均值，再从 9 个维度均值中去掉最高 1 个和最低 1 个，对剩余 7 个取平均，得到 `literary_score`。winner 只从硬规则和类型职责都通过的稿件中选择。

通过条件：默认 `quality_threshold=80`，也可用 10 分制配置（如 `8.5` 自动换算为 85）。默认 `min_passing_drafts=2`，过线候选稿少于 2 个时触发重写，避免“矮子里拔高个”。

配置兼容规则：旧 `.models` 的 `jury_config.dimensions` 不再注入新文学 9 维，避免旧合规维度污染文学均分；新配置若需调整文学维度，使用 `jury_config.literary_dimensions`。

章节生产准入规则：`ink setup --chapter` 生成的 setup 包必须匹配当前目标章节和当前元契约；`ink run --chapter` 在创建 session 前检查 setup 包的 `source_contract.meta_contract_id`、shot 数和当前 `chapter_N_events`。若元契约还含“只生成第 N 章”这类旧章节限定，或保留旧段落锁 `500-800 字/段落，3-4 段/shot`，生产必须在 setup/run 前失败，不能拖到远端 jury 阶段表现为全 0。

```json
{
  "attempt_id": "<ulid>",
  "idempotency_key": "{run_id}:{snapshot_hash}:{shot_id}:jury_score:{jury_index}:0",
  "phase": "independent",
  "jury_persona": "评委_deepseek-v4-pro",
  "dimension": "language_texture",
  "draft_text": "...",
  "contract_snapshot": {...}
}
```

每个维度写入 `writing_jury_scores`。当前代码保留 `phase='independent'` 记录；比较/最终阶段枚举保留给后续扩展。

### 4.4 Jury 评分响应

```json
{
  "attempt_id": "<ulid>",
  "phase": "independent",
  "scores": [
    {"dimension": "unexpected_value", "score": 88, "comment": "..."}
  ],
  "brilliance_markers": [],
  "badsmell_markers": []
}
```

> 分数统一为 0-100。旧 9 维枚举仍被 DDL 接受以兼容历史数据；当前默认使用 v17 hard-rule + 文学 9 维。类型维度只在 shot_profile 启用时写入。

### 4.5 通用错误响应

```json
{
  "attempt_id": "<ulid>",
  "error": true,
  "error_code": "rate_limit|timeout|bad_request|auth|unknown",
  "retryable": true,
  "message": "..."
}
```

---

## 5. `idempotency_key` 格式

### 5.1 格式

```
{run_id}:{snapshot_hash}:{shot_id}:{phase}:{index}:{attempt}
```

`snapshot_hash` 取自 `writing_run_snapshots.contract_snapshot_hash`。

### 5.2 `phase` 枚举

| phase | 含义 | index 语义 |
|------|------|-----------|
| `write_generate` | writer race / redo 生成 | writer_index: 0-3 |
| `jury_score` | 评委评分 | jury_index: 0-14（默认 3 模型 × 5 维） |
| `fact_extract` | 事实锚点提取 | extractor_index: 0 |
| `repair` | repair 调用 | repair_layer: 1-4 |
| `motif_task` | 意象任务生成 | index: 0 |
| `contract_compile` | 契约编译 | index: 0 |
| `prompt_compile` | prompt 编译 | index: 0 |
| `polish` | winner 后处理精修 | index: 0 |
| `outline_evaluate` | 大纲评估 | index: 0 |
| `constitution_generate` | L0 全书宪法生成 | index: 0 |
| `architect_chapter_rhythm` | L1 章级节奏生成 | index: 0 |
| `architect_chapter_rhythm_retry` | L1 章级节奏重试 | index: retry |
| `architect_volume_rhythm` | L0.5 卷部节奏生成 | index: 0 |
| `architect_volume_rhythm_retry` | L0.5 卷部节奏重试 | index: retry |

### 5.3 示例

```
run_01j7k2v:snap_a1b2c3:act1_ch3_s37:write_generate:0:0
run_01j7k2v:snap_a1b2c3:act1_ch3_s37:jury_score:4:1
```

---

## 6. 并发控制

SQLite 写操作串行化。赛车场经理主循环使用单线程 + `asyncio.Queue`。事务模式：`BEGIN IMMEDIATE`。Scene Composition Check 和 Intent Drift Detection 在 Shot 完成后同步执行。

---

## 7. Prompt Caching 降级策略

init/setup 阶段测量 `static_prefix_length`：
- `<= 4096`：正常使用 Anthropic Prompt Caching（3 breakpoint）
- `> 4096`：拆分缓存段，仍超限时压缩为摘要模式
- 动态部分（Previous Shots / Fact Anchors / Motif Tracker）不缓存

---

## 8. 与上游文档的冲突裁决

| 冲突点 | 裁决 |
|--------|------|
| CLI 命名 | 统一为 `ink <verb>` |
| Prompt 编译 | static_prefix 预编译 + dynamic_assembly 运行时装配 |
| anchor_type 枚举 | 以 design.md §3.7 为准 |
| idempotency_key | 追加 `{snapshot_hash}` 分量 |
| contract_status | 6 态 |
| repair 层级 | 统一 L1-L4 |
| sessions.status | `'active'` |
| 异常表 | 合并为 writing_exception_events |
| redo L2 模型 | 从 redo_model 配置读取 |
| pov_dependent | 改为 pov_scope TEXT |
| 精彩/坏味状态 | 废止旧状态机，正交字段 |
| P0 范围 | 以《分流》第 1 章导入、第 2 章链路验证、后续章节按章生产闭环为准，不以完整 13 服务一次实现为准 |
| 成本策略 | 不设置成本确认门；只记录 usage |
| 模型配置 | 项目级 `.inkflow/.models` 优先于 DB 内默认模型字段 |
| Chesil 衔接 | Chesil read-only 读取 InkFlow DB 导入；不得回写 InkFlow DB |
