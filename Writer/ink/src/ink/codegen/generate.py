from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class FieldSpec:
    name: str
    type_hint: str


@dataclass(frozen=True)
class DataclassSpec:
    name: str
    fields: tuple[FieldSpec, ...]


SCHEMAS: tuple[DataclassSpec, ...] = (
    DataclassSpec(
        "MetaContractDTO",
        (
            FieldSpec("meta_contract_id", "int"),
            FieldSpec("project_id", "int"),
            FieldSpec("identity", "dict[str, object]"),
            FieldSpec("narrative_voice", "dict[str, object]"),
            FieldSpec("hard_boundaries", "dict[str, object]"),
            FieldSpec("style_locks", "dict[str, object]"),
            FieldSpec("world_knowledge", "dict[str, object]"),
            FieldSpec("motif_system", "dict[str, object]"),
            FieldSpec("creative_zones", "dict[str, object]"),
            FieldSpec("style_quality_profile", "dict[str, object]"),
            FieldSpec("status", "str"),
        ),
    ),
    DataclassSpec(
        "ShotContractDTO",
        (
            FieldSpec("shot_id", "str"),
            FieldSpec("run_id", "int"),
            FieldSpec("must_land", "dict[str, object]"),
            FieldSpec("anti_write", "dict[str, object]"),
            FieldSpec("scene_contract", "dict[str, object]"),
            FieldSpec("persona_assignment", "dict[str, object]"),
            FieldSpec("soft_constraints", "dict[str, object]"),
        ),
    ),
    DataclassSpec(
        "OutlineSpecDTO",
        (
            FieldSpec("outline_id", "int"),
            FieldSpec("shot_contract_id", "int"),
            FieldSpec("evaluated_outline_text", "str"),
            FieldSpec("drift_score", "float"),
            FieldSpec("is_winner", "bool"),
        ),
    ),
    DataclassSpec(
        "TaskCardDTO",
        (
            FieldSpec("task_card_id", "int"),
            FieldSpec("shot_contract_id", "int"),
            FieldSpec("compiled_instructions", "str"),
            FieldSpec("superseded_at", "str | None"),
        ),
    ),
    DataclassSpec(
        "PromptSpecDTO",
        (
            FieldSpec("prompt_id", "int"),
            FieldSpec("task_card_id", "int"),
            FieldSpec("persona", "str"),
            FieldSpec("full_prompt_text", "str"),
            FieldSpec("prompt_size_bytes", "int"),
            FieldSpec("relaxed_soft", "bool"),
            FieldSpec("superseded_at", "str | None"),
        ),
    ),
    DataclassSpec(
        "DraftSpecDTO",
        (
            FieldSpec("draft_id", "int"),
            FieldSpec("shot_id", "str"),
            FieldSpec("prompt_id", "int"),
            FieldSpec("persona", "str"),
            FieldSpec("writer_model", "str"),
            FieldSpec("text", "str"),
            FieldSpec("byte_count", "int"),
            FieldSpec("degraded", "bool"),
        ),
    ),
    DataclassSpec(
        "JuryInputDTO",
        (
            FieldSpec("draft_id", "int"),
            FieldSpec("shot_contract_id", "int"),
            FieldSpec("jury_round", "int"),
            FieldSpec("judge_model_pool", "tuple[str, ...]"),
        ),
    ),
    DataclassSpec(
        "ProjectConfigDTO",
        (
            FieldSpec("project_id", "int"),
            FieldSpec("draft_count", "int"),
            FieldSpec("writer_model_pool", "tuple[str, ...]"),
            FieldSpec("jury_model_pool", "tuple[str, ...]"),
            FieldSpec("shot_quality_floor", "int"),
            FieldSpec("dimension_floor", "int"),
        ),
    ),
    DataclassSpec(
        "QualityReportDTO",
        (
            FieldSpec("evidence_class", "str"),
            FieldSpec("defect_class", "str"),
            FieldSpec("blind_review_passed", "bool"),
            FieldSpec("would_continue_reading_score", "int"),
            FieldSpec("blocking_items", "tuple[str, ...]"),
            FieldSpec("productive_deviations", "tuple[str, ...]"),
            FieldSpec("neutral_issues", "tuple[str, ...]"),
            FieldSpec("smart_model_required", "bool"),
        ),
    ),
)


def render_dataclasses(specs: tuple[DataclassSpec, ...] = SCHEMAS) -> str:
    lines = [
        "from __future__ import annotations",
        "",
        "from dataclasses import dataclass",
        "",
        "",
        "class GeneratedContractDTO:",
        "    def unpack(self) -> dict[str, object]:",
        "        return {name: getattr(self, name) for name in self.__dataclass_fields__}",
        "",
    ]
    for spec in specs:
        lines.extend(_render_dataclass(spec))
    return "\n".join(lines) + "\n"


def write_generated(output_path: Path | None = None) -> Path:
    target = output_path or Path(__file__).resolve().parents[1] / "contract" / "generated" / "dtos.py"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render_dataclasses(), encoding="utf-8", newline="\n")
    return target


def _render_dataclass(spec: DataclassSpec) -> list[str]:
    lines = [
        "@dataclass(frozen=True)",
        f"class {spec.name}(GeneratedContractDTO):",
    ]
    for field in spec.fields:
        lines.append(f"    {field.name}: {field.type_hint}")
    lines.append("")
    return lines


if __name__ == "__main__":
    print(write_generated())
