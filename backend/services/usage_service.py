"""Redis-backed daily usage counters for free-tier quotas.

Counts consumable actions (translations, translated call seconds) per user per
UTC day so the free tier can be capped while Pro is unlimited. Fails OPEN if
Redis is unavailable: availability is preferred over hard-blocking a paying or
free user because of an infra blip.
"""
from __future__ import annotations

from datetime import datetime, timezone

import redis.asyncio as aioredis

from ..config.settings import settings

_redis: aioredis.Redis | None = None
_TTL_SECONDS = 2 * 24 * 3600  # keep a day's counter around ~2 days then auto-expire


def _client() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(
            settings.REDIS_URL, encoding="utf-8", decode_responses=True
        )
    return _redis


def _today() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d")


def _key(user_id: str, resource: str) -> str:
    return f"usage:{resource}:{user_id}:{_today()}"


async def peek(user_id: str, resource: str) -> int:
    """Current usage of ``resource`` for the user today (0 on any error)."""
    try:
        val = await _client().get(_key(user_id, resource))
        return int(val) if val else 0
    except Exception:
        return 0


async def consume(user_id: str, resource: str, amount: int, limit: int) -> tuple[bool, int]:
    """Try to consume ``amount`` of ``resource``.

    Returns ``(allowed, remaining)``. A ``limit`` <= 0 means unlimited. On a
    Redis error we fail open (allowed, limit). When the amount would exceed the
    limit the counter is NOT incremented and ``allowed`` is False.
    """
    if limit <= 0:
        return True, -1  # unlimited
    try:
        r = _client()
        key = _key(user_id, resource)
        current = await r.get(key)
        current = int(current) if current else 0
        if current + amount > limit:
            return False, max(0, limit - current)
        new_val = await r.incrby(key, amount)
        if new_val == amount:  # first write today -> set expiry
            await r.expire(key, _TTL_SECONDS)
        return True, max(0, limit - new_val)
    except Exception:
        return True, limit  # fail open
