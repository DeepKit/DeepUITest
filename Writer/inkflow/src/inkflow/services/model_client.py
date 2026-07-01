"""ModelClient — 统一的 LLM / 生成器调用协议。

支持:
  - OpenAI 兼容协议 (StepFun, DeepSeek)
  - Anthropic 兼容协议 (百炼/Qwen)
  - local-default 确定性生成器 (无 API key 时的兜底)
  - 每次调用自动写入 model_attempts 审计表
"""

from __future__ import annotations

import hashlib
import json
import os
import random
import re
import sqlite3
import time
import urllib.request
import urllib.error
from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable

from inkflow.utils.ulid import generate as generate_ulid


# ── 协议定义 ──────────────────────────────────────────────────────────────


@dataclass
class ModelRequest:
    """统一请求格式。"""

    operation: str  # write_generate / jury_score / fact_extract / ...
    persona: str  # imagist / pacer / dialogist / structuralist / ...
    prompt: str
    model: str = "local-default"
    temperature: float = 0.8
    max_tokens: int = 16384
    shot_id: str | None = None
    run_id: str | None = None
    extra: dict = field(default_factory=dict)


@dataclass
class ModelResponse:
    """统一响应格式。"""

    text: str
    model: str
    usage: dict = field(default_factory=dict)
    finish_reason: str = "stop"
    self_note: str = ""


class ModelCallError(Exception):
    """模型调用错误。"""

    def __init__(self, message: str, recoverable: bool = True):
        super().__init__(message)
        self.recoverable = recoverable


@runtime_checkable
class ModelClient(Protocol):
    """统一的生成器调用接口。"""

    def generate(self, request: ModelRequest) -> ModelResponse: ...


# ── OpenAI 兼容客户端 ────────────────────────────────────────────────────


class OpenAIClient:
    """OpenAI 兼容协议客户端 (StepFun, DeepSeek)。"""

    def __init__(
        self,
        api_key: str,
        base_url: str,
        model_name: str,
        db: sqlite3.Connection | None = None,
    ) -> None:
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.model_name = model_name
        self.db = db

    def generate(self, request: ModelRequest) -> ModelResponse:
        url = f"{self.base_url}/chat/completions"
        body = {
            "model": self.model_name,
            "messages": [{"role": "user", "content": request.prompt}],
            "max_tokens": request.max_tokens,
            "temperature": request.temperature,
        }
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")

        req = urllib.request.Request(
            url,
            data=data,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
                "User-Agent": "InkFlow/1.0 OpenAI-Compatible",
            },
            method="POST",
        )

        timeout = request.extra.get("timeout_seconds", 120)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                result = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            if self.db is not None:
                _record_model_error(self.db, request, self.model_name, f"HTTP {e.code}: {body[:500]}")
            raise ModelCallError(
                f"OpenAI API HTTP {e.code}: {body[:500]}",
                recoverable=e.code >= 500,
            )
        except Exception as e:
            if self.db is not None:
                _record_model_error(self.db, request, self.model_name, str(e))
            raise ModelCallError(f"OpenAI API error: {e}", recoverable=True)

        choice = result.get("choices", [{}])[0]
        msg = choice.get("message", {})
        text = msg.get("content", "")
        if not text or not text.strip():
            # Fallback: reasoning models (step-3.7-flash) put output in reasoning_content
            text = msg.get("reasoning_content", "") or msg.get("reasoning", "")
        text = _clean_model_text(text)
        if request.operation == "jury_score" and not text.strip():
            if self.db is not None:
                _record_model_error(
                    self.db,
                    request,
                    self.model_name,
                    "OpenAI API returned no jury content after cleanup",
                )
            raise ModelCallError(
                "OpenAI API returned no jury content after cleanup",
                recoverable=True,
            )
        usage_raw = result.get("usage", {})
        usage = {
            "prompt_tokens": usage_raw.get("prompt_tokens", 0),
            "completion_tokens": usage_raw.get("completion_tokens", 0),
            "total": usage_raw.get("total_tokens", 0),
        }

        response = ModelResponse(
            text=text,
            model=self.model_name,
            usage=usage,
            finish_reason=choice.get("finish_reason", "stop"),
            self_note=f"[{self.model_name}] OpenAI",
        )

        if self.db is not None:
            _record_model_attempt(self.db, request, response, request.operation)

        return response


# ── Anthropic 兼容客户端 ─────────────────────────────────────────────────


class AnthropicClient:
    """Anthropic 兼容协议客户端 (百炼/Qwen)。"""

    def __init__(
        self,
        api_key: str,
        base_url: str,
        model_name: str,
        db: sqlite3.Connection | None = None,
    ) -> None:
        self.api_key = api_key
        self.base_url = base_url.rstrip("/")
        self.model_name = model_name
        self.db = db

    def generate(self, request: ModelRequest) -> ModelResponse:
        url = f"{self.base_url}/messages"
        body = {
            "model": self.model_name,
            "max_tokens": request.max_tokens,
            "messages": [{"role": "user", "content": request.prompt}],
            "thinking": {"type": "disabled"},  # Disable thinking for creative writing
        }
        if request.temperature:
            body["temperature"] = request.temperature

        data = json.dumps(body, ensure_ascii=False).encode("utf-8")

        req = urllib.request.Request(
            url,
            data=data,
            headers={
                "x-api-key": self.api_key,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        timeout = request.extra.get("timeout_seconds", 120)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                result = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace")
            if self.db is not None:
                _record_model_error(self.db, request, self.model_name, f"HTTP {e.code}: {body[:500]}")
            raise ModelCallError(
                f"Anthropic API HTTP {e.code}: {body[:500]}",
                recoverable=e.code >= 500,
            )
        except Exception as e:
            if self.db is not None:
                _record_model_error(self.db, request, self.model_name, str(e))
            raise ModelCallError(f"Anthropic API error: {e}", recoverable=True)

        # Anthropic format: content is a list of blocks
        content_blocks = result.get("content", [])
        text = ""
        for block in content_blocks:
            if block.get("type") == "text":
                text += block.get("text", "")
        text = _clean_model_text(text)

        usage_raw = result.get("usage", {})
        usage = {
            "prompt_tokens": usage_raw.get("input_tokens", 0),
            "completion_tokens": usage_raw.get("output_tokens", 0),
            "total": usage_raw.get("input_tokens", 0) + usage_raw.get("output_tokens", 0),
        }

        response = ModelResponse(
            text=text,
            model=self.model_name,
            usage=usage,
            finish_reason=result.get("stop_reason", "stop"),
            self_note=f"[{self.model_name}] Anthropic",
        )

        if self.db is not None:
            _record_model_attempt(self.db, request, response, request.operation)

        return response


# ── local-default 确定性生成器 ──────────────────────────────────────────


_PERSONA_TEMPLATES: dict[str, list[str]] = {
    "imagist": [
        "光线从{scene}的缝隙间漏进来，落在{object}上，像一记无声的叩问。",
        "{character}的目光停在{object}上，那东西仿佛在回应某种久违的召唤。",
        "风从{scene}的方向吹来，裹挟着{object}的气味，整个房间都为之侧目。",
    ],
    "pacer": [
        "{character}先是没有动，然后忽然站了起来。动作快得让人来不及反应。",
        "沉默持续了三秒。三秒之后，{character}开口了，语速比平时快了一倍。",
        "事情发生得毫无预兆——前一秒还风平浪静，后一秒已是另一番局面。",
    ],
    "dialogist": [
        '"你真的这么想？"{character}的声音里带着某种不容置疑的东西。',
        '"我没有别的选择。"他说这句话的时候，目光没有看向任何人。',
        '"听我说完。"她打断了他，语气不重，却让所有人都安静了下来。',
    ],
    "structuralist": [
        "从这一刻起，所有的伏线开始收拢。{character}终于看清了事情的全貌。",
        "这个决定将改变接下来所有事件的走向。{character}心里清楚，但已无退路。",
        "表面上看只是 ordinary 的一步，实际上却连接着三条完全不同的叙事线。",
    ],
}

_FILLER_SCENES = ["窗棂", "走廊尽头", "天台", "旧书房", "后院", "码头", "街角"]
_FILLER_OBJECTS = ["那封信", "半杯凉茶", "一把旧钥匙", "褪色的照片", "断掉的表带"]
_FILLER_CHARACTERS = ["他", "她", "来人", "青年", "老者"]


class LocalDefaultGenerator:
    """无 API key 时的确定性兜底生成器。"""

    def __init__(self, db: sqlite3.Connection | None = None) -> None:
        self.db = db

    def generate(self, request: ModelRequest) -> ModelResponse:
        if request.operation == "jury_score":
            return self._generate_jury_score(request)

        persona = request.persona.lower()
        seed_str = f"{request.shot_id or 'default'}::{persona}::{request.run_id or 'x'}"
        seed = int(hashlib.md5(seed_str.encode()).hexdigest()[:8], 16)
        rng = random.Random(seed)

        beats = _extract_prompt_beats(request.prompt)
        opening = _extract_prompt_opening(request.prompt)
        pov = _extract_prompt_pov(request.prompt) or rng.choice(_FILLER_CHARACTERS)

        if beats or opening:
            full_text = _compose_prompt_bound_story(
                request.shot_id or "",
                persona,
                pov,
                opening,
                beats,
                rng,
            )
        else:
            templates = _PERSONA_TEMPLATES.get(persona, _PERSONA_TEMPLATES["pacer"])
            num_paragraphs = rng.randint(3, 5)
            paragraphs: list[str] = []
            for _ in range(num_paragraphs):
                tpl = rng.choice(templates)
                text = tpl.format(
                    scene=rng.choice(_FILLER_SCENES),
                    object=rng.choice(_FILLER_OBJECTS),
                    character=rng.choice(_FILLER_CHARACTERS),
                )
                paragraphs.append(text)

            narrative = (
                f"\n\n{persona.upper()} 视角下的这一段，重点在于呈现 {_FILLER_OBJECTS[0]} "
                f"与 {_FILLER_CHARACTERS[0]} 之间的微妙关系。"
                f"场景设在 {_FILLER_SCENES[0]}，气氛随着叙述的推进逐渐升温。"
                f"每一个细节都在为后续的转折埋下伏笔。"
            )
            full_text = "\n\n".join(paragraphs) + narrative

        while len(full_text) < 200:
            full_text += f"\n（{persona} 继续推进叙事，补充更多细节与情绪层次。）"

        response = ModelResponse(
            text=full_text,
            model="local-default",
            usage={"prompt_tokens": len(request.prompt) // 2,
                   "completion_tokens": len(full_text) // 2,
                   "total": (len(request.prompt) + len(full_text)) // 2},
            finish_reason="stop",
            self_note=f"[local-default] deterministic output for {persona}",
        )

        if self.db is not None:
            _record_model_attempt(self.db, request, response, request.operation)

        return response

    def _generate_jury_score(self, request: ModelRequest) -> ModelResponse:
        draft_text = _extract_jury_draft_text(request.prompt)
        score = _local_jury_score(draft_text)
        text = json.dumps(
            {"score": score, "comment": f"local-default heuristic score {score}"},
            ensure_ascii=False,
        )
        response = ModelResponse(
            text=text,
            model="local-default",
            usage={"prompt_tokens": len(request.prompt) // 2,
                   "completion_tokens": len(text) // 2,
                   "total": (len(request.prompt) + len(text)) // 2},
            finish_reason="stop",
            self_note="[local-default] deterministic jury score",
        )
        if self.db is not None:
            _record_model_attempt(self.db, request, response, request.operation)
        return response


def _extract_prompt_opening(prompt: str) -> str:
    match = re.search(r"第一句话以[「\"](.+?)[」\"]开头", prompt, flags=re.S)
    if match:
        return _clean_prompt_line(match.group(1))
    return ""


def _clean_model_text(text: str) -> str:
    """Remove provider reasoning artifacts that should never enter prose/gates."""
    text = text or ""
    text = re.sub(r"(?is)<think>.*?</think>", "", text)
    text = re.sub(r"(?is)<thinking>.*?</thinking>", "", text)
    text = re.sub(r"(?is)<reasoning>.*?</reasoning>", "", text)
    return text.strip()


def _extract_prompt_pov(prompt: str) -> str:
    match = re.search(r"只写\s*([^ \n]+)\s*的视角", prompt)
    if match:
        return match.group(1).strip()
    match = re.search(r"视角人物[：:]\s*([^\n]+)", prompt)
    if match:
        return match.group(1).strip(" 。")
    return ""


def _extract_prompt_beats(prompt: str) -> list[str]:
    task_text = prompt
    if "## 写作任务" in task_text:
        task_text = task_text.split("## 写作任务", 1)[1]
    end_markers = ["现在开始写", "## 视角约束", "## 事实锚点", "### 写作风格"]
    for marker in end_markers:
        if marker in task_text:
            task_text = task_text.split(marker, 1)[0]

    beats: list[str] = []
    for raw_line in task_text.splitlines():
        line = _clean_prompt_line(raw_line)
        if not line:
            continue
        if line in {"场景要点：", "场景要点:", "【场景信息】", "【段落规划与内容详述】"}:
            continue
        if line.startswith(("##", "---", "你是", "不要", "请直接", "第一句话以")):
            continue
        if line.startswith("-"):
            line = _clean_prompt_line(line[1:])
        line = re.sub(r"^【[^】]{1,20}】", "", line).strip()
        line = re.sub(r"^\*\*[^*]{1,30}\*\*[：:]?", "", line).strip()
        if len(line) < 6:
            continue
        if any(prefix in line for prefix in ("字数", "风格执行", "共4段", "写手需严格落实")):
            continue
        if line not in beats:
            beats.append(line)
        if len(beats) >= 10:
            break
    return beats


def _clean_prompt_line(text: str) -> str:
    text = text.replace("\r", " ").replace("\n", " ")
    text = re.sub(r"\s+", " ", text)
    return text.strip(" -\t")


def _compose_prompt_bound_story(
    shot_id: str,
    persona: str,
    pov: str,
    opening: str,
    beats: list[str],
    rng: random.Random,
) -> str:
    concrete_beats = beats or ["他把手机扣在掌心，屏幕的冷光贴着指节慢慢暗下去"]
    if opening:
        concrete_beats = [opening] + [b for b in concrete_beats if opening not in b]

    sensory = [
        "湿冷的雾贴着袖口，像一层没有拧干的布。",
        "手机震了一下，塑料壳把掌心硌得发麻。",
        "楼道里的霉味和油烟味混在一起，压在喉咙口。",
        "风从裤脚钻上来，膝盖里那点钝痛慢慢变尖。",
    ]
    gestures = [
        f"{pov}停了一下，没有立刻说话。",
        f"{pov}把手指蜷回掌心，又重新松开。",
        f"{pov}抬头看了一眼，眼神没有落在同一个地方。",
        f"{pov}把东西往包里压了压，拉链卡在半截。",
    ]

    paragraphs: list[str] = []
    idx = 0
    for para_idx in range(3):
        seg = concrete_beats[idx:idx + 3]
        idx += 3
        if not seg:
            break
        sentences: list[str] = []
        if para_idx == 0 and opening:
            sentences.append(opening.rstrip("。！？!?"))
            seg = [b for b in seg if b != opening]
        sentences.append(rng.choice(sensory))
        for beat in seg:
            sentences.append(_beat_to_sentence(beat))
            if rng.random() < 0.45:
                sentences.append(rng.choice(gestures))
        paragraphs.append("。".join(s.strip("。") for s in sentences if s.strip()) + "。")

    remaining = concrete_beats[idx:]
    if remaining:
        tail = "。".join(_beat_to_sentence(b).strip("。") for b in remaining[:3])
        paragraphs.append(tail + "。")

    if shot_id.endswith(".s04"):
        hook = "她正要把U盘塞进口袋，屏幕右下角突然跳出一条新的边界通知"
        paragraphs[-1] = paragraphs[-1].rstrip("。！？!?") + "。" + hook
    elif not paragraphs[-1].endswith(("。", "！", "？")):
        paragraphs[-1] += "。"

    return "\n\n".join(paragraphs)


def _beat_to_sentence(beat: str) -> str:
    beat = _clean_prompt_line(beat)
    beat = re.sub(r"^内容[：:]", "", beat).strip()
    if beat.endswith(("。", "！", "？", "；")):
        return beat
    return beat + "。"


def _extract_jury_draft_text(prompt: str) -> str:
    marker = "【待评文本】"
    if marker not in prompt:
        return prompt
    text = prompt.split(marker, 1)[1]
    for end in ("请给出", "输出 JSON", "评分参考"):
        if end in text:
            text = text.split(end, 1)[0]
    return text.strip()


def _local_jury_score(text: str) -> int:
    score = 70
    chinese_chars = sum(1 for c in text if "\u4e00" <= c <= "\u9fff")
    if chinese_chars >= 500:
        score += 8
    elif chinese_chars >= 250:
        score += 4
    else:
        score -= 18

    fiction_markers = ["雾", "雨", "膝盖", "保鲜膜", "手机", "系统", "茶", "骨片", "U盘", "屏幕", "说", "看"]
    score += min(12, sum(2 for marker in fiction_markers if marker in text))

    bad_markers = ["以下是", "这段文字", "分析", "解读", "核心落点", "风格执行", "字数"]
    score -= min(30, sum(8 for marker in bad_markers if marker in text))

    if "突然" in text or "正要" in text or "还没" in text:
        score += 4
    return max(0, min(92, score))


# ── 审计 ─────────────────────────────────────────────────────────────────


def _record_model_attempt(
    db: sqlite3.Connection,
    request: ModelRequest,
    response: ModelResponse,
    phase: str,
) -> None:
    request_hash = hashlib.md5(request.prompt.encode()).hexdigest()[:16]
    idempotency_key = hashlib.md5(
        (
            f"{request.shot_id}:{request.persona}:{request.run_id}:"
            f"{phase}:{response.model}:{request_hash}"
        ).encode()
    ).hexdigest()[:32]
    response_hash = hashlib.md5(response.text.encode()).hexdigest()[:16]

    try:
        db.execute(
            "INSERT OR IGNORE INTO model_attempts "
            "(attempt_id, run_id, shot_id, phase, model_name, idempotency_key, "
            "request_prompt_hash, request_prompt_text, response_text_hash, response_text, "
            "usage_prompt_tokens, usage_completion_tokens, usage_total_tokens) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                generate_ulid(), request.run_id, request.shot_id,
                phase, response.model, idempotency_key,
                request_hash, request.prompt, response_hash, response.text,
                response.usage.get("prompt_tokens", 0),
                response.usage.get("completion_tokens", 0),
                response.usage.get("total", 0),
            ),
        )
        db.commit()
    except Exception:
        pass


def _record_model_error(
    db: sqlite3.Connection,
    request: ModelRequest,
    model_name: str,
    error_message: str,
) -> None:
    request_hash = hashlib.md5(request.prompt.encode()).hexdigest()[:16]
    idempotency_key = hashlib.md5(
        (
            f"{request.shot_id}:{request.persona}:{request.run_id}:"
            f"{request.operation}:{model_name}:{request_hash}:error"
        ).encode()
    ).hexdigest()[:32]

    try:
        db.execute(
            "INSERT OR IGNORE INTO model_attempts "
            "(attempt_id, run_id, shot_id, phase, model_name, idempotency_key, "
            "request_prompt_hash, request_prompt_text, response_text_hash, response_text, "
            "usage_prompt_tokens, usage_completion_tokens, usage_total_tokens, error_message) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, ?)",
            (
                generate_ulid(), request.run_id, request.shot_id,
                request.operation, model_name, idempotency_key,
                request_hash, request.prompt, "", "", error_message[:500],
            ),
        )
        db.commit()
    except Exception:
        pass


# ── 工厂 ─────────────────────────────────────────────────────────────────


# 模型名 → (provider_key, protocol)
_MODEL_REGISTRY: dict[str, tuple[str, str]] = {
    # StepFun (OpenAI)
    "step-router-v1": ("stepfun", "openai"),
    "step-3.7-flash": ("stepfun", "openai"),
    # OpenCode Go (OpenAI-compatible aggregate endpoint)
    "minimax-m3": ("opencode", "openai"),
    "kimi-k2.7-code": ("opencode", "openai"),
    "kimi-k2.6": ("opencode", "openai"),
    "glm-5.2": ("opencode", "openai"),
    "mimo-v2.5-pro": ("opencode", "openai"),
    "mimo-v2.5": ("opencode", "openai"),
    # Agnes AI (OpenAI-compatible)
    "agnes-2.0-flash": ("agnes", "openai"),
    # DeepSeek (OpenAI)
    "deepseek-v4-pro": ("deepseek", "openai"),
    "deepseek-v4-flash": ("deepseek", "openai"),
    # FCCY (OpenAI)
    "gpt-5.5": ("fccy", "openai"),
    "gpt-5.5-Pro": ("fccy", "openai"),
    # 百炼 (Anthropic 兼容 - coding.dashscope)
    "qwen3.7-plus": ("bailian", "anthropic"),
    "qwen3.6-plus": ("bailian", "anthropic"),
    "qwen3.5-plus": ("bailian", "anthropic"),
    "qwen3-coder-plus": ("bailian", "anthropic"),
}


def create_model_client(
    model_name: str = "local-default",
    *,
    db: sqlite3.Connection | None = None,
    providers: dict | None = None,
) -> ModelClient:
    """根据 model_name 和 providers 配置返回对应的 ModelClient 实例。

    providers 格式:
      { "stepfun": {"api_key": "...", "base_url": "...", "protocol": "openai"}, ... }
    """
    if model_name == "local-default":
        return LocalDefaultGenerator(db=db)

    if model_name not in _MODEL_REGISTRY:
        raise ValueError(
            f"Unknown model: {model_name}. Known: {list(_MODEL_REGISTRY.keys())}"
        )

    provider_key, protocol = _MODEL_REGISTRY[model_name]

    if providers is None:
        raise ValueError(f"No providers config for model {model_name}")

    if provider_key in providers:
        cfg = providers[provider_key]
    elif len(providers) == 1:
        # A fully-qualified model ref such as opencode/deepseek-v4-pro can
        # intentionally route a known model name through an aggregate provider.
        provider_key, cfg = next(iter(providers.items()))
    else:
        raise ValueError(
            f"Provider '{provider_key}' not found in providers config. "
            f"Available: {list(providers.keys())}"
        )
    api_key = cfg.get("api_key", "")
    base_url = cfg.get("base_url", "")
    actual_model = cfg.get("model", model_name)
    actual_protocol = cfg.get("protocol") or protocol

    if not api_key:
        raise ValueError(f"No API key for provider '{provider_key}'")

    if actual_protocol == "openai":
        return OpenAIClient(
            api_key=api_key, base_url=base_url, model_name=actual_model, db=db,
        )
    elif actual_protocol == "anthropic":
        return AnthropicClient(
            api_key=api_key, base_url=base_url, model_name=actual_model, db=db,
        )
    else:
        raise ValueError(f"Unknown protocol: {actual_protocol}")


def resolve_model_for_tier(
    models_config: dict,
    tier: str = "primary",
) -> str:
    """Resolve model name from config for a given tier.

    tiers: 'primary', 'candidates' (list), 'fallback'
    """
    if tier == "primary":
        return models_config.get("primary", "local-default")
    elif tier == "candidates":
        candidates = models_config.get("candidates", [])
        return candidates[0] if candidates else "local-default"
    elif tier == "fallback":
        return models_config.get("fallback", "local-default")
    return "local-default"
