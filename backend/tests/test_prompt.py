from datetime import date, datetime

import context
import resources
import server


def test_years_of_experience_is_computed_from_career_start():
    assert resources.profile["career_start"] == "2017-11"
    assert resources.years_of_experience(date(2026, 11, 5)) == 9
    assert resources.years_of_experience(date(2026, 10, 1)) == 8


def test_prompt_contains_grounding_rules_and_profile_facts():
    text = context.prompt(datetime(2026, 11, 5))
    assert "about 9 years of experience" in text
    assert "p.walukagga@gmail.com" in text
    assert "first person" in text
    assert "No markdown headings" in text
    assert "NOT KNOWN" in text  # recruiter fields still unfilled are listed for deferral
    assert "recruiter_facts" not in text.split("## Logistics for recruiters")[0]


def test_bedrock_calls_use_system_parameter(monkeypatch):
    captured = {}

    def fake_converse(**kwargs):
        captured.update(kwargs)
        return {"output": {"message": {"content": [{"text": "hello"}]}}}

    monkeypatch.setattr(server.bedrock_client, "converse", fake_converse)
    assert server.call_bedrock([{"role": "user", "content": "hi"}, {"role": "assistant", "content": "hey"}], "q") == "hello"

    assert captured["system"][0]["text"].startswith("# Who you are")
    roles = [m["role"] for m in captured["messages"]]
    assert roles == ["user", "assistant", "user"]
    assert not captured["messages"][0]["content"][0]["text"].startswith("System:")
