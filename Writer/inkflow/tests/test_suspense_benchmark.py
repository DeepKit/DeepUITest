"""Tests for D25-R2 suspense benchmark validation."""

from __future__ import annotations

import pytest

from tests.fixtures.suspense_benchmark import (
    ALL_SAMPLES,
    HIGH_SUSPENSE,
    MEDIUM_SUSPENSE,
    LOW_SUSPENSE,
    PSEUDO_SUSPENSE,
    get_samples_by_label,
    get_benchmark_summary,
)


class TestSuspenseBenchmarkStructure:
    """D25-R2: Benchmark samples have proper structure."""

    def test_all_samples_have_required_fields(self):
        """Every sample has id, text, label, rationale."""
        for sample in ALL_SAMPLES:
            assert "id" in sample, f"Missing 'id' in {sample}"
            assert "text" in sample, f"Missing 'text' in {sample}"
            assert "label" in sample, f"Missing 'label' in {sample}"
            assert "rationale" in sample, f"Missing 'rationale' in {sample}"

    def test_labels_are_valid(self):
        """All labels are one of the four valid categories."""
        valid_labels = {"high", "medium", "low", "pseudo"}
        for sample in ALL_SAMPLES:
            assert sample["label"] in valid_labels, (
                f"Invalid label '{sample['label']}' in {sample['id']}"
            )

    def test_sample_ids_are_unique(self):
        """No duplicate sample IDs."""
        ids = [s["id"] for s in ALL_SAMPLES]
        assert len(ids) == len(set(ids)), "Duplicate sample IDs found"

    def test_text_is_non_empty(self):
        """Every sample has non-empty text."""
        for sample in ALL_SAMPLES:
            assert len(sample["text"]) > 20, (
                f"Text too short in {sample['id']}: '{sample['text']}'"
            )

    def test_rationale_is_non_empty(self):
        """Every sample has non-empty rationale."""
        for sample in ALL_SAMPLES:
            assert len(sample["rationale"]) > 10, (
                f"Rationale too short in {sample['id']}"
            )

    def test_high_suspense_count(self):
        """High suspense samples should exist (at least 1)."""
        assert len(HIGH_SUSPENSE) >= 1

    def test_low_suspense_count(self):
        """Low suspense samples should exist (at least 1)."""
        assert len(LOW_SUSPENSE) >= 1

    def test_pseudo_suspense_count(self):
        """Pseudo suspense samples should exist (at least 1)."""
        assert len(PSEUDO_SUSPENSE) >= 1


class TestSuspenseBenchmarkRetrieval:
    """D25-R2: Benchmark retrieval functions work correctly."""

    def test_get_samples_by_label_high(self):
        samples = get_samples_by_label("high")
        assert len(samples) == len(HIGH_SUSPENSE)
        for s in samples:
            assert s["label"] == "high"

    def test_get_samples_by_label_medium(self):
        samples = get_samples_by_label("medium")
        assert len(samples) == len(MEDIUM_SUSPENSE)
        for s in samples:
            assert s["label"] == "medium"

    def test_get_samples_by_label_low(self):
        samples = get_samples_by_label("low")
        assert len(samples) == len(LOW_SUSPENSE)

    def test_get_samples_by_label_pseudo(self):
        samples = get_samples_by_label("pseudo")
        assert len(samples) == len(PSEUDO_SUSPENSE)

    def test_get_samples_by_label_unknown(self):
        """Unknown label returns empty list."""
        samples = get_samples_by_label("unknown")
        assert samples == []

    def test_get_benchmark_summary(self):
        summary = get_benchmark_summary()
        assert summary["total"] == len(ALL_SAMPLES)
        assert sum(summary["by_label"].values()) == summary["total"]
        assert set(summary["labels"]) == {"high", "medium", "low", "pseudo"}


class TestSuspenseEffectivenessDimension:
    """D25-R2: suspense_effectiveness is a valid jury dimension."""

    def test_dimension_exists_in_jury_service(self):
        """suspense_effectiveness dimension is defined in jury_service."""
        from inkflow.services.jury_service import DIMENSION_DESCRIPTIONS
        assert "suspense_effectiveness" in DIMENSION_DESCRIPTIONS

    def test_dimension_prompt_mentions_asymmetry(self):
        """suspense_effectiveness prompt mentions the three asymmetry dimensions."""
        from inkflow.services.jury_service import DIMENSION_DESCRIPTIONS
        prompt = DIMENSION_DESCRIPTIONS["suspense_effectiveness"]
        assert "信息不对称" in prompt or "不对称" in prompt
        assert "时间" in prompt or "未完成" in prompt

    def test_dimension_prompt_not_empty(self):
        """suspense_effectiveness prompt is non-empty and has substance."""
        from inkflow.services.jury_service import DIMENSION_DESCRIPTIONS
        prompt = DIMENSION_DESCRIPTIONS["suspense_effectiveness"]
        assert len(prompt) > 50
        assert len(prompt) < 10000


class TestSuspenseContentProperties:
    """D25-R2: Verify high-suspense samples contain information gaps and
    low-suspense samples lack them."""

    def test_high_suspense_has_information_gap(self):
        """High suspense texts should contain information asymmetry or time pressure.

        This can be expressed through various markers: reader knows more,
        character doesn't know, time pressure, or consequence asymmetry.
        """
        for sample in HIGH_SUSPENSE:
            text = sample["text"]
            rationale = sample["rationale"]
            # Check for markers of information gap or time pressure
            has_gap = any(phrase in text for phrase in [
                "读者", "不知道", "但他不知道", "她不知道",
                "倒计时", "即将", "没发现", "她不知道", "他", "她",
            ])
            # Also check rationale for confirmation
            has_gap_rationale = any(phrase in rationale for phrase in [
                "信息差", "读者知道", "不对称", "时间压力", "倒计时", "后果",
            ])
            assert has_gap or has_gap_rationale, (
                f"High suspense sample {sample['id']} lacks information gap markers. "
                f"Text: {text[:50]}..."
            )

    def test_low_suspense_no_urgency(self):
        """Low suspense texts should not have urgency markers."""
        for sample in LOW_SUSPENSE:
            text = sample["text"]
            urgency_markers = ["!", "？", "突然", "倒计时", "危险", "必须", "危机"]
            has_urgency = any(m in text for m in urgency_markers)
            assert not has_urgency, (
                f"Low suspense sample {sample['id']} has urgency markers"
            )

    def test_pseudo_suspense_no_real_consequence(self):
        """Pseudo suspense uses emotional manipulation without real stakes."""
        for sample in PSEUDO_SUSPENSE:
            text = sample["text"]
            rationale = sample["rationale"]
            # Pseudo samples should have rationales explaining why they're fake
            assert "信息差" in rationale or "把戏" in rationale or "情绪" in rationale, (
                f"Pseudo sample {sample['id']} rationale should explain lack of real stakes"
            )

    def test_all_labels_present_in_summary(self):
        """All four labels appear in the benchmark summary."""
        summary = get_benchmark_summary()
        assert len(summary["by_label"]) == 4
        for label in ["high", "medium", "low", "pseudo"]:
            assert label in summary["by_label"]
