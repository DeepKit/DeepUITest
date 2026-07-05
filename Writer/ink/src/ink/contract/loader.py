from __future__ import annotations

import json
import sqlite3

from ink.contract.generated.dtos import ShotContractDTO
from ink.errors import DataIntegrityError


def load_shot_contract(conn: sqlite3.Connection, shot_id: str, run_id: int) -> ShotContractDTO:
    row = conn.execute(
        """
        SELECT
            s.shot_id,
            s.run_id,
            ml.events,
            ml.beats,
            ml.information_releases,
            aw.forbidden_facts,
            aw.forbidden_words,
            aw.pov_only,
            sc.location,
            sc.time_of_day,
            sc.characters_present,
            sc.character_positions,
            pa.persona,
            pa.intensity,
            pa.is_creative_shot,
            pa.is_suspense_shot,
            soft.relaxable_rules,
            soft.deviation_budget
        FROM writing_shots s
        JOIN writing_shot_contracts c ON c.shot_contract_id = s.shot_contract_id
        JOIN writing_shot_must_land ml ON ml.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_anti_write aw ON aw.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_scene_contract sc ON sc.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_persona_assignment pa ON pa.shot_contract_id = c.shot_contract_id
        JOIN writing_shot_soft_constraints soft ON soft.shot_contract_id = c.shot_contract_id
        WHERE s.shot_id = ? AND s.run_id = ?
        """,
        (shot_id, run_id),
    ).fetchone()
    if row is None:
        raise DataIntegrityError(f"shot contract projection not found: {shot_id}/{run_id}")

    return ShotContractDTO(
        shot_id=str(row[0]),
        run_id=int(row[1]),
        must_land={
            "events": json.loads(row[2]),
            "beats": json.loads(row[3]),
            "information_releases": json.loads(row[4]),
        },
        anti_write={
            "forbidden_facts": json.loads(row[5]),
            "forbidden_words": json.loads(row[6]),
            "pov_only": json.loads(row[7]),
        },
        scene_contract={
            "location": row[8],
            "time_of_day": row[9],
            "characters_present": json.loads(row[10]),
            "character_positions": json.loads(row[11]),
        },
        persona_assignment={
            "persona": row[12],
            "intensity": json.loads(row[13]),
            "is_creative_shot": bool(row[14]),
            "is_suspense_shot": bool(row[15]),
        },
        soft_constraints={
            "relaxable_rules": json.loads(row[16]),
            "deviation_budget": float(row[17]),
        },
    )
