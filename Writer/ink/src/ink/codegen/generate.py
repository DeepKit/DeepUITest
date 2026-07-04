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
