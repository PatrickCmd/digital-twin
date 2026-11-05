"""Per-client rate limiting with pluggable stores.

Fixed-window counter keyed by a hashed client IP. Two stores:

- MemoryStore: per-process, good for local dev and tests. On Lambda it only
  limits within one warm container, so it is a fallback, not protection.
- DynamoDBStore: shared across Lambda instances. Enabled when RATE_LIMIT_TABLE
  is set (see terraform `enable_rate_limit_table`). Item shape:
  pk = "<client>#<window_start>", count (N), expires_at (N, TTL attribute).

The limiter fails open: if the store errors, the request is allowed and the
error is logged, so an outage never blocks the chat.
"""

from __future__ import annotations

import hashlib
import json
import os
import time
from dataclasses import dataclass
from typing import Protocol


class RateLimitStore(Protocol):
    def hit(self, key: str, window_start: int, expires_at: int) -> int:
        """Increment the counter for (key, window_start) and return the new count."""


class MemoryStore:
    def __init__(self) -> None:
        self._counts: dict[tuple[str, int], int] = {}
        self._expiry: dict[tuple[str, int], int] = {}

    def hit(self, key: str, window_start: int, expires_at: int) -> int:
        now = int(time.time())
        for k, exp in list(self._expiry.items()):
            if exp <= now:
                self._expiry.pop(k, None)
                self._counts.pop(k, None)
        k = (key, window_start)
        self._counts[k] = self._counts.get(k, 0) + 1
        self._expiry[k] = expires_at
        return self._counts[k]


class DynamoDBStore:
    def __init__(self, table_name: str, client=None) -> None:
        if client is None:
            import boto3

            client = boto3.client("dynamodb")
        self.table_name = table_name
        self.client = client

    def hit(self, key: str, window_start: int, expires_at: int) -> int:
        response = self.client.update_item(
            TableName=self.table_name,
            Key={"pk": {"S": f"{key}#{window_start}"}},
            UpdateExpression="ADD #c :one SET #exp = :exp",
            ExpressionAttributeNames={"#c": "count", "#exp": "expires_at"},
            ExpressionAttributeValues={":one": {"N": "1"}, ":exp": {"N": str(expires_at)}},
            ReturnValues="UPDATED_NEW",
        )
        return int(response["Attributes"]["count"]["N"])


@dataclass
class Decision:
    allowed: bool
    retry_after: int = 0
    remaining: int = 0


class RateLimiter:
    def __init__(self, store: RateLimitStore, limit: int, window_seconds: int) -> None:
        self.store = store
        self.limit = limit
        self.window = window_seconds

    def check(self, key: str) -> Decision:
        now = int(time.time())
        window_start = now - (now % self.window)
        try:
            count = self.store.hit(key, window_start, window_start + 2 * self.window)
        except Exception as exc:  # fail open
            print(json.dumps({"event": "rate_limit_store_error", "error": str(exc)}))
            return Decision(allowed=True, remaining=self.limit)
        if count > self.limit:
            return Decision(allowed=False, retry_after=window_start + self.window - now)
        return Decision(allowed=True, remaining=self.limit - count)


def limiter_from_env() -> RateLimiter:
    limit = int(os.getenv("RATE_LIMIT_REQUESTS", "20"))
    window = int(os.getenv("RATE_LIMIT_WINDOW_SECONDS", "600"))
    table = os.getenv("RATE_LIMIT_TABLE", "").strip()
    store: RateLimitStore = DynamoDBStore(table) if table else MemoryStore()
    return RateLimiter(store, limit, window)


def client_ip(scope: dict) -> str:
    """Best-effort client IP: API Gateway source IP when behind Mangum, else the socket peer."""
    event = scope.get("aws.event") or {}
    ip = (((event.get("requestContext") or {}).get("http") or {}).get("sourceIp")) or ""
    if not ip:
        client = scope.get("client")
        ip = client[0] if client else "unknown"
    return ip


def hash_ip(ip: str) -> str:
    return hashlib.sha256(ip.encode()).hexdigest()[:16]
