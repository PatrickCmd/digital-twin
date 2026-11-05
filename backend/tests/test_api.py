import json
import uuid

import pytest
from fastapi.testclient import TestClient

import server
from rate_limit import MemoryStore, RateLimiter


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(server, "MEMORY_DIR", str(tmp_path))
    monkeypatch.setattr(server, "rate_limiter", RateLimiter(MemoryStore(), limit=10, window_seconds=600))

    def fake_stream(conversation, user_message, stats=None):
        if stats is not None:
            stats["usage"] = {"inputTokens": 10, "outputTokens": 5}
        yield "Hello "
        yield "there"

    monkeypatch.setattr(server, "stream_bedrock", fake_stream)
    monkeypatch.setattr(server, "call_bedrock", lambda conversation, msg, stats=None: "Hello there")
    return TestClient(server.app)


def parse_sse(text: str):
    return [json.loads(line[5:]) for line in text.splitlines() if line.startswith("data:")]


def test_stream_returns_session_chunks_and_done(client):
    r = client.post("/chat/stream", json={"message": "hi"})
    assert r.status_code == 200
    events = parse_sse(r.text)
    assert events[0]["type"] == "session"
    assert uuid.UUID(events[0]["session_id"])
    assert "".join(e["content"] for e in events if e["type"] == "chunk") == "Hello there"
    assert events[-1]["type"] == "done"


def test_message_too_long_is_rejected_with_code(client):
    r = client.post("/chat/stream", json={"message": "a" * (server.MAX_MESSAGE_CHARS + 1)})
    assert r.status_code == 422
    assert r.json()["error"] == "message_too_long"


def test_blank_message_and_bad_session_id_are_rejected(client):
    assert client.post("/chat", json={"message": "   "}).status_code == 422
    r = client.post("/chat", json={"message": "hi", "session_id": "not-a-uuid"})
    assert r.status_code == 422
    assert r.json()["error"] == "invalid_session"


def test_rate_limit_returns_429_with_retry_after(client, monkeypatch):
    monkeypatch.setattr(server, "rate_limiter", RateLimiter(MemoryStore(), limit=3, window_seconds=600))
    for _ in range(3):
        assert client.post("/chat", json={"message": "hi"}).status_code == 200
    r = client.post("/chat", json={"message": "hi"})
    assert r.status_code == 429
    assert r.json()["error"] == "rate_limited"
    assert int(r.headers["Retry-After"]) >= 1


def test_full_session_is_refused(client, monkeypatch):
    monkeypatch.setattr(server, "MAX_SESSION_MESSAGES", 2)
    first = client.post("/chat", json={"message": "hi"}).json()
    r = client.post("/chat", json={"message": "again", "session_id": first["session_id"]})
    assert r.status_code == 409
    assert r.json()["error"] == "session_full"


def test_history_is_persisted_per_session(client):
    first = client.post("/chat", json={"message": "one"}).json()
    client.post("/chat", json={"message": "two", "session_id": first["session_id"]})
    history = server.load_conversation(first["session_id"])
    assert [m["role"] for m in history] == ["user", "assistant", "user", "assistant"]


def test_feedback_is_stored(client, tmp_path):
    first = client.post("/chat", json={"message": "hi"}).json()
    r = client.post(
        "/feedback",
        json={"session_id": first["session_id"], "message_index": 1, "rating": "up", "assistant_preview": "Hello"},
    )
    assert r.status_code == 201
    stored = list((tmp_path / "feedback").rglob("*.json"))
    assert len(stored) == 1
    assert json.loads(stored[0].read_text())["rating"] == "up"
    assert client.post("/feedback", json={"session_id": "nope", "message_index": 0, "rating": "up"}).status_code == 422
    assert client.post("/feedback", json={"session_id": first["session_id"], "message_index": 0, "rating": "meh"}).status_code == 422


def test_contact_is_stored_and_validated(client, tmp_path):
    payload = {"name": "Ada", "email": "ada@example.com", "message": "Hello Patrick"}
    r = client.post("/contact", json=payload)
    assert r.status_code == 201
    assert r.json() == {"status": "ok", "emailed": False}
    stored = list((tmp_path / "contact").rglob("*.json"))
    assert len(stored) == 1 and json.loads(stored[0].read_text())["email"] == "ada@example.com"

    assert client.post("/contact", json={**payload, "email": "not-an-email"}).status_code == 422
    assert client.post("/contact", json={**payload, "message": "   "}).status_code == 422
    # Honeypot: looks successful, stores nothing new.
    assert client.post("/contact", json={**payload, "website": "http://spam"}).status_code == 201
    assert len(list((tmp_path / "contact").rglob("*.json"))) == 1


def test_contact_emails_via_ses_when_configured(client, monkeypatch):
    sent = {}

    class FakeSes:
        def send_email(self, **kwargs):
            sent.update(kwargs)
            return {"MessageId": "1"}

    monkeypatch.setattr(server, "ses_client", FakeSes())
    monkeypatch.setattr(server, "SES_FROM_EMAIL", "twin@example.com")
    monkeypatch.setattr(server, "SES_TO_EMAIL", "me@example.com")
    r = client.post("/contact", json={"name": "Ada", "email": "ada@example.com", "message": "Hi"})
    assert r.json()["emailed"] is True
    assert sent["Destination"] == {"ToAddresses": ["me@example.com"]}
    assert sent["ReplyToAddresses"] == ["ada@example.com"]
