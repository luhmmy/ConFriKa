"""In-process presence registry.

Tracks which users currently have an active WebSocket connection. All access
happens from the single asyncio event-loop thread, so a plain dict is safe.

For a multi-worker / multi-node deployment this is the seam where a Redis-backed
presence set would be plugged in (see REDIS_URL in settings).
"""
from typing import Dict, Set

_connection_counts: Dict[str, int] = {}


def mark_online(username: str) -> None:
    _connection_counts[username] = _connection_counts.get(username, 0) + 1


def mark_offline(username: str) -> None:
    count = _connection_counts.get(username, 0) - 1
    if count <= 0:
        _connection_counts.pop(username, None)
    else:
        _connection_counts[username] = count


def is_online(username: str) -> bool:
    return username in _connection_counts


def online_usernames() -> Set[str]:
    return set(_connection_counts.keys())


def online_count() -> int:
    """Number of distinct users currently connected."""
    return len(_connection_counts)
