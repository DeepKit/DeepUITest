"""MotifTracker (Service 7).

Tracks motif density, evolution phases, and generates per-shot motif tasks.
4 evolution phases: establishment → variation → subversion → resolution.

Density status: green (on track), yellow (slightly over), blue (slightly under),
red (way over), gray (not yet started).
"""

from __future__ import annotations

import json
import sqlite3

from inkflow.utils.ulid import generate as generate_ulid
from inkflow.models.enums import EvolutionPhase, DensityStatus

# Default target density when not specified in motif definition
DEFAULT_MOTIF_DENSITY_PER_100 = 10


class MotifTracker:
    """Tracks motifs across a writing run."""

    def __init__(self, db: sqlite3.Connection, project_id: str, run_id: str):
        self.db = db
        self.project_id = project_id
        self.run_id = run_id

    def scan_and_record(self, shot_id: str, text: str) -> list[str]:
        """Scan generated text for motif appearances and record them.

        Searches text for motif names and variants from all registered
        motif definitions. For each match, calls record_instance().

        Args:
            shot_id: The shot that was just generated.
            text: The generated text to scan.

        Returns:
            List of motif_ids that were detected and recorded.
        """
        detected: list[str] = []

        defs = self.db.execute(
            "SELECT motif_id, name, variants_json "
            "FROM writing_motif_definitions WHERE project_id = ?",
            (self.project_id,),
        ).fetchall()

        for motif_def in defs:
            motif_id = motif_def["motif_id"]
            name = motif_def["name"]
            variants = json.loads(motif_def["variants_json"] or "{}")
            variant_list = variants.get("keywords", []) if isinstance(variants, dict) else []

            # Check if motif name or any variant keyword appears in text
            matched = name in text
            matched_variant = ""
            if not matched and variant_list:
                for kw in variant_list:
                    if kw in text:
                        matched = True
                        matched_variant = kw
                        break

            if matched:
                phase = self.get_evolution_phase(motif_id)
                self.record_instance(motif_id, shot_id, matched_variant or name, phase)
                detected.append(motif_id)

        if detected:
            self.update_density_after_shot(shot_id)

        return detected

    def register_motif(self, definition: dict) -> str:
        """Register a motif definition.

        Args:
            definition: {name, category, description, planned_density_json,
                         variants_json, min_shot_gap, mutual_exclusion_json,
                         evolution_json}

        Returns:
            motif_id

        Raises:
            ValueError: if required fields are missing.
        """
        for field in ("name", "planned_density_json", "variants_json"):
            if field not in definition:
                raise ValueError(f"register_motif: missing required field '{field}'")

        motif_id = generate_ulid()

        self.db.execute(
            "INSERT INTO writing_motif_definitions "
            "(motif_id, project_id, name, category, description, "
            "planned_density_json, variants_json, min_shot_gap, "
            "mutual_exclusion_json, evolution_json) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (motif_id, self.project_id,
             definition["name"],
             definition.get("category"),
             definition.get("description"),
             json.dumps(definition["planned_density_json"], ensure_ascii=False),
             json.dumps(definition["variants_json"], ensure_ascii=False),
             definition.get("min_shot_gap", 3),
             json.dumps(definition.get("mutual_exclusion_json", {}), ensure_ascii=False),
             json.dumps(definition.get("evolution_json", {}), ensure_ascii=False)),
        )

        # Initialize tracker
        tracker_id = generate_ulid()
        self.db.execute(
            "INSERT INTO writing_motif_tracker "
            "(tracker_id, motif_id, project_id, run_id, current_count, density_status) "
            "VALUES (?, ?, ?, ?, 0, 'gray')",
            (tracker_id, motif_id, self.project_id, self.run_id),
        )

        self.db.commit()
        return motif_id

    def get_density_status(self, motif_id: str) -> str:
        """Get current density status for a motif."""
        row = self.db.execute(
            "SELECT density_status FROM writing_motif_tracker "
            "WHERE motif_id = ? AND run_id = ?",
            (motif_id, self.run_id),
        ).fetchone()
        return row["density_status"] if row else "gray"

    def generate_motif_task(self, shot_id: str) -> dict:
        """Generate motif task for a shot.

        Checks all active motifs and determines which should appear,
        be suggested, or be forbidden in this shot.
        Respects min_shot_gap: suppresses required/suggested if the motif
        was used too recently.

        Returns:
            Dict: {required: [...], suggested: [...], forbidden: [...], allowed: [...]}
        """
        # Get current shot index for gap calculation
        current_shot_row = self.db.execute(
            "SELECT shot_index FROM writing_shots WHERE shot_id = ?",
            (shot_id,),
        ).fetchone()
        current_shot_index = current_shot_row["shot_index"] if current_shot_row else 0

        trackers = self.db.execute(
            "SELECT t.*, d.name, d.planned_density_json, d.min_shot_gap, "
            "d.mutual_exclusion_json, d.evolution_json "
            "FROM writing_motif_tracker t "
            "JOIN writing_motif_definitions d ON t.motif_id = d.motif_id "
            "WHERE t.run_id = ?",
            (self.run_id,),
        ).fetchall()

        required = []
        suggested = []
        forbidden = []
        allowed = []

        for tracker in trackers:
            name = tracker["name"]
            density = json.loads(tracker["planned_density_json"])
            status = tracker["density_status"]
            min_gap = tracker["min_shot_gap"]

            # Check min_shot_gap: if used too recently, suppress required/suggested
            gap_ok = True
            if tracker["last_used_shot_id"] and min_gap > 0:
                last_shot_row = self.db.execute(
                    "SELECT shot_index FROM writing_shots WHERE shot_id = ?",
                    (tracker["last_used_shot_id"],),
                ).fetchone()
                if last_shot_row:
                    gap = current_shot_index - last_shot_row["shot_index"]
                    if gap < min_gap:
                        gap_ok = False

            if status == "red":
                forbidden.append(name)
            elif status == "blue" and gap_ok:
                required.append(name)
            elif status == "yellow" and gap_ok:
                suggested.append(name)
            else:
                allowed.append(name)

        return {
            "required": required,
            "suggested": suggested,
            "forbidden": forbidden,
            "allowed": allowed,
        }

    def record_instance(
        self,
        motif_id: str,
        shot_id: str,
        variant: str,
        phase: str,
    ) -> str:
        """Record a motif instance appearing in a shot.

        Args:
            motif_id: Which motif.
            shot_id: Which shot.
            variant: Which variant was used.
            phase: Evolution phase.

        Returns:
            instance_id
        """
        instance_id = generate_ulid()

        self.db.execute(
            "INSERT INTO writing_motif_instances "
            "(instance_id, motif_id, project_id, run_id, shot_id, "
            "variant_used, evolution_phase) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (instance_id, motif_id, self.project_id, self.run_id,
             shot_id, variant, phase),
        )

        # Update tracker
        self.db.execute(
            "UPDATE writing_motif_tracker SET current_count = current_count + 1, "
            "last_used_shot_id = ?, updated_at = datetime('now') "
            "WHERE motif_id = ? AND run_id = ?",
            (shot_id, motif_id, self.run_id),
        )

        self.db.commit()
        return instance_id

    def get_evolution_phase(self, motif_id: str) -> str:
        """Get current evolution phase for a motif."""
        row = self.db.execute(
            "SELECT evolution_json FROM writing_motif_definitions WHERE motif_id = ?",
            (motif_id,),
        ).fetchone()

        if row is None:
            return EvolutionPhase.ESTABLISHMENT

        # Count instances to determine phase
        count_row = self.db.execute(
            "SELECT COUNT(*) as cnt FROM writing_motif_instances "
            "WHERE motif_id = ? AND run_id = ?",
            (motif_id, self.run_id),
        ).fetchone()
        count = count_row["cnt"] if count_row else 0

        if count == 0:
            return EvolutionPhase.ESTABLISHMENT
        elif count <= 2:
            return EvolutionPhase.VARIATION
        elif count <= 4:
            return EvolutionPhase.SUBVERSION
        else:
            return EvolutionPhase.RESOLUTION

    def update_density_after_shot(self, shot_id: str) -> None:
        """Update density status for all motifs after a shot completes."""
        trackers = self.db.execute(
            "SELECT t.*, d.planned_density_json, d.min_shot_gap "
            "FROM writing_motif_tracker t "
            "JOIN writing_motif_definitions d ON t.motif_id = d.motif_id "
            "WHERE t.run_id = ?",
            (self.run_id,),
        ).fetchall()

        for tracker in trackers:
            density = json.loads(tracker["planned_density_json"])
            target_density = density.get("target_per_100_shots", DEFAULT_MOTIF_DENSITY_PER_100)
            current = tracker["current_count"]

            # Get total shots so far
            total_shots_row = self.db.execute(
                "SELECT COUNT(*) as cnt FROM writing_shots WHERE run_id = ?",
                (self.run_id,),
            ).fetchone()
            total_shots = total_shots_row["cnt"] if total_shots_row else 1

            # Calculate actual density
            actual_density = (current / max(total_shots, 1)) * 100

            # Determine status (GRAY must come before BLUE — current==0
            # always has actual_density==0 which is always < target*0.5)
            if actual_density > target_density * 1.5:
                status = DensityStatus.RED
            elif actual_density > target_density * 1.2:
                status = DensityStatus.YELLOW
            elif current == 0:
                status = DensityStatus.GRAY
            elif actual_density < target_density * 0.5:
                status = DensityStatus.BLUE
            else:
                status = DensityStatus.GREEN

            self.db.execute(
                "UPDATE writing_motif_tracker SET density_status = ?, "
                "updated_at = datetime('now') "
                "WHERE tracker_id = ?",
                (status, tracker["tracker_id"]),
            )

        self.db.commit()

    def get_all_motif_states(self) -> list[dict]:
        """Get all motif tracker states."""
        rows = self.db.execute(
            "SELECT t.*, d.name "
            "FROM writing_motif_tracker t "
            "JOIN writing_motif_definitions d ON t.motif_id = d.motif_id "
            "WHERE t.run_id = ?",
            (self.run_id,),
        ).fetchall()
        return [dict(r) for r in rows]