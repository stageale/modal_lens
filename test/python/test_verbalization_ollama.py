from __future__ import annotations

import json
from urllib.error import URLError

import pytest

import verbalization.ollama as ollama_module
from verbalization.base import GenerationRequest
from verbalization.ollama import OllamaError, OllamaVerbalizer


MESSAGES = ({"role": "system", "content": "System"}, {"role": "user", "content": "User"})


class FakeResponse:
    def __init__(self, payload):
        self._payload = payload

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False

    def read(self):
        return json.dumps(self._payload).encode("utf-8")


def test_ollama_verbalizer_normalizes_configuration():
    verbalizer = OllamaVerbalizer(
        "  qwen2.5:3b  ",
        base_url="http://localhost:11434/",
        timeout=10,
    )

    assert verbalizer.backend == "ollama"
    assert verbalizer.model_id == "qwen2.5:3b"
    assert verbalizer._base_url == "http://localhost:11434"


@pytest.mark.parametrize(
    ("kwargs", "message"),
    [
        ({"model_id": " "}, "must not be empty"),
        ({"model_id": "qwen2.5", "timeout": 0}, "must be positive"),
        ({"model_id": "qwen2.5", "reasoning": "on"}, "must be a boolean"),
    ],
)
def test_ollama_verbalizer_rejects_invalid_configuration(
    kwargs,
    message,
):
    with pytest.raises(ValueError, match=message):
        OllamaVerbalizer(**kwargs)


def test_request_json_decodes_local_api_response(monkeypatch):
    def fake_urlopen(request, timeout):
        assert request.full_url == "http://localhost:11434/api/version"
        assert timeout == 5
        return FakeResponse({"version": "0.9.0"})

    monkeypatch.setattr(
        ollama_module,
        "urlopen",
        fake_urlopen,
    )

    verbalizer = OllamaVerbalizer(
        "qwen2.5:3b",
        timeout=5,
    )

    assert verbalizer._request_json("/api/version") == {
        "version": "0.9.0",
    }


def test_request_json_wraps_connection_errors(monkeypatch):
    def failing_urlopen(request, timeout):
        raise URLError("connection refused")

    monkeypatch.setattr(
        ollama_module,
        "urlopen",
        failing_urlopen,
    )

    verbalizer = OllamaVerbalizer("qwen2.5:3b")

    with pytest.raises(
        OllamaError,
        match="Could not connect to Ollama",
    ):
        verbalizer._request_json("/api/version")


def test_installed_model_metadata_resolves_latest_tag(monkeypatch):
    verbalizer = OllamaVerbalizer("qwen2.5")

    monkeypatch.setattr(
        verbalizer,
        "_request_json",
        lambda path: {
            "models": [
                {
                    "name": "qwen2.5:latest",
                    "model": "qwen2.5:latest",
                    "digest": "sha256:abc",
                    "modified_at": "2026-01-01T00:00:00Z",
                    "size": 1234,
                    "details": {
                        "quantization_level": "Q4_K_M",
                    },
                }
            ]
        },
    )

    metadata = verbalizer._installed_model_metadata()

    assert metadata["resolved_model_id"] == "qwen2.5:latest"
    assert metadata["model_digest"] == "sha256:abc"
    assert metadata["details"] == {
        "quantization_level": "Q4_K_M",
    }


def test_chat_payload_uses_json_and_greedy_options():
    verbalizer = OllamaVerbalizer("qwen2.5:3b")
    request = GenerationRequest(
        messages=MESSAGES,
        seed=17,
        max_new_tokens=256,
    )

    payload = verbalizer._chat_payload(request)

    assert payload["model"] == "qwen2.5:3b"
    assert payload["messages"] == list(MESSAGES)
    assert payload["stream"] is False
    assert payload["format"] == "json"
    assert payload["think"] is False
    assert payload["options"] == {
        "temperature": 0,
        "top_k": 1,
        "seed": 17,
        "num_predict": 256,
    }


def test_chat_payload_enables_reasoning_without_exposing_thinking():
    verbalizer = OllamaVerbalizer("qwen3.5:9b", reasoning=True)
    request = GenerationRequest(messages=MESSAGES)

    payload = verbalizer._chat_payload(request)

    assert payload["think"] is True


def test_generate_returns_raw_text_and_provenance(monkeypatch):
    verbalizer = OllamaVerbalizer("qwen2.5:3b")
    request = GenerationRequest(
        messages=MESSAGES,
        seed=17,
        max_new_tokens=256,
    )

    monkeypatch.setattr(
        verbalizer,
        "_ollama_version",
        lambda: "0.9.0",
    )
    monkeypatch.setattr(
        verbalizer,
        "_installed_model_metadata",
        lambda: {
            "resolved_model_id": "qwen2.5:3b",
            "model_digest": "sha256:abc",
        },
    )

    def fake_request(path, *, method="GET", payload=None):
        assert path == "/api/chat"
        assert method == "POST"
        assert payload["options"]["seed"] == 17
        return {
            "message": {
                "role": "assistant",
                "content": '{"overview":"ok","cluster_summaries":[],"limitations":[]}',
            },
            "done": True,
            "done_reason": "stop",
            "prompt_eval_count": 100,
            "eval_count": 20,
        }

    monkeypatch.setattr(
        verbalizer,
        "_request_json",
        fake_request,
    )

    result = verbalizer.generate(request)

    assert result.backend == "ollama"
    assert result.model_id == "qwen2.5:3b"
    assert result.raw_text.startswith("{")
    assert result.metadata["ollama_version"] == "0.9.0"
    assert result.metadata["model_digest"] == "sha256:abc"
    assert result.metadata["prompt_token_count"] == 100
    assert result.metadata["generated_token_count"] == 20
    assert result.metadata["reasoning_enabled"] is False
    assert result.metadata["decoding"]["seed"] == 17


def test_generate_rejects_non_greedy_decoding():
    verbalizer = OllamaVerbalizer("qwen2.5:3b")
    request = GenerationRequest(
        messages=MESSAGES,
        decoding="sampling",
    )

    with pytest.raises(ValueError, match="only greedy"):
        verbalizer.generate(request)
