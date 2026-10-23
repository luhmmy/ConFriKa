"""Redis-backed fixed-window rate limiting for abuse-prone endpoints.

Keyed by client IP (honouring X-Forwarded-For behind the nginx proxy). Fails
OPEN if Redis is unavailable — availability is preferred over hard-blocking, and
the limiter is a defence-in-depth layer, not the only auth control.
"""
from __future__ import annotations

from typing import Callable

import redis.asyncio as aioredis
from fastapi import Depends, HTTPException, Request, status

from ..config.settings import settings

_redis: aioredis.Redis | None = None


def _client() -> aioredis.Redis:
    global _redis
    if _redis is None:
        _redis = aioredis.from_url(
            settings.REDIS_URL, encoding="utf-8", decode_responses=True
        )
    return _redis


def _client_ip(request: Request) -> str:
    # Behind nginx the real client is the first hop in X-Forwarded-For.
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


async def _allow(key: str, limit: int, window: int) -> bool:
    r = _client()
    try:
        n = await r.incr(key)
        if n == 1:
            await r.expire(key, window)
        return n <= limit
    except Exception:
        return True  # fail open


def rate_limit(bucket: str, limit: int, window_seconds: int) -> Callable:
    """Dependency: allow at most `limit` requests per IP per `window_seconds`."""

    async def _dep(request: Request) -> None:
        key = f"rl:{bucket}:{_client_ip(request)}"
        if not await _allow(key, limit, window_seconds):
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many attempts. Please wait a minute and try again.",
                headers={"Retry-After": str(window_seconds)},
            )

    return Depends(_dep)
