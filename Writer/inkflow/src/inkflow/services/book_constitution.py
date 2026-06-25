"""Book Constitution Service (L0 全书宪法).

ARCH-4: L0 全书节奏治理层。从大纲源文件生成全书宪法，包含：
- arc_shape: 全书叙事弧
- tension_peak/valley: 张力峰值/谷底章节
- volume_map: 卷→章映射
- chapter_roles: 每章的起承转合角色
- motif_lifecycle: motif 的生命周期（种/发/收）
- global_deviation: 全局偏离参数

LLM 80% + 规则引擎 20%。人类确认后锁定为不可变。
"""

from __future__ import annotations

import hashlib
import json
import sqlite3
from pathlib import Path

from inkflow.services.model_client import (
    ModelClient,
    ModelRequest,
    ModelCallError,
    create_model_client,
)
from inkflow.utils.ulid import generate as generate_ulid


# 状态转换规则
_VALID_TRANSITIONS: dict[str, list[str]] = {
    "draft": ["human_review", "confirmed"],
    "human_review": ["confirmed"],
    "confirmed": ["locked"],
    "locked": [],
}

# 源文件列表
_SOURCE_FILES = [
    ("01_创意总纲.md", "creative_manifest"),
    ("03_人物小传.md", "character_profiles"),
    ("04_逐章大纲.md", "chapter_outline"),
    ("05_成都元素矩阵.md", "chengdu_elements"),
    ("07_不解之谜设计.md", "unsolved_mysteries"),
]


class BookConstitutionError(Exception):
    """Book constitution error."""


class BookConstitutionService:
    """L0 全书宪法服务。"""

    def __init__(
        self,
        db: sqlite3.Connection,
        project_id: str,
        models_config: dict | None = None,
        providers: dict | None = None,
    ):
        self.db = db
        self.project_id = project_id
        self.models_config = models_config or {}
        self.providers = providers or {}

    # ── 生成 ──────────────────────────────────────────────────────────

    def generate_constitution(self, story_dir: str) -> str:
        """读取 .md 源文件，用 LLM 生成宪法草稿。返回 constitution_id。"""
        # 1. 收集源材料
        materials = self._collect_source_materials(story_dir)

        # 2. 获取已注册 motif
        existing_motifs = self._get_existing_motifs()

        # 3. 构造 LLM prompt
        prompt = self._build_generation_prompt(materials, existing_motifs)

        # 4. 调用 LLM
        model_ref = self._resolve_model()
        client = create_model_client(model_ref, db=self.db, providers=self.providers)
        request = ModelRequest(
            operation="constitution_generate",
            persona="l0_architect",
            prompt=prompt,
            model=model_ref,
            temperature=0.4,
            max_tokens=8192,
        )
        response = client.generate(request)

        # 5. 解析 JSON
        constitution_data = self._parse_llm_response(response.text)

        # 6. 规则引擎验证
        issues = self.validate_constitution(constitution_data)
        if issues:
            # 有验证问题但仍保存为 draft，让人类审核
            constitution_data["_validation_issues"] = issues

        # 7. 计算源文件 hash
        source_hash = self._compute_source_hash(materials)

        # 8. 写入 DB
        constitution_id = generate_ulid()
        self.db.execute(
            "INSERT INTO writing_book_constitutions ("
            "constitution_id, project_id, version, arc_shape, "
            "tension_peak_chapter, tension_valley_chapters_json, "
            "volume_map_json, chapter_roles_json, motif_lifecycle_json, "
            "global_deviation_mean, global_deviation_range_json, "
            "status, source_outline_hash, llm_model_ref"
            ") VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, 'draft', ?, ?)",
            (
                constitution_id,
                self.project_id,
                constitution_data.get("arc_shape", ""),
                constitution_data.get("tension_peak_chapter", ""),
                json.dumps(constitution_data.get("tension_valley_chapters", []), ensure_ascii=False),
                json.dumps(constitution_data.get("volume_map", {}), ensure_ascii=False),
                json.dumps(constitution_data.get("chapter_roles", {}), ensure_ascii=False),
                json.dumps(constitution_data.get("motif_lifecycle", []), ensure_ascii=False),
                constitution_data.get("global_deviation_mean", 0.4),
                json.dumps(constitution_data.get("global_deviation_range", [0.2, 0.65]), ensure_ascii=False),
                source_hash,
                model_ref,
            ),
        )
        self.db.commit()
        return constitution_id

    # ── 验证（规则引擎）─────────────────────────────────────────────────

    def validate_constitution(self, data: dict) -> list[str]:
        """规则引擎验证，返回 issue 列表（空 = 通过）。"""
        issues: list[str] = []

        # 规则 1: 卷数 2–6
        volume_map = data.get("volume_map", {})
        vol_count = len(volume_map)
        if vol_count < 2 or vol_count > 6:
            issues.append(f"卷数 {vol_count} 不在合理范围 [2, 6]")

        # 规则 2: 所有章节都分配到某卷
        all_chapters_in_volumes: set[str] = set()
        for vdata in volume_map.values():
            chs = vdata.get("chapters", []) if isinstance(vdata, dict) else []
            all_chapters_in_volumes.update(chs)

        chapter_roles = data.get("chapter_roles", {})
        all_chapters_in_roles = set(chapter_roles.keys())

        if all_chapters_in_roles and all_chapters_in_volumes:
            missing = all_chapters_in_roles - all_chapters_in_volumes
            if missing:
                issues.append(f"以下章节在 roles 中但不在任何卷中: {sorted(missing)}")
            extra = all_chapters_in_volumes - all_chapters_in_roles
            if extra:
                issues.append(f"以下章节在卷中但不在 roles 中: {sorted(extra)}")

        # 规则 3: 张力弧有且仅有 1 个 peak
        peak = data.get("tension_peak_chapter", "")
        if not peak:
            issues.append("缺少 tension_peak_chapter")

        # 规则 4: 每个 motif 生命周期完整（planted + resolved）
        motifs = data.get("motif_lifecycle", [])
        for m in motifs:
            mid = m.get("motif_id", "?")
            if not m.get("planted_at"):
                issues.append(f"motif '{mid}' 缺少 planted_at")
            if not m.get("resolved_at"):
                issues.append(f"motif '{mid}' 缺少 resolved_at")

        # 规则 5: deviation_mean 在 [0.0, 1.0]
        mean = data.get("global_deviation_mean")
        if mean is not None:
            if not (0.0 <= mean <= 1.0):
                issues.append(f"global_deviation_mean={mean} 不在 [0.0, 1.0]")

        # 规则 6: deviation_range 合法
        rng = data.get("global_deviation_range", [])
        if len(rng) == 2:
            if rng[0] > rng[1]:
                issues.append(f"deviation_range[{rng[0]}] > range[{rng[1]}]")
            if mean is not None:
                if mean < rng[0] or mean > rng[1]:
                    issues.append(f"deviation_mean={mean} 不在 range [{rng[0]}, {rng[1]}]")

        return issues

    # ── 状态转换 ──────────────────────────────────────────────────────

    def update_status(self, constitution_id: str, new_status: str) -> None:
        """状态转换: draft → human_review → confirmed → locked。"""
        row = self.db.execute(
            "SELECT status FROM writing_book_constitutions WHERE constitution_id = ?",
            (constitution_id,),
        ).fetchone()
        if row is None:
            raise BookConstitutionError(f"宪法不存在: {constitution_id}")

        current = row[0]
        if new_status not in _VALID_TRANSITIONS.get(current, []):
            raise BookConstitutionError(
                f"非法状态转换: {current} → {new_status}。"
                f"允许: {_VALID_TRANSITIONS.get(current, [])}"
            )

        updates = ["status = ?", "updated_at = datetime('now')"]
        params: list = [new_status, constitution_id]

        if new_status == "confirmed":
            updates.append("confirmed_at = datetime('now')")
        elif new_status == "locked":
            updates.append("locked_at = datetime('now')")

        self.db.execute(
            f"UPDATE writing_book_constitutions SET {', '.join(updates)} "
            "WHERE constitution_id = ?",
            params,
        )
        self.db.commit()

    def lock_constitution(self, constitution_id: str) -> None:
        """锁定宪法（不可变）。如果当前是 confirmed，直接 lock；否则先 confirm 再 lock。"""
        row = self.db.execute(
            "SELECT status FROM writing_book_constitutions WHERE constitution_id = ?",
            (constitution_id,),
        ).fetchone()
        if row is None:
            raise BookConstitutionError(f"宪法不存在: {constitution_id}")
        status = row[0]
        if status == "locked":
            return  # 已锁定
        if status == "confirmed":
            self.update_status(constitution_id, "locked")
        else:
            self.update_status(constitution_id, "confirmed")
            self.update_status(constitution_id, "locked")

    # ── 查询 ──────────────────────────────────────────────────────────

    def get_latest_constitution(self) -> dict | None:
        """获取最新宪法（任何状态）。"""
        row = self.db.execute(
            "SELECT * FROM writing_book_constitutions "
            "WHERE project_id = ? "
            "ORDER BY version DESC LIMIT 1",
            (self.project_id,),
        ).fetchone()
        if row is None:
            return None
        return dict(row)

    def get_locked_constitution(self) -> dict | None:
        """获取已锁定的宪法（用于 run 时注入）。"""
        row = self.db.execute(
            "SELECT * FROM writing_book_constitutions "
            "WHERE project_id = ? AND status = 'locked' "
            "ORDER BY version DESC LIMIT 1",
            (self.project_id,),
        ).fetchone()
        if row is None:
            return None
        return dict(row)

    # ── 内部方法 ──────────────────────────────────────────────────────

    def _collect_source_materials(self, story_dir: str) -> dict[str, str]:
        """读取并拼接 .md 源文件内容。"""
        materials: dict[str, str] = {}
        base = Path(story_dir)
        for filename, key in _SOURCE_FILES:
            fpath = base / filename
            if fpath.exists():
                content = fpath.read_text(encoding="utf-8")
                # 截断过长文件（每个文件最多 8000 字符）
                if len(content) > 8000:
                    content = content[:8000] + "\n... [截断]"
                materials[key] = content
        return materials

    def _get_existing_motifs(self) -> list[dict]:
        """获取已注册的 motif 列表。"""
        rows = self.db.execute(
            "SELECT motif_id, name, category, description, variants_json "
            "FROM writing_motif_definitions WHERE project_id = ?",
            (self.project_id,),
        ).fetchall()
        return [
            {
                "motif_id": r[0],
                "name": r[1],
                "category": r[2],
                "description": r[3],
                "variants": json.loads(r[4]) if r[4] else [],
            }
            for r in rows
        ]

    def _build_generation_prompt(
        self, materials: dict[str, str], existing_motifs: list[dict]
    ) -> str:
        """构造 LLM prompt。"""
        # 截断每个材料
        manifest = materials.get("creative_manifest", "")[:3000]
        outline = materials.get("chapter_outline", "")[:4000]
        elements = materials.get("chengdu_elements", "")[:2000]
        mysteries = materials.get("unsolved_mysteries", "")[:1500]
        characters = materials.get("character_profiles", "")[:2000]

        # 格式化 motif 列表
        motif_lines = []
        for m in existing_motifs:
            motif_lines.append(f"  - {m['name']}: {m.get('description', '')}")
        motif_text = "\n".join(motif_lines) if motif_lines else "（无已注册 motif）"

        return f"""你是墨韵 (InkFlow) 的全书节奏架构师（L0 层）。

你的任务是为《分流》生成全书节奏宪法。你需要分析所有源材料，提取叙事结构，
规划 motif 生命周期，设定全局偏离参数。

## 创意总纲
{manifest}

## 人物小传
{characters}

## 逐章大纲（摘要）
{outline}

## 成都元素矩阵
{elements}

## 不解之谜设计
{mysteries}

## 已注册 Motif
{motif_text}

## 任务

分析以上材料，为全书生成节奏宪法。返回一个 JSON 对象（不要包含其他文字，只返回 JSON）：

```json
{{
  "arc_shape": "全书叙事弧描述（如 slow_build → crisis → revelation）",
  "tension_peak_chapter": "vXX.cXX（张力最高的章节）",
  "tension_valley_chapters": ["vXX.cXX", "..."],
  "volume_map": {{
    "v01": {{"name": "卷名", "chapters": ["v01.c01", "v01.c02", ...], "arc_summary": "卷内弧线"}},
    "v02": {{...}},
    "v03": {{...}},
    "v04": {{...}}
  }},
  "chapter_roles": {{
    "v01.c01": "起",
    "v01.c02": "承",
    ...
  }},
  "motif_lifecycle": [
    {{"motif_id": "motif的ULID", "planted_at": "v01.c01", "developed_at": ["v01.c03", "v02.c01"], "resolved_at": "v04.c05"}},
    ...
  ],
  "global_deviation_mean": 0.4,
  "global_deviation_range": [0.2, 0.65]
}}
```

## 约束
- 4 卷已确定（四水流/清浊分/回水/不系舟），不可合并或拆分
- 每卷章数：v01=8, v02=8, v03=7, v04=9
- 张力 peak 应在全书后 2/3 区域（v03 或 v04）
- 每个已注册 motif 必须有完整生命周期（planted_at + resolved_at）
- deviation_mean 应在 [0.3, 0.5] 区间
- chapter_roles 用 起/承/转/合 标记，每卷至少有 1 个起 + 1 个合
"""

    def _parse_llm_response(self, response_text: str) -> dict:
        """从 LLM 响应中提取 constitution JSON。"""
        text = response_text.strip()

        # 尝试提取 ```json ... ``` 块
        if "```json" in text:
            start = text.index("```json") + 7
            end = text.index("```", start)
            text = text[start:end].strip()
        elif "```" in text:
            start = text.index("```") + 3
            end = text.index("```", start)
            text = text[start:end].strip()

        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            raise BookConstitutionError(f"LLM 响应不是有效 JSON: {e}\n响应前 200 字: {text[:200]}")

    def _resolve_model(self) -> str:
        """解析用于宪法生成的模型。"""
        # 优先从 models_config 读取 architect 角色
        roles = self.models_config.get("roles", {})
        architect = roles.get("architect", {})
        if isinstance(architect, dict):
            primary = architect.get("primary_model", "")
            if primary:
                return primary
        # 回退到 writer 的 primary
        writer = self.models_config.get("writer", {})
        if isinstance(writer, dict):
            primary = writer.get("primary", "")
            if primary:
                return primary
        # 最终回退
        return "local-default"

    def _compute_source_hash(self, materials: dict[str, str]) -> str:
        """计算源材料 hash（用于追踪宪法是基于哪个版本的大纲生成的）。"""
        combined = "|".join(f"{k}:{v[:500]}" for k, v in sorted(materials.items()))
        return hashlib.sha256(combined.encode("utf-8")).hexdigest()[:16]
