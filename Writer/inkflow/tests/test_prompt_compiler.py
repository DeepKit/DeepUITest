"""Test Prompt Compiler (Service 2)."""

from __future__ import annotations

import pytest

from inkflow.services.prompt_compiler import PromptCompiler, _estimate_tokens


class TestEstimateTokens:
    def test_chinese_text(self):
        """Chinese text: ~1.2 chars per token."""
        text = "右腿膝盖里像有把生锈的螺丝刀一圈圈往里拧"  # 19 Chinese chars
        tokens = _estimate_tokens(text)
        assert tokens > 0
        assert tokens < len(text)

    def test_english_text(self):
        """English text: ~3.5 chars per token."""
        text = "The quick brown fox jumps over the lazy dog"
        tokens = _estimate_tokens(text)
        assert 8 <= tokens <= 20

    def test_mixed_text(self):
        """Mixed Chinese + English."""
        text = "阿坤 woke up in 成都."
        tokens = _estimate_tokens(text)
        assert tokens > 0


class TestPromptCompiler:
    @pytest.fixture
    def compiler(self, db):
        return PromptCompiler(db)

    def test_compile_static_prefix(self, compiler):
        contract = {
            "identity": {"title": "分流", "genre": "文学小说"},
            "narrative_voice": {"pov": "多POV"},
            "hard_boundaries": {},
            "anti_reveal": {},
            "world_knowledge": {},
            "structure_rules": {},
            "anti_patterns": {},
            "style_locks": {},
            "motif_system": {},
            "creative_zones": {},
        }
        result = compiler.compile_static_prefix(contract, "意象师")
        assert isinstance(result, dict)
        assert "prefix_text" in result
        assert "prefix_length" in result
        assert "分流" in result["prefix_text"]

    def test_static_prefix_includes_exposition_replacement_rules(self, compiler):
        result = compiler.compile_static_prefix(
            {"identity": {"title": "分流"}, "narrative_voice": {},
             "hard_boundaries": {}, "anti_reveal": {}, "world_knowledge": {},
             "structure_rules": {}, "anti_patterns": {}, "style_locks": {},
             "motif_system": {}, "creative_zones": {}},
            "结构师",
        )
        prompt = result["prefix_text"]
        assert "显影规则" in prompt
        assert "动作" in prompt
        assert "物件" in prompt
        assert "身体" in prompt
        assert "环境后果" in prompt
        assert "不要解释系统为什么这样做" in prompt

    def test_compile_shot_prompt(self, compiler, setup_run):
        db = setup_run
        static_prefix = compiler.compile_static_prefix(
            {"identity": {"title": "分流"}, "narrative_voice": {},
             "hard_boundaries": {}, "anti_reveal": {}, "world_knowledge": {},
             "structure_rules": {}, "anti_patterns": {}, "style_locks": {},
             "motif_system": {}, "creative_zones": {}},
            "意象师",
        )
        result = compiler.compile_shot_prompt(
            "shot_01", "run_01", "意象师",
            static_prefix,
            {"must_land": {}, "anti_write": {}, "exit_to": None},
            previous_shots=[],
            motif_tasks={"required": [], "suggested": [], "forbidden": [], "allowed": []},
        )
        assert result is not None
        assert len(result) > 0
        row = db.execute(
            "SELECT prompt_id, writer_persona FROM writing_shot_prompts "
            "WHERE prompt_id = ?", (result,)
        ).fetchone()
        assert row is not None
        assert row["writer_persona"] == "意象师"

    def test_compile_with_previous_shots(self, compiler, setup_run):
        static_prefix = compiler.compile_static_prefix(
            {"identity": {"title": "分流"}, "narrative_voice": {},
             "hard_boundaries": {}, "anti_reveal": {}, "world_knowledge": {},
             "structure_rules": {}, "anti_patterns": {}, "style_locks": {},
             "motif_system": {}, "creative_zones": {}},
            "节奏师",
        )
        previous = [
            {"shot_index": 1, "text": "右腿膝盖里像有把生锈的螺丝刀。"},
            {"shot_index": 2, "text": "阿坤从枕头下面摸出保鲜膜。"},
        ]
        result = compiler.compile_shot_prompt(
            "shot_01", "run_01", "节奏师",
            static_prefix,
            {"must_land": {}, "anti_write": {}, "exit_to": None},
            previous_shots=previous,
            motif_tasks={"required": [], "suggested": [], "forbidden": [], "allowed": []},
        )
        assert result is not None

    def test_get_shot_prompt(self, compiler, setup_run):
        static_prefix = compiler.compile_static_prefix(
            {"identity": {"title": "分流"}, "narrative_voice": {},
             "hard_boundaries": {}, "anti_reveal": {}, "world_knowledge": {},
             "structure_rules": {}, "anti_patterns": {}, "style_locks": {},
             "motif_system": {}, "creative_zones": {}},
            "意象师",
        )
        pid = compiler.compile_shot_prompt(
            "shot_01", "run_01", "意象师",
            static_prefix,
            {"must_land": {}, "anti_write": {}, "exit_to": None},
            previous_shots=[],
            motif_tasks={"required": [], "suggested": [], "forbidden": [], "allowed": []},
        )
        prompt = compiler.get_shot_prompt("shot_01", "run_01", "意象师")
        assert prompt is not None
        assert prompt["writer_persona"] == "意象师"

    def test_chapter_setup_directives_enter_prompt(self, compiler, setup_run):
        static_prefix = compiler.compile_static_prefix(
            {"identity": {"title": "分流"}, "narrative_voice": {},
             "hard_boundaries": {}, "anti_reveal": {}, "world_knowledge": {},
             "structure_rules": {}, "anti_patterns": {}, "style_locks": {},
             "motif_system": {}, "creative_zones": {}},
            "意象师",
        )
        pid = compiler.compile_shot_prompt(
            "shot_01", "run_01", "意象师",
            static_prefix,
            {
                "must_land": {"event": "阿坤出门"},
                "anti_write": {},
                "exit_to": None,
                "chapter_setup": {
                    "shot": {
                        "type_roles": ["hook"],
                        "anti_patterns": ["禁止长段系统议论"],
                    },
                    "exposition_gate": {
                        "enabled": True,
                        "rule": "概念只能通过后果显影。",
                        "forbidden_phrases": ["系统并不恶意"],
                        "repair_instruction": "改成动作、物件或沉默。",
                    },
                    "chapter_hook": {
                        "required": True,
                        "requirements": ["最后一句必须是未完成动作"],
                    },
                },
                "task_card": {
                    "title": "玻璃里的保鲜膜",
                    "pov": "郑坤",
                    "must_land": "郑坤在三环边缘看到边界提示。",
                    "hard_facts": ["外江向内侵蚀内江"],
                    "type_roles": ["hook"],
                    "hook_required": True,
                    "forbidden_phrases": ["系统并不恶意"],
                    "outline": "郑坤在玻璃反光里看到保鲜膜。",
                },
            },
            previous_shots=[],
            motif_tasks={"required": [], "suggested": [], "forbidden": [], "allowed": []},
        )

        row = setup_run.execute(
            "SELECT assembled_prompt FROM writing_shot_prompts WHERE prompt_id = ?",
            (pid,),
        ).fetchone()
        prompt = row["assembled_prompt"]
        assert "章前校准" in prompt
        assert "系统并不恶意" in prompt
        assert "禁止长段系统议论" in prompt
        assert "最后一句必须是未完成动作" in prompt
        assert "UTF-8 字符串大小不少于约 1.2KB" in prompt
        assert "你不需要精确计算字数" in prompt
        assert "Shot Task Card" in prompt
        assert "玻璃里的保鲜膜" in prompt
        assert "外江向内侵蚀内江" in prompt
        assert "屏幕通知、排队阻滞、物件变化、身体反应" in prompt

    def test_compile_shot_prompt_updates_existing_prompt(self, compiler, setup_run):
        static_prefix = compiler.compile_static_prefix(
            {"identity": {"title": "分流"}, "narrative_voice": {},
             "hard_boundaries": {}, "anti_reveal": {}, "world_knowledge": {},
             "structure_rules": {}, "anti_patterns": {}, "style_locks": {},
             "motif_system": {}, "creative_zones": {}},
            "意象师",
        )

        compiler.compile_shot_prompt(
            "shot_01", "run_01", "意象师",
            static_prefix,
            {
                "must_land": {"event": "旧事件"},
                "anti_write": {},
                "exit_to": None,
                "task_card": {
                    "title": "旧标题",
                    "pov": "郑坤",
                    "must_land": "旧事件",
                    "outline": "旧大纲",
                },
            },
        )
        compiler.compile_shot_prompt(
            "shot_01", "run_01", "意象师",
            static_prefix,
            {
                "must_land": {"event": "新事件"},
                "anti_write": {},
                "exit_to": None,
                "task_card": {
                    "title": "新标题",
                    "pov": "郑坤",
                    "must_land": "新事件",
                    "outline": "新大纲",
                },
            },
        )

        rows = setup_run.execute(
            "SELECT assembled_prompt FROM writing_shot_prompts "
            "WHERE run_id = 'run_01' AND shot_id = 'shot_01' AND writer_persona = '意象师'"
        ).fetchall()

        assert len(rows) == 1
        assert "新标题" in rows[0]["assembled_prompt"]
        assert "旧标题" not in rows[0]["assembled_prompt"]

    def test_different_personas(self, compiler, setup_run):
        static_prefix = compiler.compile_static_prefix(
            {"identity": {"title": "分流"}, "narrative_voice": {},
             "hard_boundaries": {}, "anti_reveal": {}, "world_knowledge": {},
             "structure_rules": {}, "anti_patterns": {}, "style_locks": {},
             "motif_system": {}, "creative_zones": {}},
            "意象师",
        )
        pid1 = compiler.compile_shot_prompt(
            "shot_01", "run_01", "意象师",
            static_prefix,
            {"must_land": {}, "anti_write": {}, "exit_to": None},
            previous_shots=[],
            motif_tasks={"required": [], "suggested": [], "forbidden": [], "allowed": []},
        )
        pid2 = compiler.compile_shot_prompt(
            "shot_01", "run_01", "节奏师",
            static_prefix,
            {"must_land": {}, "anti_write": {}, "exit_to": None},
            previous_shots=[],
            motif_tasks={"required": [], "suggested": [], "forbidden": [], "allowed": []},
        )
        assert pid1 != pid2

    def test_llm6_context_window_order(self, compiler, setup_run):
        """LLM-6: 上下文窗口顺序与设计一致 — 静态前缀 → 契约 → 前文 → 锚点 → 意象 → 反例."""
        db = setup_run
        static_prefix = compiler.compile_static_prefix(
            {"identity": {"title": "分流"}, "narrative_voice": {},
             "hard_boundaries": {"no_magic": True}, "anti_reveal": {},
             "world_knowledge": {}, "structure_rules": {}, "anti_patterns": {},
             "style_locks": {}, "motif_system": {}, "creative_zones": {}},
            "意象师",
        )
        previous = [
            {"shot_index": 1, "text": "N-5 摘要文本。它很短。"},
            {"shot_index": 2, "text": "N-4 摘要文本。"},
            {"shot_index": 3, "text": "N-3 摘要文本。"},
            {"shot_index": 4, "text": "N-2 全文。阿坤醒了。窗外的天还是灰的。他从枕头下面摸出保鲜膜。"},
            {"shot_index": 5, "text": "N-1 全文。他走到门口，打开了门。"},
        ]
        fact_anchors = [
            {"anchor_type": "character_state", "anchor_key": "cs:1", "anchor_value": "阿坤醒了"},
            {"anchor_type": "object_location", "anchor_key": "ol:1", "anchor_value": "保鲜膜放枕头下"},
        ]
        motif_tasks = {"required": ["窗口意象"], "suggested": [], "forbidden": [], "allowed": []}

        pid = compiler.compile_shot_prompt(
            "shot_01", "run_01", "意象师",
            static_prefix,
            {"must_land": {"event": "阿坤出门"}, "anti_write": {}, "exit_to": None},
            previous_shots=previous,
            fact_anchors=fact_anchors,
            motif_tasks=motif_tasks,
        )
        assert pid is not None

        row = db.execute(
            "SELECT assembled_prompt FROM writing_shot_prompts WHERE prompt_id = ?",
            (pid,),
        ).fetchone()
        assert row is not None
        prompt = row["assembled_prompt"] or ""

        # 验证各 section 出现顺序
        static_pos = prompt.find("意象师")
        contract_pos = prompt.find("必须落地")
        prev_pos = prompt.find("前文上下文")
        anchor_pos = prompt.find("事实锚点")
        motif_pos = prompt.find("意象任务")

        assert static_pos >= 0, "缺少静态前缀"
        assert contract_pos >= 0, "缺少当前 Shot 契约"
        assert prev_pos >= 0, "缺少前文上下文 (前文上下文)"
        assert anchor_pos >= 0, "缺少事实锚点"
        assert motif_pos >= 0, "缺少意象任务"

        # 验证顺序: 静态前缀 < 契约 < 前文 < 锚点 < 意象
        assert static_pos < contract_pos < prev_pos < anchor_pos < motif_pos, (
            f"上下文窗口顺序错误: "
            f"static={static_pos}, contract={contract_pos}, "
            f"prev={prev_pos}, anchor={anchor_pos}, motif={motif_pos}"
        )

        # 验证前文上下文 section 出现在 prompt 中（可能包含摘要/完整）
        prev_ctx_pos = prompt.find("前文上下文")
        assert prev_ctx_pos >= 0, "缺少前文上下文 section"
        # 验证最近 2 个 shot 的内容出现在前文上下文中
        prev_section = prompt[prev_ctx_pos:prev_ctx_pos + 500]
        assert "N-1" in prev_section, "N-1 应在前文上下文中"
        assert "N-2" in prev_section, "N-2 应在前文上下文中"
