from __future__ import annotations

import pytest

from verbalization.base import (
    GenerationRequest,
    GenerationResult,
    Verbalizer,
)


MESSAGES = (
    {"role": "system", "content": "System"},
    {"role": "user", "content": "User"},
)


class ExampleVerbalizer(Verbalizer):
    @property
    def backend(self) -> str:
        return "example"

    @property
    def model_id(self) -> str:
        return "example/model"

    def generate(
        self,
        request: GenerationRequest,
    ) -> GenerationResult:
        return GenerationResult(
            backend=self.backend,
            model_id=self.model_id,
            raw_text="{}",
            metadata={"seed": request.seed},
        )


def test_generation_request_uses_reproducible_defaults():
    request = GenerationRequest(messages=MESSAGES)

    assert request.seed == 42
    assert request.max_new_tokens == 768
    assert request.decoding == "greedy"


@pytest.mark.parametrize(
    ("kwargs", "message"),
    [
        ({"messages": ()}, "requires messages"),
        ({"messages": MESSAGES, "seed": -1}, "non-negative"),
        ({"messages": MESSAGES, "max_new_tokens": 0}, "positive"),
    ],
)
def test_generation_request_rejects_invalid_values(
    kwargs,
    message,
):
    with pytest.raises(ValueError, match=message):
        GenerationRequest(**kwargs)


def test_generation_result_uses_independent_metadata_defaults():
    first = GenerationResult(
        backend="example",
        model_id="one",
        raw_text="{}",
    )
    second = GenerationResult(
        backend="example",
        model_id="two",
        raw_text="{}",
    )

    assert first.metadata == {}
    assert second.metadata == {}
    assert first.metadata is not second.metadata


def test_verbalizer_interface_can_be_implemented():
    verbalizer = ExampleVerbalizer()
    request = GenerationRequest(messages=MESSAGES, seed=7)

    result = verbalizer.generate(request)

    assert result.backend == "example"
    assert result.model_id == "example/model"
    assert result.metadata == {"seed": 7}


def test_abstract_verbalizer_cannot_be_instantiated():
    with pytest.raises(TypeError):
        Verbalizer()
