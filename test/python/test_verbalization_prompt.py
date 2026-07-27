from __future__ import annotations

from verbalization.facts import build_verbalization_facts
from verbalization.prompt import SYSTEM_MESSAGE, build_verbalization_messages, render_user_message


def test_render_user_message_contains_output_contract_and_facts(
    sample_report,
):
    facts = build_verbalization_facts(sample_report)

    message = render_user_message(facts)

    assert '"overview": "string"' in message
    assert '"cluster_summaries"' in message
    assert '"limitations"' in message
    assert "analysis.model_count" in message
    assert "theory.content" not in message
    assert "Do not include Markdown" in message


def test_build_verbalization_messages_uses_common_roles(
    sample_report,
):
    facts = build_verbalization_facts(sample_report)

    messages = build_verbalization_messages(facts)

    assert messages[0] == {
        "role": "system",
        "content": SYSTEM_MESSAGE,
    }
    assert messages[1]["role"] == "user"
    assert messages[1]["content"] == render_user_message(facts)


def test_system_message_forbids_new_normative_claims():
    assert "Do not infer new norms" in SYSTEM_MESSAGE
    assert "Use only the supplied facts" in SYSTEM_MESSAGE
    assert "Return only valid JSON" in SYSTEM_MESSAGE
