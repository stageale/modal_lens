from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any, Literal

@dataclass(frozen=True)
class GenerationRequest:
    messages: tuple[Mapping[str, str], ...]
    seed: int = 42
    max_new_tokens: int = 768
    decoding: Literal["greedy"] = "greedy"
    
    def __post_init__(self) -> None:
        if not self.messages:
            raise ValueError("Generation request requires messages.")
        
        if self.seed < 0:
            raise ValueError("Seed must be non-negative.")
        
        if self.max_new_tokens <= 0:
            raise ValueError("max_new_tokens must be positive.")
        
@dataclass(frozen=True)
class GenerationResult:
    backend: str
    model_id: str
    raw_text: str
    metadata: Mapping[str, Any] = field(
        default_factory=dict
    )
    
class Verbalizer(ABC):
    @property
    @abstractmethod
    def backend(self) -> str:
        raise NotImplementedError
    
    @property
    @abstractmethod
    def model_id(self) -> str:
        raise NotImplementedError
    
    @abstractmethod
    def generate(self, request: GenerationRequest) -> GenerationResult:
        raise NotImplementedError