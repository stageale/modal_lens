from __future__ import annotations

from types import SimpleNamespace

import pytest

torch = pytest.importorskip("torch")
pytest.importorskip("transformers")

import verbalization.transformers as transformers_module
from verbalization.base import GenerationRequest
from verbalization.transformers import TransformersError, TransformersVerbalizer


MESSAGES = (
    {"role": "system", "content": "System"},
    {"role": "user", "content": "User"},
)


class FakeTokenizer:
    eos_token_id = 2

    def __init__(self):
        self.template_calls = []
        self.decoded_ids = None

    def apply_chat_template(self, messages, **kwargs):
        self.template_calls.append((messages, kwargs))
        return {
            "input_ids": torch.tensor([[10, 11, 12]]),
            "attention_mask": torch.tensor([[1, 1, 1]]),
        }

    def decode(self, token_ids, *, skip_special_tokens):
        self.decoded_ids = token_ids.tolist()
        assert skip_special_tokens is True
        return '  {"overview":"ok","cluster_summaries":[],"limitations":[]}  '


class FakeModel:
    def __init__(self):
        self.generation_config = SimpleNamespace(
            pad_token_id=None,
        )
        self.device = None
        self.evaluated = False
        self.generate_kwargs = None
        self._parameter = torch.nn.Parameter(
            torch.zeros(1, dtype=torch.float32)
        )

    def to(self, device):
        self.device = device
        return self

    def eval(self):
        self.evaluated = True
        return self

    def parameters(self):
        yield self._parameter

    def generate(self, **kwargs):
        self.generate_kwargs = kwargs
        return torch.tensor(
            [[10, 11, 12, 20, 21]]
        )


def _build_mocked_verbalizer(monkeypatch):
    tokenizer = FakeTokenizer()
    model = FakeModel()
    tokenizer_load = {}
    model_load = {}

    monkeypatch.setattr(
        TransformersVerbalizer,
        "_resolve_revision",
        staticmethod(
            lambda repository_id, revision: (
                f"sha:{repository_id}:{revision}"
            )
        ),
    )

    def fake_tokenizer_from_pretrained(
        repository_id,
        **kwargs,
    ):
        tokenizer_load.update(
            {
                "repository_id": repository_id,
                **kwargs,
            }
        )
        return tokenizer

    def fake_model_from_pretrained(
        repository_id,
        **kwargs,
    ):
        model_load.update(
            {
                "repository_id": repository_id,
                **kwargs,
            }
        )
        return model

    monkeypatch.setattr(
        transformers_module.AutoTokenizer,
        "from_pretrained",
        fake_tokenizer_from_pretrained,
    )
    monkeypatch.setattr(
        transformers_module.AutoModelForCausalLM,
        "from_pretrained",
        fake_model_from_pretrained,
    )

    verbalizer = TransformersVerbalizer(
        "HuggingFaceTB/SmolLM3-3B",
        revision="paper-revision",
        device="cpu",
        torch_dtype="auto",
        chat_template_kwargs={
            "enable_thinking": False,
        },
    )

    return (
        verbalizer,
        tokenizer,
        model,
        tokenizer_load,
        model_load,
    )


def test_transformers_verbalizer_loads_resolved_revisions(
    monkeypatch,
):
    (
        verbalizer,
        _,
        model,
        tokenizer_load,
        model_load,
    ) = _build_mocked_verbalizer(monkeypatch)

    assert verbalizer.backend == "transformers"
    assert verbalizer.model_id == "HuggingFaceTB/SmolLM3-3B"
    assert tokenizer_load == {
        "repository_id": "HuggingFaceTB/SmolLM3-3B",
        "revision": (
            "sha:HuggingFaceTB/SmolLM3-3B:paper-revision"
        ),
        "trust_remote_code": False,
    }
    assert model_load == {
        "repository_id": "HuggingFaceTB/SmolLM3-3B",
        "revision": (
            "sha:HuggingFaceTB/SmolLM3-3B:paper-revision"
        ),
        "torch_dtype": "auto",
        "trust_remote_code": False,
    }
    assert model.device == torch.device("cpu")
    assert model.evaluated is True


def test_prepare_inputs_uses_official_chat_template(
    monkeypatch,
):
    verbalizer, tokenizer, _, _, _ = (
        _build_mocked_verbalizer(monkeypatch)
    )
    request = GenerationRequest(messages=MESSAGES)

    inputs = verbalizer._prepare_inputs(request)

    assert inputs["input_ids"].device.type == "cpu"
    messages, kwargs = tokenizer.template_calls[0]
    assert messages == list(MESSAGES)
    assert kwargs["tokenize"] is True
    assert kwargs["add_generation_prompt"] is True
    assert kwargs["return_tensors"] == "pt"
    assert kwargs["return_dict"] is True
    assert kwargs["enable_thinking"] is False


def test_generate_uses_greedy_decoding_and_returns_metadata(
    monkeypatch,
):
    verbalizer, tokenizer, model, _, _ = (
        _build_mocked_verbalizer(monkeypatch)
    )
    seeded = []
    monkeypatch.setattr(
        transformers_module,
        "set_seed",
        seeded.append,
    )
    request = GenerationRequest(
        messages=MESSAGES,
        seed=17,
        max_new_tokens=256,
    )

    result = verbalizer.generate(request)

    assert seeded == [17]
    assert result.backend == "transformers"
    assert result.raw_text == (
        '{"overview":"ok","cluster_summaries":[],"limitations":[]}'
    )
    assert tokenizer.decoded_ids == [20, 21]
    assert model.generate_kwargs["do_sample"] is False
    assert model.generate_kwargs["num_beams"] == 1
    assert model.generate_kwargs["max_new_tokens"] == 256
    assert model.generate_kwargs["pad_token_id"] == 2
    assert result.metadata["prompt_token_count"] == 3
    assert result.metadata["generated_token_count"] == 2
    assert result.metadata["device"] == "cpu"
    assert result.metadata["dtype"] == "torch.float32"
    assert result.metadata["chat_template_kwargs"] == {
        "enable_thinking": False,
    }
    assert result.metadata["decoding"]["seed"] == 17


def test_select_device_accepts_cpu():
    assert TransformersVerbalizer._select_device(
        "cpu"
    ) == torch.device("cpu")


def test_select_device_rejects_unavailable_cuda(monkeypatch):
    monkeypatch.setattr(
        torch.cuda,
        "is_available",
        lambda: False,
    )

    with pytest.raises(
        TransformersError,
        match="CUDA was requested but is unavailable",
    ):
        TransformersVerbalizer._select_device("cuda")


def test_transformers_verbalizer_rejects_empty_model_id():
    with pytest.raises(ValueError, match="must not be empty"):
        TransformersVerbalizer(" ")


def test_generate_rejects_non_greedy_decoding(monkeypatch):
    verbalizer, _, _, _, _ = (
        _build_mocked_verbalizer(monkeypatch)
    )
    request = GenerationRequest(
        messages=MESSAGES,
        decoding="sampling",
    )

    with pytest.raises(ValueError, match="only greedy"):
        verbalizer.generate(request)
