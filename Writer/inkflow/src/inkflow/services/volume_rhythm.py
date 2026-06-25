"""Volume Rhythm Service — L0.5 卷部战术节奏 (ARCH-5).

职责：
  读取 L0 全书宪法 + 卷内章 events，产出卷级节奏参数：
    - volume_mini_arc: 卷内 mini-arc（每章 phase）
    - chapter_roles_in_volume: 卷内章角色（起/承/转/合 子集）
    - tension_budget: 卷内张力预算（peak 章 + 谷底章）
    - deviation_range_per_chapter: 每章的有效 deviation range

存储：
  优先使用 tree_nodes L2 volume 节点的 contract_versions。
  专用表 writing_volume_rhythms 提供快速运行时查询。
"""

from __future__ import annotations

import json
import sqlite3

from inkflow.utils.ulid import generate as generate_ulid
from inkflow.services.model_client import ModelClient, ModelRequest, ModelCallError


_VOLUME_ARC_PHASES = ["起", "承", "转", "合"]
_CHAPTER_ROLES = ["起", "承", "转", "合"]
_VALID_TENSION_RANGE = (0.0, 1.0)


class VolumeRhythmError(Exception):
    """Volume rhythm generation/validation error."""


class VolumeRhythmService:
    """L0.5: 卷部战术节奏服务。"""

    def __init__(
        self,
        db: sqlite3.Connection,
        project_id: str,
        model_client: ModelClient,
    ):
        self.db = db
        self.project_id = project_id
        self.model = model_client

    def generate_volume_rhythm(
        self,
        constitution: dict,
        volume_key: str,
        chapter_events_map: dict[str, list[dict]],
    ) -> dict:
        """生成单卷节奏。

        Args:
            constitution: L0 全书宪法 dict（来自 writing_book_constitutions）。
            volume_key: 卷 key，如 'v01'。
            chapter_events_map: {chapter_key: [event_dict, ...]}，卷内所有章的事件。

        Returns:
            volume_rhythm dict 含 volume_key, volume_mini_arc,
            chapter_roles_in_volume, tension_budget, deviation_range_per_chapter。
        """
        # 1. 从宪法提取卷级上下文
        volume_map = self._parse_json(constitution.get("volume_map_json") or "{}")
        chapter_roles = self._parse_json(constitution.get("chapter_roles_json") or "{}")
        volume_data = volume_map.get(volume_key, {})

        volume_chapters = volume_data.get("chapters", list(chapter_events_map.keys()))
        volume_name = volume_data.get("name", volume_key)

        # 2. LLM 生成
        llm_result = self._llm_generate(
            volume_key=volume_key,
            volume_name=volume_name,
            volume_chapters=volume_chapters,
            chapter_events_map=chapter_events_map,
            chapter_roles=chapter_roles,
            constitution=constitution,
        )

        # 3. 规则引擎验证
        issues = self._validate(llm_result, volume_chapters, constitution)
        if issues:
            llm_result = self._llm_fix(llm_result, issues, volume_chapters)
            remaining = self._validate(llm_result, volume_chapters, constitution)
            if remaining:
                raise VolumeRhythmError(
                    f"Volume rhythm validation failed after retry: {remaining}"
                )

        # 4. 补全
        result = self._finalize(llm_result, volume_key, volume_chapters)
        return result

    def store_volume_rhythm(self, rhythm: dict, run_id: str) -> str:
        """存储卷节奏到 writing_volume_rhythms 表。"""
        rhythm_id = f"vr_{rhythm['volume_key']}_{run_id}"
        self.db.execute(
            "INSERT OR REPLACE INTO writing_volume_rhythms "
            "(rhythm_id, volume_key, project_id, run_id, rhythm_json, validation_json) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                rhythm_id,
                rhythm["volume_key"],
                self.project_id,
                run_id,
                json.dumps(rhythm, ensure_ascii=False),
                json.dumps({"valid": True}, ensure_ascii=False),
            ),
        )
        self.db.commit()
        return rhythm_id

    def get_volume_rhythm(
        self, volume_key: str, run_id: str | None = None
    ) -> dict | None:
        """获取卷节奏。优先取最新 run 的，否则取任意 run 的。"""
        query = (
            "SELECT rhythm_json FROM writing_volume_rhythms "
            "WHERE volume_key = ? AND project_id = ? "
        )
        params = [volume_key, self.project_id]
        if run_id:
            query += "AND run_id = ? "
            params.append(run_id)
        query += "ORDER BY created_at DESC LIMIT 1"

        row = self.db.execute(query, params).fetchone()
        if row is None:
            return None
        return json.loads(row["rhythm_json"])

    def get_volume_rhythm_for_chapter(
        self, chapter_key: str, run_id: str | None = None
    ) -> dict | None:
        """获取某章所属卷的节奏。"""
        volume_key = chapter_key.split(".")[0]
        return self.get_volume_rhythm(volume_key, run_id)

    # ── LLM ──

    def _llm_generate(
        self,
        volume_key: str,
        volume_name: str,
        volume_chapters: list[str],
        chapter_events_map: dict[str, list[dict]],
        chapter_roles: dict[str, str],
        constitution: dict,
    ) -> dict:
        """LLM 生成卷节奏。"""
        # 组装章事件摘要
        chapter_summaries = {}
        for ck in volume_chapters:
            events = chapter_events_map.get(ck, [])
            summary_lines = []
            for ev in events[:4]:
                title = ev.get("title", "")
                event_text = ev.get("event", "")[:150]
                summary_lines.append(f"  - {title}: {event_text}")
            chapter_summaries[ck] = "\n".join(summary_lines) or "（无事件）"

        chapters_block = "\n".join(
            f"### {ck}\n{chapter_summaries.get(ck, '（无事件）')}"
            for ck in volume_chapters
        )

        arc_shape = constitution.get("arc_shape", "unknown")
        tension_peak = constitution.get("tension_peak_chapter", "")
        deviation_mean = constitution.get("global_deviation_mean", 0.4)
        deviation_range = self._parse_json(
            constitution.get("global_deviation_range_json") or "[]"
        )
        if not deviation_range or len(deviation_range) < 2:
            deviation_range = [0.2, 0.65]

        chapter_role_block = "\n".join(
            f"  {ck}: {chapter_roles.get(ck, '?')}"
            for ck in volume_chapters
        )

        prompt = f"""你是墨韵的全书节奏架构师。请为以下卷设计战术节奏参数。

## 卷信息
- 卷 key: {volume_key}
- 卷名: {volume_name}
- 全书叙事弧: {arc_shape}
- 全书张力峰值章: {tension_peak}

## 全书偏离参数
- global_deviation_mean: {deviation_mean}
- global_deviation_range: [{deviation_range[0]}, {deviation_range[1]}]

## 全书章角色（全局视角）
{chapter_role_block}

## 卷内章节及事件
{chapters_block}

## 任务

为这个卷生成节奏参数，输出 JSON：

```json
{{
  "volume_key": "{volume_key}",
  "volume_mini_arc": [
    {{"chapter_key": "v01.c01", "arc_phase": "establishment", "tension_level": 0.3}},
    ...
  ],
  "chapter_roles_in_volume": {{
    "v01.c01": "起",
    "v01.c02": "承",
    ...
  }},
  "tension_budget": {{
    "peak_chapter": "v01.c04",
    "valley_chapters": ["v01.c01", "v01.c08"],
    "peak_tension": 0.9,
    "valley_tension": 0.2
  }},
  "deviation_range_per_chapter": {{
    "v01.c01": [0.2, 0.5],
    "v01.c02": [0.3, 0.6],
    ...
  }}
}}
```

## 约束
- arc_phase 用: establishment / rising / climax / release
- chapter_roles_in_volume 用: 起/承/转/合（仅用于卷内，可选 subset）
- deviation_range_per_chapter 的每章 range 必须在全局 [{deviation_range[0]}, {deviation_range[1]}] 内
- tension_level 和 peak_tension/valley_tension 在 [0.0, 1.0]
- chapter_roles_in_volume 的 key 必须覆盖 volume_chapters 的全部章节
"""

        try:
            response = self.model.generate(ModelRequest(
                operation="architect_volume_rhythm",
                persona="architect",
                prompt=prompt,
                temperature=0.5,
                max_tokens=4096,
            ))
            return self._parse_llm_response(response.text)
        except (ModelCallError, ValueError) as e:
            raise VolumeRhythmError(f"LLM 生成卷节奏失败: {e}")

    def _llm_fix(self, prev: dict, issues: list[str], volume_chapters: list[str]) -> dict:
        """LLM 修复验证失败的问题。"""
        prompt = f"""上一次的卷节奏 JSON 有以下问题需要修复：

{json.dumps(issues, ensure_ascii=False, indent=2)}

上一次的输出：
{json.dumps(prev, ensure_ascii=False, indent=2)}

请修复以上问题，重新输出完整的 JSON。保持相同的输出格式。"""

        try:
            response = self.model.generate(ModelRequest(
                operation="architect_volume_rhythm_retry",
                persona="architect",
                prompt=prompt,
                temperature=0.3,
                max_tokens=4096,
            ))
            return self._parse_llm_response(response.text)
        except (ModelCallError, ValueError):
            return prev

    # ── 验证 ──

    def _validate(
        self, result: dict, volume_chapters: list[str], constitution: dict,
    ) -> list[str]:
        """规则引擎验证，返回 issue 列表（空 = 通过）。"""
        issues: list[str] = []

        if not result.get("volume_key"):
            issues.append("缺少 volume_key")

        # 检查 chapter_roles_in_volume 覆盖全部章节
        roles = result.get("chapter_roles_in_volume", {})
        missing = set(volume_chapters) - set(roles.keys())
        if missing:
            issues.append(f"chapter_roles_in_volume 缺少: {sorted(missing)}")
        extra = set(roles.keys()) - set(volume_chapters)
        if extra:
            issues.append(f"chapter_roles_in_volume 多余: {sorted(extra)}")

        # 检查 volume_mini_arc 覆盖全部章节
        arc = result.get("volume_mini_arc", [])
        arc_keys = {a.get("chapter_key") for a in arc}
        missing_arc = set(volume_chapters) - arc_keys
        if missing_arc:
            issues.append(f"volume_mini_arc 缺少: {sorted(missing_arc)}")

        # 检查 deviation_range_per_chapter 覆盖全部章节
        dr = result.get("deviation_range_per_chapter", {})
        missing_dr = set(volume_chapters) - set(dr.keys())
        if missing_dr:
            issues.append(f"deviation_range_per_chapter 缺少: {sorted(missing_dr)}")

        # 检查 deviation 范围合法性
        global_range = self._parse_json(
            constitution.get("global_deviation_range_json") or "[]"
        )
        if len(global_range) == 2:
            for ck in dr:
                r = dr[ck]
                if isinstance(r, list) and len(r) == 2:
                    if r[0] > r[1]:
                        issues.append(f"{ck}: deviation_range[{r[0]}] > [{r[1]}]")
                    if r[0] < global_range[0] - 0.1:
                        issues.append(f"{ck}: deviation min {r[0]} 低于全局下限 {global_range[0]}")
                    if r[1] > global_range[1] + 0.1:
                        issues.append(f"{ck}: deviation max {r[1]} 高于全局上限 {global_range[1]}")

        # tension_budget 检查
        tb = result.get("tension_budget", {})
        if tb:
            peak = tb.get("peak_tension", -1)
            valley = tb.get("valley_tension", 2)
            if not (_VALID_TENSION_RANGE[0] <= peak <= _VALID_TENSION_RANGE[1]):
                issues.append(f"peak_tension {peak} 超出范围")
            if not (_VALID_TENSION_RANGE[0] <= valley <= _VALID_TENSION_RANGE[1]):
                issues.append(f"valley_tension {valley} 超出范围")
            if peak < valley:
                issues.append(f"peak_tension {peak} < valley_tension {valley}")

        return issues

    # ── 内部 ──

    def _parse_llm_response(self, text: str) -> dict:
        """从 LLM 响应提取 JSON。"""
        text = text.strip()
        if "```json" in text:
            start = text.index("```json") + 7
            end = text.index("```", start)
            text = text[start:end].strip()
        elif "```" in text:
            start = text.index("```") + 3
            end = text.index("```", start)
            text = text[start:end].strip()
        try:
            data = json.loads(text)
        except json.JSONDecodeError as e:
            raise VolumeRhythmError(f"LLM 响应不是有效 JSON: {e}\n前 200 字: {text[:200]}")

        if not isinstance(data, dict):
            raise VolumeRhythmError("LLM 响应不是 JSON 对象")
        return data

    def _parse_json(self, raw) -> dict:
        """安全解析 JSON 字段，总是返回 dict。"""
        if not raw:
            return {}
        if isinstance(raw, dict):
            return raw
        if isinstance(raw, str):
            try:
                result = json.loads(raw)
                if isinstance(result, dict):
                    return result
                return {}
            except (json.JSONDecodeError, TypeError):
                return {}
        return {}

    def _finalize(self, llm_result: dict, volume_key: str, volume_chapters: list[str]) -> dict:
        """补全缺省值，返回最终 dict。"""
        # 确保 deviation_range_per_chapter 覆盖所有章节
        dr = llm_result.get("deviation_range_per_chapter", {})
        for ck in volume_chapters:
            if ck not in dr:
                dr[ck] = [0.3, 0.7]  # 默认

        # 确保 volume_mini_arc 覆盖所有章节
        arc = llm_result.get("volume_mini_arc", [])
        arc_map = {a.get("chapter_key"): a for a in arc}
        for ck in volume_chapters:
            if ck not in arc_map:
                arc_map[ck] = {"chapter_key": ck, "arc_phase": "rising", "tension_level": 0.5}

        return {
            "volume_key": volume_key,
            "volume_mini_arc": sorted(arc_map.values(), key=lambda a: a.get("chapter_key", "")),
            "chapter_roles_in_volume": llm_result.get("chapter_roles_in_volume", {}),
            "tension_budget": llm_result.get("tension_budget", {}),
            "deviation_range_per_chapter": dr,
            "generated_by": "llm",
        }
