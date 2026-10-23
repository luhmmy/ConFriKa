"""Reachability / privacy controls: who may call or message a user.

Each user chooses, per channel, whether 'everyone', only their 'contacts', or
'nobody' may reach them — so a stranger spotted in Global Spaces can't suddenly
call or spam them. Enforced server-side so it can't be bypassed by the client.
"""
from __future__ import annotations

from typing import Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from ..database.models import User, UserContact
from .auth_service import normalize_username


async def _is_contact(db: AsyncSession, owner: User, other_username: str) -> bool:
    other = normalize_username(other_username)
    row = await db.scalar(
        select(UserContact).where(
            (UserContact.user_id == owner.id)
            & (UserContact.contact_username == other)
        )
    )
    return row is not None


async def reachability_block(
    db: AsyncSession, target: User, sender_username: str, action: str
) -> Optional[str]:
    """Return a user-facing reason if `sender` may NOT `action` `target`, else None.

    action: 'call' | 'message'.
    """
    noun = "calls" if action == "call" else "messages"
    setting = (
        target.calls_privacy if action == "call" else target.messages_privacy
    )
    setting = (setting or "everyone").lower()

    if setting == "everyone":
        return None
    if setting == "nobody":
        return f"{target.full_name} isn’t accepting {noun} right now."
    if setting == "contacts":
        if await _is_contact(db, target, sender_username):
            return None
        return f"{target.full_name} only accepts {noun} from their contacts."
    return None
