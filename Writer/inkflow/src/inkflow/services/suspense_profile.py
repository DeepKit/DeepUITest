"""Suspense Profile — suspense profile system (D-25).

Provides 5 named suspense presets, each defining alpha/beta/gamma weights
(info asymmetry / time asymmetry / consequence asymmetry).

Suspense intensity = alpha * info_asymmetry + beta * time_asymmetry + gamma * consequence_asymmetry
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class SuspenseProfile:
    """Suspense preset: defines three asymmetry weights + engineering parameters."""

    name: str
    display_name: str
    description: str

    # Three asymmetry weights (alpha, beta, gamma), sum to 1.0
    alpha: float  # info asymmetry weight
    beta: float   # time asymmetry weight
    gamma: float  # consequence asymmetry weight

    # Engineering parameters (derived from three asymmetries)
    chapter_hook_intensity: int = 50
    info_gap_frequency: int = 50
    harm_preview_intensity: int = 50
    number_temperature_required: bool = True
    explanation_ban_intensity: int = 50
    foreshadowing_density: int = 50

    default_hook_type: str = "action_interrupt"
    requires_tension_valley: bool = True


# 5 named presets
PRESETS: dict[str, SuspenseProfile] = {
    "literary_tension": SuspenseProfile(
        name="literary_tension",
        display_name="literary tension",
        description="No traditional hooks, driven by character internal conflict. For literary fiction.",
        alpha=0.3, beta=0.4, gamma=0.3,
        chapter_hook_intensity=10,
        info_gap_frequency=10,
        harm_preview_intensity=10,
        number_temperature_required=False,
        explanation_ban_intensity=10,
        foreshadowing_density=20,
        default_hook_type="silence",
        requires_tension_valley=True,
    ),
    "institutional_suspense": SuspenseProfile(
        name="institutional_suspense",
        display_name="institutional suspense",
        description="Tension from system pressure, not personal danger. Info-gap driven.",
        alpha=0.5, beta=0.3, gamma=0.2,
        chapter_hook_intensity=50,
        info_gap_frequency=60,
        harm_preview_intensity=40,
        number_temperature_required=True,
        explanation_ban_intensity=50,
        foreshadowing_density=50,
        default_hook_type="action_interrupt",
        requires_tension_valley=True,
    ),
    "psychological_thriller": SuspenseProfile(
        name="psychological_thriller",
        display_name="psychological thriller",
        description="High-intensity consequence perception. Reader constantly fears the worst.",
        alpha=0.2, beta=0.3, gamma=0.5,
        chapter_hook_intensity=90,
        info_gap_frequency=70,
        harm_preview_intensity=90,
        number_temperature_required=True,
        explanation_ban_intensity=90,
        foreshadowing_density=80,
        default_hook_type="cliffhanger",
        requires_tension_valley=False,
    ),
    "whodunit": SuspenseProfile(
        name="whodunit",
        display_name="whodunit / mystery",
        description="Info orchestration driven. Precise control of info asymmetry, many red herrings.",
        alpha=0.6, beta=0.2, gamma=0.2,
        chapter_hook_intensity=60,
        info_gap_frequency=80,
        harm_preview_intensity=30,
        number_temperature_required=True,
        explanation_ban_intensity=70,
        foreshadowing_density=90,
        default_hook_type="information_hook",
        requires_tension_valley=True,
    ),
    "slow_burn": SuspenseProfile(
        name="slow_burn",
        display_name="slow burn",
        description="Low frequency, high intensity. Many seeds, slow reveals. For long-form suspense.",
        alpha=0.4, beta=0.4, gamma=0.2,
        chapter_hook_intensity=40,
        info_gap_frequency=30,
        harm_preview_intensity=30,
        number_temperature_required=True,
        explanation_ban_intensity=40,
        foreshadowing_density=70,
        default_hook_type="silence",
        requires_tension_valley=True,
    ),
}


def get_preset(name: str) -> SuspenseProfile:
    """Get a suspense preset by name.

    Args:
        name: Preset name, e.g. 'institutional_suspense'

    Returns:
        SuspenseProfile instance

    Raises:
        KeyError: if preset name doesn't exist
    """
    if name not in PRESETS:
        available = ", ".join(PRESETS.keys())
        raise KeyError(
            f"Unknown suspense preset: '{name}'. Available: {available}"
        )
    return PRESETS[name]


def list_presets() -> list[dict]:
    """List all available presets with basic info."""
    return [
        {
            "name": p.name,
            "display_name": p.display_name,
            "description": p.description,
            "weights": {"alpha": p.alpha, "beta": p.beta, "gamma": p.gamma},
        }
        for p in PRESETS.values()
    ]


def compute_suspense_intensity(
    profile: SuspenseProfile,
    info_asymmetry_score: float,
    time_asymmetry_score: float,
    consequence_asymmetry_score: float,
) -> float:
    """Compute suspense intensity.

    Args:
        profile: Suspense preset
        info_asymmetry_score: Info asymmetry score (0-100)
        time_asymmetry_score: Time asymmetry score (0-100)
        consequence_asymmetry_score: Consequence asymmetry score (0-100)

    Returns:
        Weighted suspense intensity (0-100)
    """
    return (
        profile.alpha * info_asymmetry_score
        + profile.beta * time_asymmetry_score
        + profile.gamma * consequence_asymmetry_score
    )


def build_suspense_directive(
    profile: SuspenseProfile,
    blueprint: dict | None = None,
) -> str:
    """Build suspense directive text from profile and blueprint.

    Used for injection into prompt_compiler static prefix.

    Args:
        profile: Suspense preset
        blueprint: Optional shot-level blueprint overrides

    Returns:
        Suspense directive text
    """
    hook_type = (
        blueprint.get("hook_type", profile.default_hook_type)
        if blueprint else profile.default_hook_type
    )
    tension_target = blueprint.get("tension_target", 50) if blueprint else 50

    parts = [f"## Suspense Engine ({profile.display_name})"]

    # 1. Global question
    if blueprint and blueprint.get("global_question"):
        parts.append(f"\nCore suspense question: {blueprint['global_question']}")

    # 2. Info asymmetry
    parts.append(f"\n### Info Asymmetry (weight {profile.alpha:.1f})")
    if profile.alpha >= 0.5:
        parts.append(
            "Reader must know more than the character. Use dramatic irony: "
            "let the reader examine every character through the lens of hidden knowledge."
        )
    elif profile.alpha >= 0.3:
        parts.append(
            "Use info gaps moderately: reader knows something, character doesn't. "
            "Create one every 2-3 chapters."
        )
    else:
        parts.append("Info gaps are not the focus. Reader and character discover together.")

    # 3. Time asymmetry
    parts.append(f"\n### Time Asymmetry (weight {profile.beta:.1f})")
    if profile.beta >= 0.4:
        parts.append(
            "Chapter ending must leave a sense of incompleteness. "
            "Do not give the reader a feeling of closure."
        )
    else:
        parts.append("Chapter endings can have natural closure. Unfinished action not required.")

    # 4. Consequence asymmetry
    parts.append(f"\n### Consequence Asymmetry (weight {profile.gamma:.1f})")
    if profile.gamma >= 0.4:
        parts.append(
            "Before any impactful information reaches the reader, "
            "first establish emotional groundwork through sensory details."
        )
        parts.append(
            "Reader must perceive danger or consequences that the character has not yet perceived."
        )
    else:
        parts.append(
            "Consequence perception and character perception can be synchronized. "
            "No mandatory preview."
        )

    # 5. Chapter hook type
    hook_type_descriptions = {
        "action_interrupt": "Physical action interrupt: character mid-action, cut at chapter end",
        "silence": "Silent ending: object/action/silence, no summary",
        "cliffhanger": "Cliffhanger: reveal shocking info, don't show consequences",
        "information_hook": "Info hook: give a key piece of info, don't show the whole picture",
    }
    parts.append(f"\n### Chapter Hook Type: {hook_type}")
    parts.append(hook_type_descriptions.get(hook_type, "undefined"))

    # 6. Number temperature
    if profile.number_temperature_required:
        parts.append("\n### Numbers Have Temperature")
        parts.append(
            "Every number (percentage, year, quantity, distance) must be followed "
            "in the same sentence or the next by a concrete person or object."
        )
        parts.append(
            "Never follow a number with abstract concepts (efficiency, resources, system, optimization)."
        )

    # 7. Explanation ban
    if profile.explanation_ban_intensity >= 70:
        parts.append("\n### Explanation Ban (strict)")
        parts.append(
            "No explanatory clauses. No 'this means', 'he realized', 'essentially', etc. "
            "Let facts, actions, and silence speak. Do not explain."
        )
    elif profile.explanation_ban_intensity >= 30:
        parts.append("\n### Explanation Ban (moderate)")
        parts.append(
            "Minimize explanatory clauses. If explanation is necessary, "
            "it must generate new questions, not close old ones."
        )

    # 8. Foreshadowing
    if profile.foreshadowing_density >= 70:
        parts.append("\n### Foreshadowing (dense)")
        parts.append(
            "When a key object first appears, show its effect or appearance first, "
            "delay naming by at least one sentence. At least 2-3 seeds per chapter."
        )
    elif profile.foreshadowing_density >= 30:
        parts.append("\n### Foreshadowing (moderate)")
        parts.append(
            "Important objects: show then name. 1-2 seeds per chapter."
        )

    # 9. Tension target
    if blueprint and "tension_target" in blueprint:
        parts.append(f"\n### Chapter Tension Target: {tension_target}/100")
        if tension_target >= 70:
            parts.append("High-tension chapter. Keep the pressure on, no room to breathe.")
        elif tension_target >= 40:
            parts.append("Medium-tension chapter. Build suspense but don't detonate.")
        else:
            parts.append("Buffer chapter. Let the reader digest, but don't fully relax.")

    return "\n".join(parts)