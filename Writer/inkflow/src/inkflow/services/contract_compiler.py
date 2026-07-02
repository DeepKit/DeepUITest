"""Contract Compiler (Service 1).

Compiles meta-contracts through a 2-phase process:
- Phase 1a: Compile to human_confirm_layer, pause for human review
- Phase 1b: Auto-expand below human_confirm_layer to Shot level

The meta-contract is the ten-subclass contract system (identity, narrative_voice,
hard_boundaries, anti_reveal, world_knowledge, structure_rules, anti_patterns,
style_locks, motif_system, creative_zones).
"""

from __future__ import annotations

import json
import sqlite3

from inkflow.utils.ulid import generate as generate_ulid
from inkflow.utils.hashing import snapshot_hash
from inkflow.models.enums import ContractStatus, ShotContractStatus
from inkflow.exceptions import ContractError


class ContractCompiler:
    """Compiles meta-contracts and shot-level contracts."""

    def __init__(self, db: sqlite3.Connection, project_id: str):
        self.db = db
        self.project_id = project_id

    # ── Meta-contract ──

    def create_meta_contract(
        self,
        contract_data: dict,
        *,
        human_confirm_layer: int = 2,
        version: str = "3.6",
    ) -> str:
        """Create a new meta-contract (draft status).

        Args:
            contract_data: The ten-subclass contract dict.
            human_confirm_layer: Layer index where human confirms.
            version: Contract version string.

        Returns:
            meta_contract_id
        """
        meta_contract_id = generate_ulid()

        self.db.execute(
            "INSERT INTO writing_meta_contract "
            "(meta_contract_id, project_id, contract_version, min_runtime_version, "
            "status, layers_json, human_confirm_layer) "
            "VALUES (?, ?, ?, '3.6', 'draft', ?, ?)",
            (meta_contract_id, self.project_id, version,
             json.dumps(contract_data, ensure_ascii=False), human_confirm_layer),
        )
        self.db.commit()
        return meta_contract_id

    def update_contract_status(self, meta_contract_id: str, status: str) -> None:
        """Update meta-contract status. Validates transition against current status."""
        current = self.db.execute(
            "SELECT status FROM writing_meta_contract WHERE meta_contract_id = ?",
            (meta_contract_id,),
        ).fetchone()
        if current is None:
            raise ContractError(f"Contract not found: {meta_contract_id}")
        current_status = current["status"]

        # Valid transitions: draft→human_review→confirmed→locked (repairing/evolving from any)
        if status not in (ContractStatus.REPAIRING, ContractStatus.EVOLVING):
            valid_next = {
                ContractStatus.DRAFT: [ContractStatus.HUMAN_REVIEW, ContractStatus.CONFIRMED],
                ContractStatus.HUMAN_REVIEW: [ContractStatus.CONFIRMED, ContractStatus.DRAFT],
                ContractStatus.CONFIRMED: [ContractStatus.LOCKED],
                ContractStatus.LOCKED: [],
            }
            allowed = valid_next.get(ContractStatus(current_status), [])
            if status not in allowed:
                raise ContractError(
                    f"Invalid contract status transition: "
                    f"{current_status} → {status}"
                )

        self.db.execute(
            "UPDATE writing_meta_contract SET status = ?, updated_at = datetime('now') "
            "WHERE meta_contract_id = ?",
            (status, meta_contract_id),
        )
        self.db.commit()

    def get_meta_contract(self) -> dict | None:
        """Get the latest meta-contract for this project."""
        row = self.db.execute(
            "SELECT * FROM writing_meta_contract "
            "WHERE project_id = ? "
            "ORDER BY created_at DESC LIMIT 1",
            (self.project_id,),
        ).fetchone()
        if row is None:
            return None
        result = dict(row)
        result["layers_json"] = json.loads(result["layers_json"])
        return result

    def confirm_contract(self, meta_contract_id: str) -> None:
        """Human confirms the contract (human_review → confirmed)."""
        self.update_contract_status(meta_contract_id, ContractStatus.CONFIRMED)

    def lock_contract(self, meta_contract_id: str) -> None:
        """Lock contract for a run (confirmed → locked). Idempotent if already locked."""
        current = self.db.execute(
            "SELECT status FROM writing_meta_contract WHERE meta_contract_id = ?",
            (meta_contract_id,),
        ).fetchone()
        if current and current["status"] == "locked":
            return  # Already locked
        self.update_contract_status(meta_contract_id, ContractStatus.LOCKED)

    def is_contract_confirmed(self) -> bool:
        """Check if meta-contract is in confirmed or locked state."""
        contract = self.get_meta_contract()
        if contract is None:
            return False
        return contract["status"] in (ContractStatus.CONFIRMED, ContractStatus.LOCKED)

    # ── Structured contract field accessors ──

    def _get_layers(self) -> dict:
        """Get the parsed layers_json from the latest meta-contract."""
        mc = self.get_meta_contract()
        if mc is None:
            return {}
        return mc.get("layers_json", {})

    def get_chapter_events(self, chapter_key: str | None = None) -> list[dict]:
        """Get chapter events from the contract. Contract is the authority.

        Args:
            chapter_key: e.g. 'v01.c02' or 'v01.c03'. If None, defaults to 'v01.c02'
                for backward compatibility.

        Returns:
            List of {shot, title, pov, event} dicts.
        """
        layers = self._get_layers()
        sr = layers.get("structure_rules", {})

        if chapter_key is None:
            chapter_key = "v01.c02"

        # Map chapter_key to the right field name
        key_map = {
            "v01.c02": "chapter_2_events",
            "v01.c03": "chapter_3_events",
            "v01.c04": "chapter_4_events",
            "v01.c05": "chapter_5_events",
            "v01.c06": "chapter_6_events",
            "v01.c07": "chapter_7_events",
            "v01.c08": "chapter_8_events",
        }
        field_name = key_map.get(chapter_key, f"chapter_{_chapter_num(chapter_key)}_events")
        return sr.get(field_name, [])

    def get_shot_count(self, chapter_key: str | None = None) -> int:
        """Get target shot count from the contract."""
        return len(self.get_chapter_events(chapter_key))

    def get_identity(self) -> dict:
        return self._get_layers().get("identity", {})

    def get_narrative_voice(self) -> dict:
        return self._get_layers().get("narrative_voice", {})

    def get_hard_boundaries(self) -> dict:
        return self._get_layers().get("hard_boundaries", {})

    def get_anti_reveal(self) -> dict:
        return self._get_layers().get("anti_reveal", {})

    def get_world_knowledge(self) -> dict:
        return self._get_layers().get("world_knowledge", {})

    def get_style_locks(self) -> dict:
        return self._get_layers().get("style_locks", {})

    def get_anti_patterns(self) -> dict:
        return self._get_layers().get("anti_patterns", {})

    def get_motif_system(self) -> dict:
        return self._get_layers().get("motif_system", {})

    def get_creative_zones(self) -> dict:
        return self._get_layers().get("creative_zones", {})

    def get_structure_rules(self) -> dict:
        return self._get_layers().get("structure_rules", {})

    def get_suspense_config(self) -> dict:
        return self._get_layers().get("suspense_config", {})

    # ── v24: Structured table readers (CONFIG-ENFORCE-4) ──

    def get_meta_contract_from_structured(self) -> dict | None:
        """Build meta_contract dict from v23 structured tables.

        Falls back to layers_json if structured tables are empty.
        This is the preferred path for consumers (prompt_compiler, etc.).
        """
        pid = self.project_id

        # Try structured tables first
        ident_row = self.db.execute(
            "SELECT * FROM writing_project_identity WHERE project_id = ? "
            "ORDER BY created_at DESC LIMIT 1", (pid,),
        ).fetchone()
        if ident_row is None:
            # Fall back to layers_json
            return self.get_meta_contract()

        ident = dict(ident_row)
        nv_row = self.db.execute(
            "SELECT * FROM writing_narrative_voice WHERE project_id = ? "
            "ORDER BY created_at DESC LIMIT 1", (pid,),
        ).fetchone()
        hb_row = self.db.execute(
            "SELECT * FROM writing_hard_boundaries WHERE project_id = ? "
            "ORDER BY created_at DESC LIMIT 1", (pid,),
        ).fetchone()
        sl_row = self.db.execute(
            "SELECT * FROM writing_style_locks WHERE project_id = ? "
            "ORDER BY created_at DESC LIMIT 1", (pid,),
        ).fetchone()
        sb_row = self.db.execute(
            "SELECT * FROM writing_suspense_blueprint WHERE project_id = ? "
            "ORDER BY created_at DESC LIMIT 1", (pid,),
        ).fetchone()

        # Build identity dict
        identity = {
            "title": ident.get("title", ""),
            "author": ident.get("author", ""),
            "genre_tags": json.loads(ident["genre_tags"]) if ident.get("genre_tags") else [],
            "era": ident.get("era", ""),
            "language": ident.get("language", "zh-CN"),
            "total_chapters": ident.get("total_chapters", 1),
        }
        # Restore pov_characters from hard_boundaries
        if hb_row:
            chars = json.loads(hb_row["characters_alive"]) if hb_row.get("characters_alive") else []
            if isinstance(chars, list):
                identity["pov_characters"] = chars

        # Build narrative_voice dict
        narrative_voice = {}
        if nv_row:
            nv = dict(nv_row)
            narrative_voice = {
                "pov_mode": nv.get("pov_mode", "third_limited"),
                "pov_characters": json.loads(nv["pov_characters"]) if nv.get("pov_characters") else [],
                "tense": nv.get("tense", "past"),
                "narrator_type": nv.get("narrator_type", "invisible"),
            }

        # Build hard_boundaries dict
        hard_boundaries = {}
        if hb_row:
            hb = dict(hb_row)
            hard_boundaries = {
                "forbidden_phrases": json.loads(hb["forbidden_phrases"]) if hb.get("forbidden_phrases") else [],
                "forbidden_topics": json.loads(hb["forbidden_topics"]) if hb.get("forbidden_topics") else [],
                "deprecated_aliases": json.loads(hb["deprecated_aliases"]) if hb.get("deprecated_aliases") else {},
                "world_rules": json.loads(hb["world_rules"]) if hb.get("world_rules") else [],
                "characters_alive": json.loads(hb["characters_alive"]) if hb.get("characters_alive") else [],
            }

        # Build style_locks dict
        style_locks = {}
        if sl_row:
            sl = dict(sl_row)
            style_locks = {
                "max_paragraph_chars": sl.get("max_paragraph_chars"),
                "max_sentence_chars": sl.get("max_sentence_chars"),
                "dialogue_ratio_min": sl.get("dialogue_ratio_min"),
                "dialogue_ratio_max": sl.get("dialogue_ratio_max"),
                "sensory_density": sl.get("sensory_density", "normal"),
                "anti_patterns": json.loads(sl["anti_patterns"]) if sl.get("anti_patterns") else [],
            }

        # Build suspense_blueprint dict
        suspense_blueprint = {}
        if sb_row:
            sb = dict(sb_row)
            suspense_blueprint = {
                "preset": sb.get("preset", "literary_tension"),
                "global_question": sb.get("global_question", ""),
            }

        # Get the layers_json for fields not yet in structured tables
        # (anti_reveal, world_knowledge, motif_system, creative_zones, suspense_config, structure_rules)
        layers = self._get_layers()

        return {
            "identity": identity,
            "narrative_voice": narrative_voice or layers.get("narrative_voice", {}),
            "hard_boundaries": hard_boundaries or layers.get("hard_boundaries", {}),
            "anti_reveal": layers.get("anti_reveal", {}),
            "world_knowledge": layers.get("world_knowledge", {}),
            "structure_rules": layers.get("structure_rules", {}),
            "anti_patterns": layers.get("anti_patterns", {}),
            "style_locks": style_locks or layers.get("style_locks", {}),
            "motif_system": layers.get("motif_system", {}),
            "creative_zones": layers.get("creative_zones", {}),
            "suspense_config": layers.get("suspense_config", {}),
            "suspense_blueprint": suspense_blueprint or layers.get("suspense_blueprint", {}),
        }

    def get_shot_structured(self, contract_id: str) -> dict:
        """Read shot contract from v24 structured tables.

        Returns dict with keys: must_land, anti_write, narrative_params.
        Falls back to JSON blob columns if structured tables are empty.
        """
        ml_row = self.db.execute(
            "SELECT * FROM writing_shot_must_land WHERE contract_id = ?",
            (contract_id,),
        ).fetchone()
        aw_row = self.db.execute(
            "SELECT * FROM writing_shot_anti_write WHERE contract_id = ?",
            (contract_id,),
        ).fetchone()
        np_row = self.db.execute(
            "SELECT * FROM writing_shot_narrative_params WHERE contract_id = ?",
            (contract_id,),
        ).fetchone()
        scene_row = self.db.execute(
            "SELECT * FROM writing_shot_scene_contracts WHERE contract_id = ?",
            (contract_id,),
        ).fetchone()

        result = {}

        if ml_row:
            ml = dict(ml_row)
            result["must_land"] = {
                "title": ml.get("title", ""),
                "beats": ml.get("beats", ""),
                "event": ml.get("event_text", ""),
            }
            result["pov_routing"] = {
                "pov_character": ml.get("pov_character", ""),
            }
        else:
            # Fallback to JSON blob
            sc_row = self.db.execute(
                "SELECT must_land_json, pov_routing_json FROM writing_shot_contracts "
                "WHERE contract_id = ?", (contract_id,),
            ).fetchone()
            if sc_row:
                result["must_land"] = json.loads(sc_row["must_land_json"]) if sc_row["must_land_json"] else {}
                result["pov_routing"] = json.loads(sc_row["pov_routing_json"]) if sc_row["pov_routing_json"] else {}

        if aw_row:
            aw = dict(aw_row)
            result["anti_write"] = {
                "pov_only": aw.get("pov_only", ""),
                "forbidden": json.loads(aw["forbidden_words"]) if aw.get("forbidden_words") else [],
                "forbidden_facts": json.loads(aw["forbidden_facts"]) if aw.get("forbidden_facts") else [],
            }
        else:
            sc_row = self.db.execute(
                "SELECT anti_write_json FROM writing_shot_contracts WHERE contract_id = ?",
                (contract_id,),
            ).fetchone()
            if sc_row:
                result["anti_write"] = json.loads(sc_row["anti_write_json"]) if sc_row["anti_write_json"] else {}

        if np_row:
            np_d = dict(np_row)
            result["narrative_params"] = {
                "narrative_phase": np_d.get("narrative_phase"),
                "sensory_pressure": np_d.get("sensory_pressure"),
                "deviation_budget": np_d.get("deviation_budget"),
                "dominant_sense": np_d.get("dominant_sense"),
                "entry_mood": np_d.get("entry_mood", ""),
                "hard_facts": json.loads(np_d["hard_facts"]) if np_d.get("hard_facts") else [],
                "soft_constraints": json.loads(np_d["soft_constraints"]) if np_d.get("soft_constraints") else [],
                "reference": np_d.get("reference", ""),
                "exit_to": np_d.get("exit_to", ""),
                "motif_tasks": json.loads(np_d["motif_tasks"]) if np_d.get("motif_tasks") else {},
            }
        else:
            sc_row = self.db.execute(
                "SELECT contract_json FROM writing_shot_contracts WHERE contract_id = ?",
                (contract_id,),
            ).fetchone()
            if sc_row:
                cj = json.loads(sc_row["contract_json"]) if sc_row["contract_json"] else {}
                result["narrative_params"] = {
                    "narrative_phase": cj.get("narrative_phase"),
                    "sensory_pressure": cj.get("sensory_pressure"),
                    "deviation_budget": cj.get("deviation_budget"),
                    "dominant_sense": cj.get("dominant_sense"),
                    "entry_mood": cj.get("entry_mood", ""),
                    "hard_facts": cj.get("hard_facts") or [],
                    "soft_constraints": cj.get("soft_constraints") or [],
                    "reference": cj.get("reference", ""),
                    "exit_to": cj.get("exit_to", ""),
                    "motif_tasks": cj.get("motif_tasks") or {},
                }

        if scene_row:
            scene = dict(scene_row)
            result["scene_contract"] = {
                "scene_id": scene.get("scene_id", ""),
                "location": scene.get("location", ""),
                "time_position": scene.get("time_position", ""),
                "entry_point": scene.get("entry_point", ""),
                "entry_object": scene.get("entry_object", ""),
                "required_anchors": json.loads(scene["required_anchors"]) if scene.get("required_anchors") else [],
                "forbidden_overlap": json.loads(scene["forbidden_overlap"]) if scene.get("forbidden_overlap") else [],
                "information_delta": scene.get("information_delta", ""),
                "exit_state": scene.get("exit_state", ""),
                "same_scene_continuation": bool(scene.get("same_scene_continuation")),
                "min_utf8_bytes": scene.get("min_utf8_bytes", 1200),
            }
        else:
            sc_row = self.db.execute(
                "SELECT contract_json FROM writing_shot_contracts WHERE contract_id = ?",
                (contract_id,),
            ).fetchone()
            if sc_row:
                cj = json.loads(sc_row["contract_json"]) if sc_row["contract_json"] else {}
                result["scene_contract"] = cj.get("scene_contract") or {}

        return result

    # ── Structured table writers (v23/v24 CONFIG-ENFORCE) ──

    def write_meta_contract_structured(self, meta_contract_id: str, contract_data: dict) -> None:
        """Write v23 structured meta-contract tables from contract_data.

        This is the DB-level enforcement path. Each table has NOT NULL + CHECK
        constraints so AI cannot silently skip fields.

        Called by confirm-contract after create_meta_contract().
        """
        pid = self.project_id

        # ═══ writing_project_identity ═══
        ident = contract_data.get("identity", {})
        title = ident.get("title", "") or ""
        author = ident.get("author", "") or ""
        raw_genres = ident.get("genre_tags")
        if raw_genres is None:
            raw_genres = ident.get("genre", [])
        if isinstance(raw_genres, str):
            raw_genres = [raw_genres] if raw_genres else []
        elif not isinstance(raw_genres, list):
            raw_genres = []
        genre_tags = json.dumps(raw_genres, ensure_ascii=False)
        era = ident.get("era", "") or ""
        language = ident.get("language", "zh-CN") or "zh-CN"
        total_chapters = ident.get("total_chapters", 1)
        try:
            total_chapters = int(total_chapters)
            if total_chapters <= 0:
                total_chapters = 1
        except (ValueError, TypeError):
            total_chapters = 1

        self.db.execute(
            "INSERT OR REPLACE INTO writing_project_identity "
            "(identity_id, project_id, title, author, genre_tags, era, language, total_chapters) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (generate_ulid(), pid, title, author, genre_tags, era, language, total_chapters),
        )

        # ═══ writing_hard_boundaries ═══
        hb = contract_data.get("hard_boundaries", {})
        forbidden_phrases = json.dumps(hb.get("forbidden_phrases", []), ensure_ascii=False)
        forbidden_topics = json.dumps(hb.get("forbidden_topics", []), ensure_ascii=False)
        deprecated_aliases = json.dumps(hb.get("deprecated_aliases", {}), ensure_ascii=False)
        world_rules_list = hb.get("world_rules", contract_data.get("world_knowledge", {}).get("rules", []))
        world_rules = json.dumps(world_rules_list, ensure_ascii=False)
        characters_alive = json.dumps(hb.get("characters_alive", ident.get("pov_characters", [])), ensure_ascii=False)

        self.db.execute(
            "INSERT OR REPLACE INTO writing_hard_boundaries "
            "(boundary_id, project_id, forbidden_phrases, forbidden_topics, "
            "deprecated_aliases, world_rules, characters_alive) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (generate_ulid(), pid, forbidden_phrases, forbidden_topics,
             deprecated_aliases, world_rules, characters_alive),
        )

        # ═══ writing_narrative_voice ═══
        nv = contract_data.get("narrative_voice", {})
        pov_mode = nv.get("pov_mode", "third_limited")
        valid_pov = ('first_person', 'third_limited', 'third_omniscient', 'multi_pov', 'free_indirect')
        if pov_mode not in valid_pov:
            pov_mode = "third_limited"
        pov_chars = json.dumps(nv.get("pov_characters", ident.get("pov_characters", [])), ensure_ascii=False)
        tense = nv.get("tense", "past")
        if tense not in ('past', 'present', 'mixed'):
            tense = "past"
        narrator_type = nv.get("narrator_type", "invisible")
        valid_narrator = ('character', 'invisible', 'unreliable', 'choral')
        if narrator_type not in valid_narrator:
            narrator_type = "invisible"

        self.db.execute(
            "INSERT OR REPLACE INTO writing_narrative_voice "
            "(voice_id, project_id, pov_mode, pov_characters, tense, narrator_type) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (generate_ulid(), pid, pov_mode, pov_chars, tense, narrator_type),
        )

        # ═══ writing_style_locks ═══
        sl = contract_data.get("style_locks", {})
        max_para = sl.get("max_paragraph_chars")
        max_sent = sl.get("max_sentence_chars")
        dial_min = sl.get("dialogue_ratio_min")
        dial_max = sl.get("dialogue_ratio_max")
        sensory = sl.get("sensory_density", "normal")
        if sensory not in ('sparse', 'normal', 'dense'):
            sensory = "normal"
        anti_pats = json.dumps(
            contract_data.get("anti_patterns", {}).get("patterns",
            sl.get("anti_patterns", [])), ensure_ascii=False
        )

        # Sanitize numeric values
        def _safe_int(v):
            if v is None: return None
            try:
                v = int(v)
                return v if v > 0 else None
            except (ValueError, TypeError):
                return None
        def _safe_ratio(v):
            if v is None: return None
            try:
                v = float(v)
                return v if 0 <= v <= 1 else None
            except (ValueError, TypeError):
                return None

        self.db.execute(
            "INSERT OR REPLACE INTO writing_style_locks "
            "(lock_id, project_id, max_paragraph_chars, max_sentence_chars, "
            "dialogue_ratio_min, dialogue_ratio_max, sensory_density, anti_patterns) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (generate_ulid(), pid, _safe_int(max_para), _safe_int(max_sent),
             _safe_ratio(dial_min), _safe_ratio(dial_max), sensory, anti_pats),
        )

        # ═══ writing_suspense_blueprint ═══
        sb = contract_data.get("suspense_blueprint", {})
        preset = sb.get("preset", "literary_tension")
        valid_presets = ('literary_tension', 'institutional_suspense',
                         'psychological_thriller', 'whodunit', 'slow_burn')
        if preset not in valid_presets:
            preset = "literary_tension"
        global_q = sb.get("global_question", "")
        # Ensure minimum length > 5 for CHECK constraint
        if not global_q or len(global_q) <= 5:
            sc = contract_data.get("suspense_config", {})
            # Try to derive from suspense_config
            anchor = sc.get("reader_anchor", "")
            if anchor and len(anchor) > 5:
                global_q = anchor
            else:
                global_q = f"{title}的核心悬念"  # fallback from identity title
        # Final safety: if still too short, pad
        if len(global_q) <= 5:
            global_q = f"{title}的核心悬念待解"

        self.db.execute(
            "INSERT OR REPLACE INTO writing_suspense_blueprint "
            "(blueprint_id, project_id, preset, global_question) "
            "VALUES (?, ?, ?, ?)",
            (generate_ulid(), pid, preset, global_q),
        )

        # Get the blueprint_id we just inserted for FK reference
        bp_row = self.db.execute(
            "SELECT blueprint_id FROM writing_suspense_blueprint "
            "WHERE project_id = ? ORDER BY created_at DESC LIMIT 1",
            (pid,),
        ).fetchone()
        blueprint_id = bp_row["blueprint_id"] if bp_row else None

        # ═══ writing_chapter_tension_arc ═══
        # Extract per-chapter tension data from suspense_config or structure_rules
        sr = contract_data.get("structure_rules", {})
        chapter_hooks = contract_data.get("suspense_config", {}).get("chapter_hooks", {})
        if not isinstance(chapter_hooks, dict):
            chapter_hooks = {}

        # For each chapter_N_events, create a tension arc entry
        for key in sr:
            if not key.startswith("chapter_") or not key.endswith("_events"):
                continue
            # Extract chapter key like "v01.c02" from "chapter_2_events"
            import re
            m = re.search(r'chapter_(\d+)_events', key)
            if not m:
                continue
            ch_num = int(m.group(1))
            chapter_key = f"v01.c{ch_num:02d}"

            # Determine tension target and role from chapter_hooks or defaults
            hook_info = chapter_hooks.get(f"chapter_{ch_num}", {})
            tension = hook_info.get("tension_target", 50)
            role = hook_info.get("suspense_role", "escalation")
            valid_roles = ('setup', 'escalation', 'peak', 'payoff', 'breather')
            if role not in valid_roles:
                role = "escalation"
            try:
                tension = int(tension)
                tension = max(0, min(100, tension))
            except (ValueError, TypeError):
                tension = 50

            reader_retention = hook_info.get("reader_retention", "") or ""
            main_engine = hook_info.get("main_engine", "") or ""

            if blueprint_id:
                self.db.execute(
                    "INSERT OR REPLACE INTO writing_chapter_tension_arc "
                    "(arc_id, blueprint_id, chapter_key, tension_target, suspense_role, "
                    "reader_retention, main_engine) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (generate_ulid(), blueprint_id, chapter_key, tension, role,
                     reader_retention, main_engine),
                )

        self.db.commit()

    def validate_contract_schema(self, contract_data: dict) -> list[str]:
        """Python-layer fast validation before DB INSERT.

        Returns list of error messages. Empty list = all good.
        Checks that values will pass DB CHECK constraints.
        """
        errors = []

        # Identity checks
        ident = contract_data.get("identity", {})
        if not ident.get("title"):
            errors.append("identity.title 不能为空")
        if not ident.get("author"):
            errors.append("identity.author 不能为空")
        if not ident.get("era"):
            errors.append("identity.era 不能为空")
        tc = ident.get("total_chapters")
        if tc is not None:
            try:
                if int(tc) <= 0:
                    errors.append("identity.total_chapters 必须 > 0")
            except (ValueError, TypeError):
                errors.append("identity.total_chapters 必须是正整数")

        # Narrative voice checks
        nv = contract_data.get("narrative_voice", {})
        pov_mode = nv.get("pov_mode", "third_limited")
        if pov_mode not in ('first_person', 'third_limited', 'third_omniscient', 'multi_pov', 'free_indirect'):
            errors.append(f"narrative_voice.pov_mode 非法值: {pov_mode}")
        tense = nv.get("tense", "past")
        if tense not in ('past', 'present', 'mixed'):
            errors.append(f"narrative_voice.tense 非法值: {tense}")
        narrator = nv.get("narrator_type", "invisible")
        if narrator not in ('character', 'invisible', 'unreliable', 'choral'):
            errors.append(f"narrative_voice.narrator_type 非法值: {narrator}")

        # Style locks checks
        sl = contract_data.get("style_locks", {})
        for ratio_key in ('dialogue_ratio_min', 'dialogue_ratio_max'):
            v = sl.get(ratio_key)
            if v is not None:
                try:
                    fv = float(v)
                    if not (0 <= fv <= 1):
                        errors.append(f"style_locks.{ratio_key} 必须在 0-1 之间")
                except (ValueError, TypeError):
                    errors.append(f"style_locks.{ratio_key} 必须是数字")

        # Suspense blueprint checks
        sb = contract_data.get("suspense_blueprint", {})
        preset = sb.get("preset", "literary_tension")
        if preset not in ('literary_tension', 'institutional_suspense',
                          'psychological_thriller', 'whodunit', 'slow_burn'):
            errors.append(f"suspense_blueprint.preset 非法值: {preset}")

        # Semantic completeness checks
        # 1. Shot POVs must be declared. Full POV coverage is enforced only
        #    when the contract has chapter events for the whole book; early
        #    partial outlines can legitimately omit later-generation POVs.
        pov_chars = nv.get("pov_characters", ident.get("pov_characters", []))
        if isinstance(pov_chars, str):
            pov_chars = [c.strip() for c in pov_chars.split(",") if c.strip()]
        if pov_chars:
            sr = contract_data.get("structure_rules", {})
            shot_povs = set()
            covered_chapters = set()
            for key in sr:
                if not key.startswith("chapter_") or not key.endswith("_events"):
                    continue
                try:
                    covered_chapters.add(int(key[len("chapter_"):-len("_events")]))
                except ValueError:
                    pass
                for ev in sr.get(key, []):
                    if isinstance(ev, dict):
                        pov = ev.get("pov", "")
                        if pov:
                            shot_povs.add(pov)
                            if pov not in pov_chars:
                                errors.append(f"shot POV '{pov}' 未在 POV 角色列表中声明")
            try:
                total_chapters = int(ident.get("total_chapters") or 0)
            except (ValueError, TypeError):
                total_chapters = 0
            has_full_outline = total_chapters > 1 and len(covered_chapters) >= total_chapters - 1
            if has_full_outline:
                for pc in pov_chars:
                    if pc not in shot_povs:
                        errors.append(f"角色 '{pc}' 在 POV 列表中但未在任何 shot 中出现")

        return errors

    # ── Contract revision history ──

    def record_revision(
        self,
        meta_contract_id: str,
        changed_by: str,
        reason: str,
        before: dict,
        after: dict,
    ) -> str:
        """Record a contract revision with diff.

        Args:
            meta_contract_id: The meta-contract being revised.
            changed_by: 'human', 'ai', or 'upgrade'.
            reason: Must be >= 50 chars per CHECK constraint.
            before: Contract state before change.
            after: Contract state after change.

        Returns:
            revision_id
        """
        revision_id = generate_ulid()
        diff = _compute_diff(before, after)

        self.db.execute(
            "INSERT INTO writing_meta_contract_revisions "
            "(revision_id, meta_contract_id, changed_by, reason, "
            "before_json, after_json, diff_json) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (revision_id, meta_contract_id, changed_by, reason,
             json.dumps(before, ensure_ascii=False),
             json.dumps(after, ensure_ascii=False),
             json.dumps(diff, ensure_ascii=False)),
        )
        self.db.commit()
        return revision_id

    # ── Shot contracts ──

    def compile_shot_contracts(
        self,
        run_id: str,
        shots: list[dict],
        meta_contract: dict,
    ) -> list[str]:
        """Compile per-shot contracts from meta-contract.

        For P0: This is a deterministic expansion. Each shot inherits
        identity, hard_boundaries, anti_reveal, world_knowledge, style_locks
        from the meta-contract. Shot-specific fields (must_land, anti_write,
        exit_to, motif_tasks, pov_routing) come from the chapter outline.

        Args:
            run_id: The run ID.
            shots: List of {shot_id, shot_index, layer_key} dicts.
            meta_contract: The confirmed meta-contract.

        Returns:
            List of contract_ids.
        """
        contract_ids = []
        contract_hash = snapshot_hash(meta_contract)

        try:
            self.db.execute("SAVEPOINT compile_shot_contracts")
            for shot in shots:
                existing = self.db.execute(
                    "SELECT contract_id FROM writing_shot_contracts "
                    "WHERE run_id = ? AND shot_id = ?",
                    (run_id, shot["shot_id"]),
                ).fetchone()
                if existing:
                    contract_ids.append(existing["contract_id"])
                    continue

                contract_id = generate_ulid()

                must_land = shot.get("must_land", {})
                anti_write = shot.get("anti_write", {})
                exit_to = shot.get("exit_to")
                motif_tasks = shot.get("motif_tasks")
                pov_routing = shot.get("pov_routing")

                # OPT-2: Sensory density per shot
                sensory_pressure = shot.get("sensory_pressure")
                dominant_sense = shot.get("dominant_sense")

                # OPT-6: Emotional transition bridge
                entry_mood = shot.get("entry_mood")

                # ARCH-1: Three-layer deviation taxonomy
                hard_facts = shot.get("hard_facts")
                soft_constraints = shot.get("soft_constraints")
                reference = shot.get("reference")

                # ARCH-2/3: Rhythm parameters
                deviation_budget = shot.get("deviation_budget")
                narrative_phase = shot.get("narrative_phase")
                scene_contract = _normalize_scene_contract(
                    shot.get("scene_contract"),
                    shot_index=shot["shot_index"],
                    layer_key=shot["layer_key"],
                    must_land=must_land,
                )

                # Full contract = meta-contract layers + shot-specific
                full_contract = {
                    "meta_contract_hash": contract_hash,
                    "shot_index": shot["shot_index"],
                    "layer_key": shot["layer_key"],
                    "must_land": must_land,
                    "anti_write": anti_write,
                    "exit_to": exit_to,
                    "motif_tasks": motif_tasks,
                    "pov_routing": pov_routing,
                    "sensory_pressure": sensory_pressure,
                    "dominant_sense": dominant_sense,
                    "entry_mood": entry_mood,
                    # ARCH-1: Three-layer deviation structure
                    "hard_facts": hard_facts,
                    "soft_constraints": soft_constraints,
                    "reference": reference,
                    # ARCH-2/3: Rhythm parameters
                    "deviation_budget": deviation_budget,
                    "narrative_phase": narrative_phase,
                    "scene_contract": scene_contract,
                }

                self.db.execute(
                    "INSERT INTO writing_shot_contracts "
                    "(contract_id, project_id, run_id, shot_id, layer_key, "
                    "contract_status, snapshot_hash, must_land_json, "
                    "anti_write_json, exit_to_json, motif_tasks_json, "
                    "pov_routing_json, contract_json) "
                    "VALUES (?, ?, ?, ?, ?, 'draft', ?, ?, ?, ?, ?, ?, ?)",
                    (contract_id, self.project_id, run_id, shot["shot_id"],
                     shot["layer_key"], contract_hash,
                     json.dumps(must_land, ensure_ascii=False),
                     json.dumps(anti_write, ensure_ascii=False),
                     json.dumps(exit_to, ensure_ascii=False) if exit_to else None,
                     json.dumps(motif_tasks, ensure_ascii=False) if motif_tasks else None,
                     json.dumps(pov_routing, ensure_ascii=False) if pov_routing else None,
                     json.dumps(full_contract, ensure_ascii=False)),
                )

                # v24: Write to structured shot tables for DB-level enforcement
                self._write_shot_structured_tables(
                    contract_id, must_land, anti_write, pov_routing,
                    sensory_pressure, dominant_sense, entry_mood,
                    deviation_budget, narrative_phase,
                    hard_facts, soft_constraints, reference,
                    exit_to, motif_tasks, scene_contract,
                )

                contract_ids.append(contract_id)

            self.db.execute("RELEASE SAVEPOINT compile_shot_contracts")
            self.db.commit()
            return contract_ids
        except Exception:
            self.db.execute("ROLLBACK TO SAVEPOINT compile_shot_contracts")
            raise

    def get_shot_contract(self, shot_id: str, run_id: str) -> dict | None:
        """Get the contract for a specific shot."""
        row = self.db.execute(
            "SELECT * FROM writing_shot_contracts "
            "WHERE shot_id = ? AND run_id = ?",
            (shot_id, run_id),
        ).fetchone()
        if row is None:
            return None
        result = dict(row)
        for json_field in ("must_land_json", "anti_write_json", "exit_to_json",
                           "motif_tasks_json", "pov_routing_json", "contract_json"):
            if result.get(json_field):
                result[json_field] = json.loads(result[json_field])
        return result

    def lock_shot_contracts(self, run_id: str) -> None:
        """Lock all shot contracts for a run."""
        self.db.execute(
            "UPDATE writing_shot_contracts SET contract_status = 'locked' "
            "WHERE run_id = ? AND contract_status != 'locked'",
            (run_id,),
        )
        self.db.commit()

    # ── v24: Structured shot table writers ──

    def _write_shot_structured_tables(
        self,
        contract_id: str,
        must_land: dict,
        anti_write: dict,
        pov_routing: dict | None,
        sensory_pressure: str | None,
        dominant_sense: str | None,
        entry_mood: str | None,
        deviation_budget: int | None,
        narrative_phase: str | None,
        hard_facts: list | None,
        soft_constraints: list | None,
        reference: str | None,
        exit_to: dict | None,
        motif_tasks: dict | None,
        scene_contract: dict | None,
    ) -> None:
        """Write to v24 structured shot tables for DB-level enforcement.

        This runs alongside the JSON blob writes. The structured tables
        provide NOT NULL + CHECK constraints that AI cannot bypass.
        """
        # ═══ writing_shot_must_land ═══
        ml_title = must_land.get("title", "") or ""
        ml_beats_raw = must_land.get("beats", "")
        if isinstance(ml_beats_raw, list):
            ml_beats = "\n".join(str(b) for b in ml_beats_raw if b)
        else:
            ml_beats = str(ml_beats_raw) if ml_beats_raw else ""
        ml_event = must_land.get("event", "") or must_land.get("event_text", "") or ""

        # Ensure minimum content — if beats is empty, fall back to event; if event empty, fall back to beats
        if not ml_beats.strip() and ml_event.strip():
            ml_beats = ml_event
        if not ml_event.strip() and ml_beats.strip():
            ml_event = ml_beats
        # Last resort: use title as both
        if not ml_beats.strip():
            ml_beats = ml_title or "untitled"
        if not ml_event.strip():
            ml_event = ml_title or "untitled"
        if not ml_title.strip():
            ml_title = ml_event[:20] or "untitled"

        pov_char = ""
        if pov_routing and isinstance(pov_routing, dict):
            pov_char = pov_routing.get("pov_character", "") or ""

        self.db.execute(
            "INSERT OR REPLACE INTO writing_shot_must_land "
            "(must_land_id, contract_id, title, beats, event_text, pov_character) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (generate_ulid(), contract_id, ml_title, ml_beats, ml_event, pov_char),
        )

        # ═══ writing_shot_anti_write ═══
        aw_pov_only = ""
        aw_forbidden_words = "[]"
        aw_forbidden_facts = "[]"
        if anti_write and isinstance(anti_write, dict):
            aw_pov_only = anti_write.get("pov_only", "") or ""
            fw = anti_write.get("forbidden", anti_write.get("forbidden_words", []))
            if isinstance(fw, list):
                aw_forbidden_words = json.dumps(fw, ensure_ascii=False)
            elif isinstance(fw, str):
                aw_forbidden_words = fw if fw.startswith("[") else json.dumps(
                    [x.strip() for x in fw.split(",") if x.strip()], ensure_ascii=False
                )
            ff = anti_write.get("forbidden_facts", [])
            if isinstance(ff, list):
                aw_forbidden_facts = json.dumps(ff, ensure_ascii=False)
            elif isinstance(ff, str):
                aw_forbidden_facts = ff if ff.startswith("[") else "[]"

        self.db.execute(
            "INSERT OR REPLACE INTO writing_shot_anti_write "
            "(anti_write_id, contract_id, pov_only, forbidden_words, forbidden_facts) "
            "VALUES (?, ?, ?, ?, ?)",
            (generate_ulid(), contract_id, aw_pov_only, aw_forbidden_words, aw_forbidden_facts),
        )

        # ═══ writing_shot_narrative_params ═══
        # Validate enum values — if invalid, set to None (let DB CHECK pass as NULL)
        np_phase = narrative_phase if narrative_phase in (
            'opening', 'rising', 'complication', 'crisis', 'climax', 'resolution'
        ) else None
        np_sensory = sensory_pressure if sensory_pressure in (
            'low', 'normal', 'heightened', 'overwhelming'
        ) else None
        np_budget = deviation_budget
        if np_budget is not None:
            try:
                np_budget = int(np_budget)
                np_budget = max(0, min(100, np_budget))
            except (ValueError, TypeError):
                np_budget = None
        np_sense = dominant_sense if dominant_sense in (
            'visual', 'auditory', 'tactile', 'olfactory', 'gustatory', 'kinesthetic'
        ) else None
        np_mood = entry_mood or ""
        np_hf = json.dumps(hard_facts, ensure_ascii=False) if isinstance(hard_facts, list) else "[]"
        np_sc = json.dumps(soft_constraints, ensure_ascii=False) if isinstance(soft_constraints, list) else "[]"
        np_ref = reference or ""
        np_exit = json.dumps(exit_to, ensure_ascii=False) if isinstance(exit_to, dict) else (str(exit_to) if exit_to else "")
        np_motif = json.dumps(motif_tasks, ensure_ascii=False) if isinstance(motif_tasks, dict) else "{}"

        self.db.execute(
            "INSERT OR REPLACE INTO writing_shot_narrative_params "
            "(params_id, contract_id, narrative_phase, sensory_pressure, "
            "deviation_budget, dominant_sense, entry_mood, hard_facts, "
            "soft_constraints, reference, exit_to, motif_tasks) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (generate_ulid(), contract_id, np_phase, np_sensory,
             np_budget, np_sense, np_mood, np_hf, np_sc, np_ref, np_exit, np_motif),
        )

        # ═══ writing_shot_scene_contracts ═══
        scene = _normalize_scene_contract(scene_contract, shot_index=0, layer_key="", must_land=must_land)
        self.db.execute(
            "INSERT OR REPLACE INTO writing_shot_scene_contracts "
            "(scene_contract_id, contract_id, scene_id, location, time_position, "
            "entry_point, entry_object, required_anchors, forbidden_overlap, "
            "information_delta, exit_state, same_scene_continuation, min_utf8_bytes) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                generate_ulid(),
                contract_id,
                scene["scene_id"],
                scene["location"],
                scene.get("time_position", ""),
                scene.get("entry_point", ""),
                scene.get("entry_object", ""),
                json.dumps(scene.get("required_anchors") or [], ensure_ascii=False),
                json.dumps(scene.get("forbidden_overlap") or [], ensure_ascii=False),
                scene.get("information_delta", ""),
                scene.get("exit_state", ""),
                1 if scene.get("same_scene_continuation") else 0,
                int(scene.get("min_utf8_bytes") or 1200),
            ),
        )


def _normalize_scene_contract(
    scene_contract: dict | None,
    *,
    shot_index: int,
    layer_key: str,
    must_land: dict | None,
) -> dict:
    """Normalize a scene contract into the v25 structured table shape."""
    scene = scene_contract if isinstance(scene_contract, dict) else {}
    must_land = must_land if isinstance(must_land, dict) else {}
    event_text = " ".join(
        str(value)
        for value in (
            must_land.get("title"),
            must_land.get("event"),
            must_land.get("event_text"),
            must_land.get("beats"),
        )
        if value
    )

    def as_list(value) -> list[str]:
        if isinstance(value, list):
            return [str(item).strip() for item in value if str(item).strip()]
        if isinstance(value, tuple):
            return [str(item).strip() for item in value if str(item).strip()]
        if isinstance(value, str):
            return [part.strip() for part in value.split(",") if part.strip()]
        return []

    scene_id = str(scene.get("scene_id") or "").strip()
    if not scene_id:
        if layer_key and shot_index:
            scene_id = f"{layer_key}.scene.{shot_index:02d}"
        elif shot_index:
            scene_id = f"scene.{shot_index:02d}"
        else:
            scene_id = "scene"

    location = str(scene.get("location") or "").strip()
    if not location:
        location = _fallback_scene_location(event_text)

    required = as_list(scene.get("required_anchors"))
    if not required:
        required = _fallback_required_anchors(event_text)

    try:
        min_bytes = int(scene.get("min_utf8_bytes") or 1200)
    except (TypeError, ValueError):
        min_bytes = 1200
    min_bytes = max(600, min_bytes)

    return {
        "scene_id": scene_id,
        "location": location,
        "time_position": str(scene.get("time_position") or "").strip(),
        "entry_point": str(scene.get("entry_point") or "").strip(),
        "entry_object": str(scene.get("entry_object") or "").strip(),
        "required_anchors": required,
        "forbidden_overlap": as_list(scene.get("forbidden_overlap")),
        "information_delta": str(scene.get("information_delta") or "").strip(),
        "exit_state": str(scene.get("exit_state") or "").strip(),
        "same_scene_continuation": bool(scene.get("same_scene_continuation")),
        "min_utf8_bytes": min_bytes,
    }


def _fallback_scene_location(text: str) -> str:
    compact = text or ""
    if any(term in compact for term in ("转运站", "月台", "军列", "交接单", "卡车")):
        return "转运站月台"
    if any(term in compact for term in ("露天", "堆场", "货场", "防水布", "托盘", "前线")):
        return "前线露天堆场"
    if any(term in compact for term in ("工厂", "厂区", "车间", "铁门", "硫化")):
        return "工厂车间门口"
    return "待明确场景"


def _fallback_required_anchors(text: str) -> list[str]:
    anchors: list[str] = []
    for term in (
        "转运站", "月台", "军列", "交接单", "卡车",
        "露天", "堆场", "防水布", "托盘", "微裂纹", "批号",
        "工厂", "车间", "铁门", "不该出现的气味", "硫磺", "橡胶",
    ):
        if term in (text or "") and term not in anchors:
            anchors.append(term)
    return anchors[:8]


def _chapter_num(chapter_key: str) -> int:
    """Extract chapter number from key like 'v01.c02' → 2."""
    import re
    m = re.search(r'c(\d+)', chapter_key)
    return int(m.group(1)) if m else 2


def _compute_diff(before: dict, after: dict) -> dict:
    """Compute a recursive diff between two contract states."""
    diff: dict = {"added": {}, "removed": {}, "changed": {}}

    all_keys = set(before.keys()) | set(after.keys())
    for key in all_keys:
        if key not in before:
            diff["added"][key] = after[key]
        elif key not in after:
            diff["removed"][key] = before[key]
        elif before[key] != after[key]:
            if isinstance(before[key], dict) and isinstance(after[key], dict):
                nested = _compute_diff(before[key], after[key])
                if nested["added"] or nested["removed"] or nested["changed"]:
                    diff["changed"][key] = nested
            else:
                diff["changed"][key] = {"before": before[key], "after": after[key]}

    return diff
