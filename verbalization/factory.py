from __future__ import annotations

from typing import Any

from .base import Verbalizer

HF_MODEL_ALIASES = {
    "smollm3": "HuggingFaceTB/SmolLM3-3B",
    "qwen3": "Qwen/Qwen3-4B-Instruct-2507",
    "phi4-mini": "microsoft/Phi-4-mini-instruct"
}


def create_verbalizer(
        backend: str, 
        model_id: str, 
        *, 
        revision: str = "main", 
        device: str = "auto", 
        torch_dtype: Any = "auto",
        ollama_base_url: str = "http://localhost:11434",
        ollama_timeout: float = 300.0, 
        reasoning: bool = False
    ) -> Verbalizer:
    if not isinstance(reasoning, bool):
        raise ValueError("reasoning must be a boolean.")

    normalized_backend = backend.strip().lower()
    
    if normalized_backend == "ollama":
        from .ollama import OllamaVerbalizer
        
        return OllamaVerbalizer(model_id=model_id, base_url=ollama_base_url, timeout=ollama_timeout, reasoning=reasoning)
    
    if normalized_backend == "transformers":
        from .transformers import TransformersVerbalizer
        
        resolved_model_id = _resolve_hf_model_id(model_id)
        
        return TransformersVerbalizer(
            model_id=resolved_model_id,
            revision=revision,
            device=device,
            torch_dtype=torch_dtype,
            chat_template_kwargs=_hf_chat_template_kwargs(resolved_model_id, reasoning=reasoning)
        )
    
    raise ValueError(f"Unsupported verbalization backend: {backend!r}. Expected 'ollama' or 'transformers'.")


def _resolve_hf_model_id(model_id: str) -> str:
    normalized = model_id.strip()
    
    if not normalized:
        raise ValueError("Model id must not be empty.")
    
    return HF_MODEL_ALIASES.get(normalized.lower(), normalized)

def _hf_chat_template_kwargs(model_id: str, *, reasoning: bool) -> dict[str, Any]:
    if model_id == "HuggingFaceTB/SmolLM3-3B":
        return {"enable_thinking": reasoning}
    
    return {}