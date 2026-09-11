from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .base import GenerationRequest, GenerationResult, Verbalizer


class OllamaError(RuntimeError):
    """Raised when communication with Ollama fails"""


class OllamaVerbalizer(Verbalizer):
    def __init__(self, model_id: str, *, base_url: str = "http://localhost:11434", timeout: float = 300.0, reasoning: bool = False) -> None:
        if not model_id.strip():
            raise ValueError("Ollama model_id must not be empty.")
        
        if timeout <= 0:
            raise ValueError("Ollama timeout must be positive.")

        if not isinstance(reasoning, bool):
            raise ValueError("reasoning must be a boolean.")
        
        self._model_id = model_id.strip()
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout
        self._reasoning = reasoning
        
    @property
    def backend(self) -> str:
        return "ollama"
    
    @property
    def model_id(self) -> str:
        return self._model_id
    
    def _request_json(self, path: str, *, method: str = "GET", payload: Mapping[str, Any] | None = None) -> dict[str, Any]:
        data = None
        
        headers = {
            "Accept": "application/json"
        }
        
        if payload is not None:
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            
            headers["Content-Type"] = "application/json"
            
        request = Request(url=f"{self._base_url}{path}", data=data, headers=headers, method=method)
        
        try:
            with urlopen(request, timeout=self._timeout) as response:
                response_text = response.read().decode("utf-8")
        except HTTPError as error:
            error_text = error.read().decode("utf-8", errors="replace")
            try:
                error_data = json.loads(error_text)
                message = error_data.get(
                    "error",
                    error_text,
                )
            except json.JSONDecodeError:
                message = error_text

            raise OllamaError(
                f"Ollama returned HTTP "
                f"{error.code}: {message}"
            ) from error
        except URLError as error:
            raise OllamaError(
                "Could not connect to Ollama at "
                f"{self._base_url}: {error.reason}"
            ) from error

        try:
            result = json.loads(response_text)
        except json.JSONDecodeError as error:
            raise OllamaError(
                "Ollama returned invalid JSON."
            ) from error

        if not isinstance(result, dict):
            raise OllamaError(
                "Ollama response must be a JSON object."
            )

        return result
    
    def _ollama_version(self) -> str | None:
        response = self._request_json("/api/version")
        
        version = response.get("version")
        
        return version if isinstance(version, str) else None
    
    def _installed_model_metadata(self) -> dict[str, Any]:
        response = self._request_json("/api/tags")
        models = response.get("models")
        
        if not isinstance(models, list):
            raise OllamaError("Ollama did not return a model list.")
        
        accepted_names = {
            self._model_id,
        }
        
        if ":" not in self._model_id:
            accepted_names.add(f"{self._model_id}:latest")
            
        for model in models:
            if not isinstance(model, dict):
                continue
            
            model_names = {
                model.get("name"),
                model.get("model")
            }
            
            if accepted_names.isdisjoint(model_names):
                continue
            
            return {
                "resolved_model_id": model.get("model") or model.get("name"),
                "model_digest": model.get("digest"),
                "modified_at": model.get("modified_at"),
                "size_bytes": model.get("size"),
                "details": model.get("details", {})
            }
        raise OllamaError(f"Ollama model is not installed: {self._model_id}")
    
    def _chat_payload(self, request: GenerationRequest) -> dict[str, Any]:
        return {
            "model": self._model_id,
            "messages": [dict(message) for message in request.messages],
            "stream": False,
            "format": "json",
            "think": self._reasoning,
            "options": {
                "temperature": 0,
                "top_k": 1,
                "seed": request.seed,
                "num_predict": request.max_new_tokens
            }
        }
        
    def generate(self, request: GenerationRequest) -> GenerationResult:
        if request.decoding != "greedy":
            raise ValueError("OllamaVerbalizer currently supports only greedy decoding.")

        ollama_version = (self._ollama_version())

        model_metadata = (self._installed_model_metadata())

        response = self._request_json("/api/chat", method="POST", payload=self._chat_payload(request))

        message = response.get("message")

        if not isinstance(message, Mapping):
            raise OllamaError("Ollama response contains no assistant message.")

        raw_text = message.get("content")

        if not isinstance(raw_text, str):
            raise OllamaError("Ollama assistant content must be a string.")

        metadata = {
            "ollama_version": ollama_version,
            **model_metadata,
            "reasoning_enabled": self._reasoning,
            "created_at": response.get("created_at"),
            "done": response.get("done"),
            "done_reason": response.get("done_reason"),
            "prompt_token_count": response.get("prompt_eval_count"),
            "generated_token_count": response.get("eval_count"),
            "total_duration_ns": response.get("total_duration"),
            "load_duration_ns": response.get("load_duration"),
            "prompt_eval_duration_ns": response.get("prompt_eval_duration"),
            "generation_duration_ns": response.get("eval_duration"),
            "decoding": {
                "policy": "greedy",
                "temperature": 0,
                "top_k": 1,
                "seed": request.seed,
                "max_new_tokens": request.max_new_tokens
            }
        }

        return GenerationResult(
            backend=self.backend,
            model_id=self.model_id,
            raw_text=raw_text,
            metadata=metadata
        )