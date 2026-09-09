from __future__ import annotations

import platform
from collections.abc import Mapping
from typing import Any

import torch
import transformers
from huggingface_hub import HfApi
from huggingface_hub.utils import HfHubHTTPError
from transformers import AutoModelForCausalLM, AutoTokenizer, set_seed

from .base import GenerationRequest, GenerationResult, Verbalizer


class TransformersError(RuntimeError):
    """Raised when Transformers inference fails."""
    
    
class TransformersVerbalizer(Verbalizer):
    def __init__(
        self, 
        model_id: str, 
        *, 
        tokenizer_id: str | None = None, 
        revision: str = "main", 
        tokenizer_revision: str | None = None,
        device: str = "auto",
        torch_dtype: str | torch.dtype = "auto",
        chat_template_kwargs: Mapping[str, Any] | None = None
    ) -> None:
        if not model_id.strip():
            raise ValueError("Transformers model_id must not be empty.")
        
        self._model_id = model_id.strip()
        self._tokenizer_id = tokenizer_id or self._model_id
        
        self._requested_revision = revision
        self._requested_tokenizer_revision = tokenizer_revision or revision
        
        self._chat_template_kwargs = dict(chat_template_kwargs or {})
        self._device = self._select_device(device)
        
        self._resolved_model_revision = self._resolve_revision(self._model_id, revision)
        self._resolved_tokenizer_revision = self._resolve_revision(self._tokenizer_id, self._requested_tokenizer_revision)
        
        self._tokenizer = AutoTokenizer.from_pretrained(self._tokenizer_id, revision=self._resolved_tokenizer_revision, trust_remote_code=False)
        self._model = AutoModelForCausalLM.from_pretrained(self._model_id, revision=self._resolved_model_revision, torch_dtype=torch_dtype, trust_remote_code=False)
        
        self._model.to(self._device)
        self._model.eval()
        
    @property
    def backend(self) -> str:
        return "transformers"
    
    @property
    def model_id(self) -> str:
        return self._model_id
    
    @staticmethod
    def _resolve_revision(repository_id: str, revision: str) -> str:
        try:
            model_info = HfApi().model_info(repo_id=repository_id, revision=revision)
        except HfHubHTTPError as error:
            raise TransformersError(f"Could not resolve Hugging Face revision {revision!r} for {repository_id!r}.") from error
        if not model_info.sha:
            raise TransformersError(f"Hugging Face returned no commit SHA for {repository_id!r}.")
        
        return model_info.sha
    
    @staticmethod
    def _select_device(requested_device: str) -> torch.device:
        if requested_device == "auto":
            if torch.cuda.is_available():
                return torch.device("cuda")
            
            if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
                return torch.device("mps")
            
            return torch.device("cpu")
        
        device = torch.device(requested_device)
        
        if device.type == "cuda" and not torch.cuda.is_available():
            raise TransformersError("CUDA was requested but is unavailable.")
        
        if device.type == "mps" and not hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            raise TransformersError("MPS was requested but is unavailable.")
        
        return device
    
    def _prepare_inputs(self, request: GenerationRequest) -> dict[str, torch.Tensor]:
        messages = [dict(message) for message in request.messages]
        
        try:
            encoded = self._tokenizer.apply_chat_template(
                messages,
                tokenize=True,
                add_generation_prompt=True,
                return_tensors="pt",
                return_dict=True,
                **self._chat_template_kwargs
            )
        except Exception as error:
            raise TransformersError("Could not apply the model's official chat template.") from error
        
        return {
            name: tensor.to(self._device) for name, tensor in encoded.items()
        }
        
    @staticmethod
    def _final_response(decoded_text: str) -> str:
        stripped = decoded_text.strip()

        if "<think>" in stripped and "</think>" not in stripped:
            raise TransformersError("Transformers reasoning was truncated before the final response.")

        if "</think>" in stripped:
            stripped = stripped.rsplit("</think>", 1)[1].strip()

        if not stripped:
            raise TransformersError("Transformers returned no final response after reasoning.")

        return stripped

    def _runtime_metadata(self, request: GenerationRequest, *, prompt_token_count: int, generated_token_count: int) -> dict[str, Any]:
        parameter = next(self._model.parameters())
        
        device_name = None
        
        if self._device.type == "cuda":
            device_name = torch.cuda.get_device_name(self._device)
            
        return {
            "model_revision": (
                self._resolved_model_revision
            ),
            "tokenizer_id": self._tokenizer_id,
            "tokenizer_revision": (
                self._resolved_tokenizer_revision
            ),
            "python_version": (
                platform.python_version()
            ),
            "transformers_version": (
                transformers.__version__
            ),
            "pytorch_version": torch.__version__,
            "cuda_version": torch.version.cuda,
            "device": str(self._device),
            "device_name": device_name,
            "dtype": str(parameter.dtype),
            "prompt_token_count": (prompt_token_count),
            "generated_token_count": (generated_token_count),
            "chat_template_kwargs": dict(self._chat_template_kwargs),
            "reasoning_enabled": bool(self._chat_template_kwargs.get("enable_thinking", False)),
            "decoding": {
                "policy": "greedy",
                "do_sample": False,
                "num_beams": 1,
                "seed": request.seed,
                "max_new_tokens": (request.max_new_tokens),
            },
        }
        
    def generate(self, request: GenerationRequest) -> GenerationResult:
        if request.decoding != "greedy":
            raise ValueError("TransformersVerbalizer currently supports only greedy decoding.")

        set_seed(request.seed)

        inputs = self._prepare_inputs(request)

        prompt_token_count = int(inputs["input_ids"].shape[-1])

        generation_options: dict[str, Any] = {
            "do_sample": False,
            "num_beams": 1,
            "max_new_tokens": request.max_new_tokens
        }

        if self._model.generation_config.pad_token_id is None and self._tokenizer.eos_token_id is not None:
            generation_options["pad_token_id"] = self._tokenizer.eos_token_id

        try:
            with torch.inference_mode():
                output_ids = self._model.generate(**inputs,**generation_options)
        except Exception as error:
            raise TransformersError("Transformers generation failed.") from error

        generated_ids = output_ids[0,prompt_token_count:]

        decoded_text = self._tokenizer.decode(generated_ids, skip_special_tokens=True)

        raw_text = self._final_response(decoded_text)

        generated_token_count = int(generated_ids.shape[-1])

        return GenerationResult(
            backend=self.backend,
            model_id=self.model_id,
            raw_text=raw_text,
            metadata=self._runtime_metadata(
                request,
                prompt_token_count=prompt_token_count,
                generated_token_count=generated_token_count,
            ),
        )
        