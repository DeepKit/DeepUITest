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
