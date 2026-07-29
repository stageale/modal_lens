from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any

SYSTEM_MESSAGE = """
You verbalize previously computed computed analysis results.

Use only the supplied facts.
Do not infer new norms, legal conclusions, recommendations, or facts.
Do not reinterpret the underlying theory.
Every cluster statement must cite supplied evidence identifiers.
Return only valid JSON.
""".strip()

def render_user_message(verbalization_facts: Mapping[str, Any]) -> str:
    facts_json = json.dumps(verbalization_facts, ensure_ascii=False, sort_keys=True, indent=2)
    
    return f"""
    Create a concise English summary of the supplied analysis facts.
    
    Return exactly this JSON structure:
    
    {{
        "overview": "string",
        "cluster_summaries":[
            {{
                "cluster_id": 0,
                "summary": "string",
                "evidence": ["fact.identifier"]
            }}
        ],
        "limitations": ["string"]
    }}
    
    Requirements:
    - Include one cluster summary for every supplied cluster.
    - Use only existing cluster identifiers.
    - Evidence entries must exactly match supplied fact identifiers.
    - Do not include Markdown or explanatory text outside the JSON.
    - State uncertainty or missing information under "limitations".
    
    VERBALIZATION FACTS:
    
    {facts_json}
    """.strip()

def build_verbalization_messages(verbalization_facts: Mapping[str, Any]) -> tuple[dict[str, str], ...]:
    return (
        {
            "role": "system",
            "content": SYSTEM_MESSAGE,
        }, 
        {
            "role": "user",
            "content": render_user_message(verbalization_facts)
        }
    )