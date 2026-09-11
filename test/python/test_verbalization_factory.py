from __future__ import annotations

from typing import Any

import pytest

import verbalization.ollama as ollama_module
import verbalization.transformers as transformers_module
from verbalization.factory import create_verbalizer


class FakeVerbalizer:
    def __init__(self, **options: Any):
        self.options = options


def test_factory_forwards_reasoning_to_ollama(monkeypatch):
    monkeypatch.setattr(
        ollama_module,
        "OllamaVerbalizer",
        FakeVerbalizer,
    )

    verbalizer = create_verbalizer(
        "ollama",
        "qwen3.5:9b",
        reasoning=True,
    )

    assert verbalizer.options["reasoning"] is True


def test_factory_configures_smollm_thinking(monkeypatch):
    monkeypatch.setattr(
        transformers_module,
        "TransformersVerbalizer",
        FakeVerbalizer,
    )

    verbalizer = create_verbalizer(
        "transformers",
        "smollm3",
        reasoning=True,
    )

    assert verbalizer.options["model_id"] == "HuggingFaceTB/SmolLM3-3B"
    assert verbalizer.options["chat_template_kwargs"] == {
        "enable_thinking": True,
    }


def test_factory_keeps_unrelated_transformers_templates_unchanged(monkeypatch):
    monkeypatch.setattr(
        transformers_module,
        "TransformersVerbalizer",
        FakeVerbalizer,
    )

    verbalizer = create_verbalizer(
        "transformers",
        "phi4-mini",
        reasoning=True,
    )

    assert verbalizer.options["chat_template_kwargs"] == {}


def test_factory_rejects_non_boolean_reasoning():
    with pytest.raises(ValueError, match="reasoning must be a boolean"):
        create_verbalizer(
            "ollama",
            "qwen3.5:9b",
            reasoning="on",  # type: ignore[arg-type]
        )
