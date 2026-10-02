from __future__ import annotations
from typing import Any
from openai import APIConnectionError, APIError, APIStatusError, OpenAI

from .base import GenerationRequest, GenerationResult, Verbalizer


class OpenAIError(RuntimeError):
    """Raised when communication with OpenAI fails."""


class OpenAIVerbalizer(Verbalizer):
    def __init__(
        self,
        model_id: str,
        *,
        api_key: str | None = None,
        base_url: str | None = None,
        timeout: float = 300.0,
        reasoning: bool = False,
    ) -> None:
        if not model_id.strip():
            raise ValueError("OpenAI model_id must not be empty.")

        if timeout <= 0:
            raise ValueError("OpenAI timeout must be positive.")

        if not isinstance(reasoning, bool):
            raise ValueError("reasoning must be a boolean.")

        self._model_id = model_id.strip()
        self._timeout = timeout
        self._reasoning = reasoning

        client_kwargs: dict[str, Any] = {
            "timeout": timeout,
        }

        if api_key is not None:
            if not api_key.strip():
                raise ValueError("OpenAI api_key must not be empty when provided.")
            client_kwargs["api_key"] = api_key.strip()

        if base_url is not None:
            if not base_url.strip():
                raise ValueError("OpenAI base_url must not be empty when provided.")
            client_kwargs["base_url"] = base_url.rstrip("/")

        self._client = OpenAI(**client_kwargs)

    @property
    def backend(self) -> str:
        return "openai"

    @property
    def model_id(self) -> str:
        return self._model_id

    def _model_metadata(self) -> dict[str, Any]:
        try:
            model = self._client.models.retrieve(self._model_id)
        except (APIConnectionError, APIStatusError, APIError) as error:
            raise OpenAIError(
                f"Could not retrieve OpenAI model metadata for "
                f"{self._model_id!r}: {error}"
            ) from error

        return {
            "resolved_model_id": getattr(model, "id", self._model_id),
            "created_at": getattr(model, "created", None),
            "owned_by": getattr(model, "owned_by", None),
        }

    def _response_kwargs(self, request: GenerationRequest) -> dict[str, Any]:
        kwargs: dict[str, Any] = {
            "model": self._model_id,
            "input": [dict(message) for message in request.messages],
            "max_output_tokens": request.max_new_tokens,
            "text": {
                "format": {
                    "type": "json_object",
                }
            },
        }

        if self._reasoning:
            kwargs["reasoning"] = {
                "effort": "low",
            }

        return kwargs

    def generate(self, request: GenerationRequest) -> GenerationResult:
        if request.decoding != "greedy":
            raise ValueError(
                "OpenAIVerbalizer currently supports only greedy decoding."
            )

        model_metadata = self._model_metadata()

        try:
            response = self._client.responses.create(
                **self._response_kwargs(request)
            )
        except APIConnectionError as error:
            raise OpenAIError(
                "Could not connect to OpenAI."
            ) from error
        except APIStatusError as error:
            message = getattr(error, "message", str(error))
            raise OpenAIError(
                f"OpenAI returned HTTP {error.status_code}: {message}"
            ) from error
        except APIError as error:
            raise OpenAIError(
                f"OpenAI API request failed: {error}"
            ) from error

        raw_text = response.output_text

        if not isinstance(raw_text, str) or not raw_text.strip():
            raise OpenAIError(
                "OpenAI response contains no assistant text output."
            )

        usage = getattr(response, "usage", None)

        prompt_token_count = (
            getattr(usage, "input_tokens", None)
            if usage is not None
            else None
        )
        generated_token_count = (
            getattr(usage, "output_tokens", None)
            if usage is not None
            else None
        )
        reasoning_token_count = None

        if usage is not None:
            output_details = getattr(usage, "output_tokens_details", None)
            if output_details is not None:
                reasoning_token_count = getattr(
                    output_details,
                    "reasoning_tokens",
                    None,
                )

        metadata = {
            **model_metadata,
            "response_id": getattr(response, "id", None),
            "created_at": getattr(response, "created_at", None),
            "status": getattr(response, "status", None),
            "reasoning_enabled": self._reasoning,
            "prompt_token_count": prompt_token_count,
            "generated_token_count": generated_token_count,
            "reasoning_token_count": reasoning_token_count,
            "total_token_count": (
                getattr(usage, "total_tokens", None)
                if usage is not None
                else None
            ),
            "decoding": {
                "policy": "greedy",
                "seed": request.seed,
                "max_new_tokens": request.max_new_tokens,
            },
        }

        return GenerationResult(
            backend=self.backend,
            model_id=self.model_id,
            raw_text=raw_text,
            metadata=metadata,
        )
